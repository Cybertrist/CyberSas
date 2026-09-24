package serveur

import (
	"bytes"
	"crypto/ecdh"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Cybertrist/CyberSas/internal/base"
	"github.com/Cybertrist/CyberSas/internal/dns"
	"github.com/Cybertrist/CyberSas/internal/noise"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
)

// Ces tests font tourner l'API pour de vrai, sans réseau ni noyau : une
// base SQLite dans un dossier temporaire, un moteur qui ne tourne pas, et
// un pare-feu remplacé par une fonction qui ne fait rien.

type tunMuet struct{}

func (tunMuet) Read([]byte) (int, error)    { select {} }
func (tunMuet) Write(b []byte) (int, error) { return len(b), nil }
func (tunMuet) Close() error                { return nil }

type banc struct {
	t     *testing.T
	srv   *Serveur
	http  *httptest.Server
	base  *base.Base
	prive *ecdh.PrivateKey
}

func nouveauBanc(t *testing.T) *banc {
	appliquerPareFeu = func(string) error { return nil }
	dossier := t.TempDir()
	ecrire := func(nom, contenu string) string {
		chemin := filepath.Join(dossier, nom)
		os.WriteFile(chemin, []byte(contenu), 0o600)
		return chemin
	}
	cfg := Config{
		Point: "vpn.essai:51820", Reseau: netip.MustParsePrefix("10.77.0.0/24"), Serveur: netip.MustParseAddr("10.77.0.1"),
		Interface: "sas0",
		Equipe:    ecrire("equipe.txt", "alice@x.fr equipe\n"),
		Politique: ecrire("politique.json", `{"regles": [
			{"de": ["groupe:equipe"], "vers": ["etiquette:maison"], "ports": ["tcp:80"]}
		]}`),
		ClientsGoogle: ecrire("clients", "a-remplir.apps.googleusercontent.com\n"),
		DureeAppareil: time.Hour,
	}
	b, err := base.Ouvrir(filepath.Join(dossier, "sas.db"))
	if err != nil {
		t.Fatal(err)
	}
	prive, _ := noise.GenererCle()
	m := tunnel.Nouveau(tunnel.Config{Prive: prive, Tun: tunMuet{}})
	srv := Nouveau(cfg, b, m, dns.Nouveau("sas.internal", "127.0.0.1:1"), prive, nil)
	h := httptest.NewServer(srv.Routes())
	t.Cleanup(h.Close)
	return &banc{t: t, srv: srv, http: h, base: b, prive: prive}
}

func (b *banc) appel(methode, chemin, jeton string, corps any, reponse any) int {
	var c []byte
	if corps != nil {
		c, _ = json.Marshal(corps)
	}
	req, _ := http.NewRequest(methode, b.http.URL+chemin, bytes.NewReader(c))
	if jeton != "" {
		req.Header.Set("Authorization", "Bearer "+jeton)
	}
	rep, err := http.DefaultClient.Do(req)
	if err != nil {
		b.t.Fatal(err)
	}
	defer rep.Body.Close()
	if reponse != nil {
		json.NewDecoder(rep.Body).Decode(reponse)
	}
	return rep.StatusCode
}

// demande : une inscription correcte pour cette clé, avec sa preuve.
func (b *banc) demande(k *ecdh.PrivateKey, cle, nom string) protocole.DemandeConnexion {
	h := time.Now().Unix()
	p, err := protocole.Prouver(k, b.prive.PublicKey().Bytes(), h)
	if err != nil {
		b.t.Fatal(err)
	}
	return protocole.DemandeConnexion{CleInscription: cle, Nom: nom,
		ClePublique: base64.StdEncoding.EncodeToString(k.PublicKey().Bytes()), Horodatage: h, Preuve: p}
}

func (b *banc) cle(etiquette, utilisateur string) string {
	c := "sas-essai-" + base64.RawURLEncoding.EncodeToString(noise.Nonce(uint64(time.Now().UnixNano())))
	if err := b.base.CreerCle(c, etiquette, utilisateur, time.Now().Add(time.Minute)); err != nil {
		b.t.Fatal(err)
	}
	return c
}

func TestInscriptionEtPreuve(t *testing.T) {
	b := nouveauBanc(t)
	k, _ := noise.GenererCle()

	// Sans preuve, ou avec la preuve d'une autre clé : refusé, et la clé
	// d'inscription n'est pas consommée.
	c := b.cle("maison", "")
	d := b.demande(k, c, "maison")
	sansPreuve := d
	sansPreuve.Preuve = ""
	if code := b.appel("POST", protocole.CheminConnexion, "", sansPreuve, nil); code != http.StatusUnauthorized {
		t.Fatalf("inscription sans preuve : %d, 401 attendu", code)
	}
	autre, _ := noise.GenererCle()
	volee := b.demande(autre, c, "maison")
	volee.ClePublique = d.ClePublique // la clé publique d'un autre, sans sa clé privée
	if code := b.appel("POST", protocole.CheminConnexion, "", volee, nil); code != http.StatusUnauthorized {
		t.Fatalf("inscription d'une clé qu'on ne détient pas : %d, 401 attendu", code)
	}

	var r protocole.ReponseConnexion
	if code := b.appel("POST", protocole.CheminConnexion, "", d, &r); code != http.StatusOK {
		t.Fatalf("inscription correcte : %d", code)
	}
	if r.Appareil.Adresse != "10.77.0.2" || r.Serveur.ClePublique != b.srv.publique || r.Jeton == "" {
		t.Fatalf("réponse inattendue : %+v", r)
	}
	// La clé d'inscription ne sert qu'une fois.
	if code := b.appel("POST", protocole.CheminConnexion, "", b.demande(k, c, "maison"), nil); code != http.StatusUnauthorized {
		t.Fatalf("clé réutilisée : %d, 401 attendu", code)
	}
}

func TestClePubliqueFaible(t *testing.T) {
	b := nouveauBanc(t)
	k, _ := noise.GenererCle()
	d := b.demande(k, b.cle("maison", ""), "x")
	d.ClePublique = base64.StdEncoding.EncodeToString(make([]byte, 32))
	if code := b.appel("POST", protocole.CheminConnexion, "", d, nil); code != http.StatusBadRequest {
		t.Fatalf("clé nulle : %d, 400 attendu", code)
	}
}

func TestPasDeRepriseDUneCleInscrite(t *testing.T) {
	b := nouveauBanc(t)
	k, _ := noise.GenererCle()
	if code := b.appel("POST", protocole.CheminConnexion, "", b.demande(k, b.cle("maison", ""), "maison"), nil); code != http.StatusOK {
		t.Fatalf("première inscription : %d", code)
	}
	// Même clé privée, mais pour le compte d'alice : la fiche ne change
	// pas de main.
	if code := b.appel("POST", protocole.CheminConnexion, "", b.demande(k, b.cle("", "alice@x.fr"), "pirate"), nil); code != http.StatusConflict {
		t.Fatalf("reprise d'une clé inscrite : %d, 409 attendu", code)
	}
}

func TestReseauNeMontreQueLesPairsRelies(t *testing.T) {
	b := nouveauBanc(t)
	inscrire := func(etiquette, utilisateur, nom string) protocole.ReponseConnexion {
		k, _ := noise.GenererCle()
		var r protocole.ReponseConnexion
		if code := b.appel("POST", protocole.CheminConnexion, "", b.demande(k, b.cle(etiquette, utilisateur), nom), &r); code != http.StatusOK {
			t.Fatalf("inscription de %s : %d", nom, code)
		}
		return r
	}
	maison := inscrire("maison", "", "maison")
	alice := inscrire("", "alice@x.fr", "portable")
	nas := inscrire("nas", "", "nas") // aucune règle ne le concerne

	if code := b.appel("GET", protocole.CheminReseau, "", nil, nil); code != http.StatusUnauthorized {
		t.Fatalf("état du réseau sans jeton : %d, 401 attendu", code)
	}
	var etat protocole.EtatReseau
	b.appel("GET", protocole.CheminReseau, alice.Jeton, nil, &etat)
	if len(etat.Pairs) != 1 || etat.Pairs[0].Nom != "maison" {
		t.Fatalf("alice devrait voir la maison, et seulement elle : %+v", etat.Pairs)
	}
	// Côté maison : alice est un pair, et peut ouvrir le TCP 80.
	b.appel("GET", protocole.CheminReseau, maison.Jeton, nil, &etat)
	if len(etat.Pairs) != 1 || etat.Pairs[0].Nom != "portable" {
		t.Fatalf("la maison devrait voir le portable d'alice : %+v", etat.Pairs)
	}
	if len(etat.Entrant) != 1 || etat.Entrant[0].Ports[0] != "tcp:80" {
		t.Fatalf("règle entrante de la maison : %+v", etat.Entrant)
	}
	// Le nas n'a aucune relation : il ne voit personne, personne ne le voit.
	b.appel("GET", protocole.CheminReseau, nas.Jeton, nil, &etat)
	if len(etat.Pairs) != 0 {
		t.Fatalf("le nas ne devrait voir personne : %+v", etat.Pairs)
	}
	if !b.srv.Relie(maison.Appareil.Numero, alice.Appareil.Numero) || b.srv.Relie(nas.Appareil.Numero, alice.Appareil.Numero) {
		t.Fatal("les relations du relais ne suivent pas la politique")
	}
}

func TestSortieDeLEquipe(t *testing.T) {
	b := nouveauBanc(t)
	k, _ := noise.GenererCle()
	var r protocole.ReponseConnexion
	b.appel("POST", protocole.CheminConnexion, "", b.demande(k, b.cle("", "alice@x.fr"), "portable"), &r)
	// Alice quitte l'équipe : à la synchronisation suivante, son appareil
	// disparaît, et son jeton ne vaut plus rien.
	os.WriteFile(b.srv.cfg.Equipe, []byte("# personne\n"), 0o600)
	if err := b.srv.Synchroniser(); err != nil {
		t.Fatal(err)
	}
	if code := b.appel("GET", protocole.CheminReseau, r.Jeton, nil, nil); code != http.StatusUnauthorized {
		t.Fatalf("appareil d'une personne sortie : %d, 401 attendu", code)
	}
}
