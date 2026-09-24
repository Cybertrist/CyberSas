// Package serveur assemble le serveur CyberSas : l'API où les appareils
// s'inscrivent, le moteur du tunnel, le pare-feu et le DNS du VPN.
//
// Une seule fonction décide de l'état du réseau : Synchroniser. Elle relit
// l'équipe, la politique et les appareils, retire ce qui n'a plus lieu
// d'être, puis pousse le résultat au moteur, à nftables et au DNS. Elle
// tourne à chaque inscription, et toutes les cinq secondes, pour prendre
// en compte une modification faite à la main.
package serveur

import (
	"context"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"log/slog"
	"net/netip"
	"os"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/Cybertrist/CyberSas/internal/base"
	"github.com/Cybertrist/CyberSas/internal/dns"
	"github.com/Cybertrist/CyberSas/internal/politique"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
	"github.com/Cybertrist/CyberSas/internal/verrou"
	"github.com/coreos/go-oidc/v3/oidc"
)

type Config struct {
	Domaine       string       // pour le point du tunnel : vpn.<domaine>
	Point         string       // hôte:port UDP annoncé aux appareils
	Reseau        netip.Prefix // 10.77.0.0/24
	Serveur       netip.Addr   // 10.77.0.1
	Interface     string       // sas0
	Equipe        string       // fichier « adresse groupe »
	Politique     string       // fichier JSON
	ClientsGoogle string       // fichier : un identifiant client OAuth par ligne
	Verrou        string       // fichier : clé publique du verrou, en base64 ; absent sans verrou
	DureeAppareil time.Duration
}

type Serveur struct {
	cfg      Config
	base     *base.Base
	moteur   *tunnel.Moteur
	dns      *dns.Serveur
	prive    *ecdh.PrivateKey
	publique string
	journal  *slog.Logger

	mu        sync.Mutex
	flux      []politique.Flux
	signature string

	// relations : les paires de numéros d'appareils que le moteur a le
	// droit de relayer. Lues à chaque trame, d'où un verrou à part.
	muRelations sync.RWMutex
	relations   map[[2]uint32]bool

	// La vérification Google a son propre verrou : aller chercher les clés
	// de Google peut prendre du temps, et ne doit pas bloquer le reste.
	muGoogle sync.Mutex
	verif    *oidc.IDTokenVerifier
}

// Relie dit si le moteur peut relayer une trame de l'appareil de vers
// l'appareil vers. Appelée pour chaque trame relayée.
func (s *Serveur) Relie(de, vers uint32) bool {
	s.muRelations.RLock()
	defer s.muRelations.RUnlock()
	return s.relations[[2]uint32{de, vers}]
}

// verrou : la clé publique du verrou, si l'admin en a mis un.
func (s *Serveur) verrou() (ed25519.PublicKey, string) {
	if s.cfg.Verrou == "" {
		return nil, ""
	}
	b, err := os.ReadFile(s.cfg.Verrou)
	if err != nil {
		return nil, ""
	}
	texte := strings.TrimSpace(string(b))
	pub, err := verrou.LirePublique(texte)
	if err != nil {
		s.journal.Error("clé du verrou illisible", "erreur", err)
		return nil, ""
	}
	return pub, texte
}

func Nouveau(cfg Config, b *base.Base, m *tunnel.Moteur, d *dns.Serveur, prive *ecdh.PrivateKey, journal *slog.Logger) *Serveur {
	if journal == nil {
		journal = slog.New(slog.DiscardHandler)
	}
	return &Serveur{cfg: cfg, base: b, moteur: m, dns: d, journal: journal, prive: prive,
		publique: base64.StdEncoding.EncodeToString(prive.PublicKey().Bytes())}
}

func jetonAleatoire() string {
	b := make([]byte, 32)
	rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

func (s *Serveur) chargerEquipe() politique.Equipe {
	e, err := politique.ChargerEquipe(s.cfg.Equipe)
	if err != nil {
		s.journal.Error("équipe illisible, personne n'entre", "erreur", err)
		return politique.Equipe{}
	}
	return e
}

// Synchroniser remet le réseau en accord avec l'équipe, la politique et la
// base. Elle ne touche au noyau que si quelque chose a changé.
func (s *Serveur) Synchroniser() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	equipe := s.chargerEquipe()
	pol, err := politique.Charger(s.cfg.Politique)
	if err != nil {
		// Politique cassée : on garde l'ancienne plutôt que d'ouvrir ou de
		// fermer tout le réseau sur une faute de frappe.
		return fmt.Errorf("politique : %w", err)
	}
	appareils, err := s.base.Appareils()
	if err != nil {
		return err
	}

	now := time.Now()
	var gardes []base.Appareil
	for _, a := range appareils {
		raison := ""
		switch {
		case !a.Expire.IsZero() && now.After(a.Expire):
			raison = "inscription expirée"
		case a.Proprietaire != "" && equipe[a.Proprietaire] == "":
			raison = "propriétaire sorti de l'équipe"
		}
		if raison != "" {
			s.base.Supprimer(a.ID)
			s.journal.Warn("appareil retiré", "evenement", "retrait", "appareil", a.Nom, "proprietaire", a.Proprietaire, "raison", raison)
			continue
		}
		gardes = append(gardes, a)
	}

	var pairs []tunnel.Pair
	var apps []politique.Appareil
	numeros := map[netip.Addr]uint32{}
	noms := map[string]netip.Addr{"serveur": s.cfg.Serveur}
	var sig strings.Builder
	for _, a := range gardes {
		cle, err := base64.StdEncoding.DecodeString(a.ClePublique)
		if err != nil || len(cle) != 32 {
			continue
		}
		var pub [32]byte
		copy(pub[:], cle)
		// Côté serveur, aucun filtre dans le moteur : ce qui s'adresse au
		// serveur lui-même passe par le pare-feu du noyau.
		pairs = append(pairs, tunnel.Pair{Publique: pub, Adresses: []netip.Prefix{netip.PrefixFrom(a.Adresse, 32)},
			Numero: uint32(a.ID), ToutEntrant: true})
		apps = append(apps, politique.Appareil{Adresse: a.Adresse, Proprietaire: a.Proprietaire, Etiquette: a.Etiquette})
		numeros[a.Adresse] = uint32(a.ID)
		noms[a.Nom] = a.Adresse
		fmt.Fprintf(&sig, "%d %s %s %s %s %s|", a.ID, a.Nom, a.ClePublique, a.Adresse, a.Proprietaire, a.Etiquette)
	}
	flux := pol.Compiler(equipe, apps, s.cfg.Serveur)
	regles := politique.Nft(flux, s.cfg.Interface, s.cfg.Serveur)
	sig.WriteString(regles)
	if sig.String() == s.signature {
		return nil
	}

	relations := map[[2]uint32]bool{}
	for paire := range politique.Relations(flux, s.cfg.Serveur) {
		de, vers := numeros[paire[0]], numeros[paire[1]]
		if de != 0 && vers != 0 {
			relations[[2]uint32{de, vers}] = true
		}
	}
	s.muRelations.Lock()
	s.relations = relations
	s.muRelations.Unlock()

	s.moteur.DefinirPairs(pairs)
	if err := appliquerPareFeu(regles); err != nil {
		return err
	}
	s.dns.Definir(noms)
	s.flux, s.signature = flux, sig.String()
	s.journal.Info("réseau synchronisé", "evenement", "synchronisation", "appareils", len(gardes),
		"flux", len(flux), "relations", len(relations)/2)
	return nil
}

// Boucle : une synchronisation toutes les cinq secondes.
func (s *Serveur) Boucle(ctx context.Context) {
	t := time.NewTicker(5 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if err := s.Synchroniser(); err != nil {
				s.journal.Error("synchronisation", "erreur", err)
			}
		}
	}
}

func (s *Serveur) clientsGoogle() []string {
	b, err := os.ReadFile(s.cfg.ClientsGoogle)
	if err != nil {
		return nil
	}
	var r []string
	for _, l := range strings.Fields(string(b)) {
		if strings.HasSuffix(l, ".apps.googleusercontent.com") && !strings.HasPrefix(l, "a-remplir") {
			r = append(r, l)
		}
	}
	return r
}

// verifierGoogle valide un jeton d'identité Google : signature par les
// clés publiées par Google, émetteur, expiration, et surtout destinataire.
// Un jeton émis pour une autre application ne passe pas.
func (s *Serveur) verifierGoogle(ctx context.Context, jeton string) (string, error) {
	clients := s.clientsGoogle()
	if len(clients) == 0 {
		return "", fmt.Errorf("aucun client Google configuré")
	}
	s.muGoogle.Lock()
	if s.verif == nil {
		p, err := oidc.NewProvider(ctx, "https://accounts.google.com")
		if err != nil {
			s.muGoogle.Unlock()
			return "", fmt.Errorf("Google injoignable : %w", err)
		}
		s.verif = p.Verifier(&oidc.Config{SkipClientIDCheck: true})
	}
	v := s.verif
	s.muGoogle.Unlock()

	tok, err := v.Verify(ctx, jeton)
	if err != nil {
		return "", err
	}
	if !slices.ContainsFunc(tok.Audience, func(a string) bool { return slices.Contains(clients, a) }) {
		return "", fmt.Errorf("jeton émis pour une autre application")
	}
	var c struct {
		Email   string `json:"email"`
		Verifie bool   `json:"email_verified"`
	}
	if err := tok.Claims(&c); err != nil {
		return "", err
	}
	if !c.Verifie || c.Email == "" {
		return "", fmt.Errorf("adresse non vérifiée par Google")
	}
	return strings.ToLower(c.Email), nil
}

// appliquerPareFeu charge les règles dans le noyau. Variable pour que les
// tests, qui n'ont pas de noyau à configurer, la remplacent.
var appliquerPareFeu = politique.Appliquer
