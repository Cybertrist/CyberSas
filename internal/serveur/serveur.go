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
	DureeAppareil time.Duration
}

type Serveur struct {
	cfg      Config
	base     *base.Base
	moteur   *tunnel.Moteur
	dns      *dns.Serveur
	publique string
	journal  *slog.Logger

	mu        sync.Mutex
	flux      []politique.Flux
	signature string
	verif     *oidc.IDTokenVerifier
}

func Nouveau(cfg Config, b *base.Base, m *tunnel.Moteur, d *dns.Serveur, publique []byte, journal *slog.Logger) *Serveur {
	return &Serveur{cfg: cfg, base: b, moteur: m, dns: d, journal: journal,
		publique: base64.StdEncoding.EncodeToString(publique)}
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
	noms := map[string]netip.Addr{"serveur": s.cfg.Serveur}
	var sig strings.Builder
	for _, a := range gardes {
		cle, err := base64.StdEncoding.DecodeString(a.ClePublique)
		if err != nil || len(cle) != 32 {
			continue
		}
		var pub [32]byte
		copy(pub[:], cle)
		pairs = append(pairs, tunnel.Pair{Publique: pub, Adresses: []netip.Prefix{netip.PrefixFrom(a.Adresse, 32)}})
		apps = append(apps, politique.Appareil{Adresse: a.Adresse, Proprietaire: a.Proprietaire, Etiquette: a.Etiquette})
		noms[a.Nom] = a.Adresse
		fmt.Fprintf(&sig, "%s %s %s %s %s|", a.Nom, a.ClePublique, a.Adresse, a.Proprietaire, a.Etiquette)
	}
	flux := pol.Compiler(equipe, apps, s.cfg.Serveur)
	regles := politique.Nft(flux, s.cfg.Interface, s.cfg.Serveur)
	sig.WriteString(regles)
	if sig.String() == s.signature {
		return nil
	}

	s.moteur.DefinirPairs(pairs)
	if err := politique.Appliquer(regles); err != nil {
		return err
	}
	s.dns.Definir(noms)
	s.flux, s.signature = flux, sig.String()
	s.journal.Info("réseau synchronisé", "evenement", "synchronisation", "appareils", len(gardes), "flux", len(flux))
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
	s.mu.Lock()
	if s.verif == nil {
		p, err := oidc.NewProvider(ctx, "https://accounts.google.com")
		if err != nil {
			s.mu.Unlock()
			return "", fmt.Errorf("Google injoignable : %w", err)
		}
		s.verif = p.Verifier(&oidc.Config{SkipClientIDCheck: true})
	}
	v := s.verif
	s.mu.Unlock()

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
