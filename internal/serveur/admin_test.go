package serveur

import (
	"encoding/base64"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Cybertrist/CyberSas/internal/b64"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

// Le libellé : pris du nom proposé à l'inscription, changé par l'appareil
// lui-même, jamais par un autre membre de l'équipe.
func TestLibelle(t *testing.T) {
	b := nouveauBanc(t)
	alice := b.inscrire("", "alice@x.fr", "Portable d'Alice")
	bob := b.inscrire("", "bob@x.fr", "tel")
	if alice.Appareil.Libelle != "Portable d'Alice" || alice.Appareil.Nom != "portable-d-alice-alice" {
		t.Fatalf("inscrit : nom %q, libellé %q", alice.Appareil.Nom, alice.Appareil.Libelle)
	}
	if code := b.appel("POST", protocole.CheminLibelle, alice.Jeton, protocole.DemandeLibelle{Libelle: "  Z Fold8 Alice \x1b "}, nil); code != http.StatusOK {
		t.Fatalf("renommer le sien : %d", code)
	}
	var r protocole.EtatReseau
	b.appel("GET", protocole.CheminReseau, alice.Jeton, nil, &r)
	if r.Moi.Libelle != "Z Fold8 Alice" {
		t.Errorf("libellé relu : %q", r.Moi.Libelle)
	}
	// Bob n'est pas admin : il ne renomme pas l'appareil d'Alice.
	autre := protocole.DemandeLibelle{ClePublique: alice.Appareil.ClePublique, Libelle: "pirate"}
	if code := b.appel("POST", protocole.CheminLibelle, bob.Jeton, autre, nil); code != http.StatusForbidden {
		t.Errorf("renommer celui d'un autre : %d, 403 attendu", code)
	}
	if code := b.appel("POST", protocole.CheminLibelle, alice.Jeton, protocole.DemandeLibelle{Libelle: " \t "}, nil); code != http.StatusBadRequest {
		t.Errorf("nom vide : %d, 400 attendu", code)
	}
}

// Les routes des admins : fermées aux autres ; ouvertes, elles n'acceptent
// que des certificats vraiment signés par le verrou.
func TestRoutesAdmin(t *testing.T) {
	b := nouveauBanc(t)
	pub, prive, _ := verrou.Generer()
	cheminVerrou := filepath.Join(b.dossier, "verrou")
	os.WriteFile(cheminVerrou, []byte(base64.StdEncoding.EncodeToString(pub)), 0o600)
	b.srv.cfg.Verrou = cheminVerrou
	os.WriteFile(b.srv.cfg.Equipe, []byte("admin@x.fr admins\nalice@x.fr equipe\n"), 0o600)

	admin := b.inscrire("", "admin@x.fr", "fold")
	alice := b.inscrire("", "alice@x.fr", "portable")

	for _, c := range []struct{ methode, chemin string }{
		{"GET", protocole.CheminAppareils}, {"POST", protocole.CheminSignatures}, {"POST", protocole.CheminRetrait},
	} {
		if code := b.appel(c.methode, c.chemin, alice.Jeton, []protocole.Appareil{}, nil); code != http.StatusForbidden {
			t.Errorf("%s sans être admin : %d, 403 attendu", c.chemin, code)
		}
	}

	var liste []protocole.Appareil
	if code := b.appel("GET", protocole.CheminAppareils, admin.Jeton, nil, &liste); code != http.StatusOK || len(liste) != 2 {
		t.Fatalf("liste : %d, %d appareils", code, len(liste))
	}
	var fiche protocole.Appareil
	for _, a := range liste {
		if a.ClePublique == alice.Appareil.ClePublique {
			fiche = a
		}
	}
	if fiche.Signature != "" || fiche.Groupe != "equipe" {
		t.Fatalf("fiche d'Alice : %+v", fiche)
	}

	// Un certificat signé par une autre clé : refusé.
	_, faux, _ := verrou.Generer()
	signer := func(cle []byte) protocole.Appareil {
		k, _ := b64.Cle32(fiche.ClePublique)
		c := verrou.Certificat{Cle: k, Adresse: netip.MustParseAddr(fiche.Adresse), Proprietaire: fiche.Proprietaire,
			Groupe: fiche.Groupe, Expire: time.Now().Add(24 * time.Hour).Truncate(time.Second)}
		sig, err := c.Signer(cle)
		if err != nil {
			t.Fatal(err)
		}
		a := fiche
		a.Signature, a.SignatureExpire = base64.StdEncoding.EncodeToString(sig), c.Expire
		return a
	}
	if code := b.appel("POST", protocole.CheminSignatures, admin.Jeton, []protocole.Appareil{signer(faux)}, nil); code != http.StatusBadRequest {
		t.Errorf("certificat d'une autre clé : %d, 400 attendu", code)
	}
	// Signé par le verrou : accepté, et Alice le voit.
	if code := b.appel("POST", protocole.CheminSignatures, admin.Jeton, []protocole.Appareil{signer(prive)}, nil); code != http.StatusOK {
		t.Fatalf("vrai certificat : %d", code)
	}
	var r protocole.EtatReseau
	b.appel("GET", protocole.CheminReseau, alice.Jeton, nil, &r)
	if r.Moi.Signature == "" {
		t.Error("Alice ne voit pas son certificat")
	}

	// Retrait : pas de soi-même ; celui d'Alice, oui.
	if code := b.appel("POST", protocole.CheminRetrait, admin.Jeton, protocole.DemandeRetrait{ClePublique: admin.Appareil.ClePublique}, nil); code != http.StatusBadRequest {
		t.Errorf("se retirer soi-même : %d, 400 attendu", code)
	}
	if code := b.appel("POST", protocole.CheminRetrait, admin.Jeton, protocole.DemandeRetrait{ClePublique: alice.Appareil.ClePublique}, nil); code != http.StatusOK {
		t.Errorf("retirer Alice : %d", code)
	}
	if code := b.appel("GET", protocole.CheminReseau, alice.Jeton, nil, nil); code != http.StatusUnauthorized {
		t.Errorf("Alice retirée répond encore : %d", code)
	}
}
