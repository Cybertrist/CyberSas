package appareil

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// L'état survit à un aller-retour sur disque, autorité comprise, et reste
// lisible par l'appareil seul.
func TestStockageAllerRetour(t *testing.T) {
	s := Stockage{Dossier: filepath.Join(t.TempDir(), "sas")}
	e := Etat{Serveur: "https://vpn.exemple.fr", ClePrivee: "cle", Autorite: "-----BEGIN CERTIFICATE-----"}
	if err := s.Ecrire(e); err != nil {
		t.Fatal(err)
	}
	lu, err := s.Lire()
	if err != nil {
		t.Fatal(err)
	}
	if lu.Serveur != e.Serveur || lu.ClePrivee != e.ClePrivee || lu.Autorite != e.Autorite {
		t.Fatalf("relu %+v, écrit %+v", lu, e)
	}
	if runtime.GOOS != "windows" {
		if st, _ := os.Stat(s.Fichier()); st.Mode().Perm() != 0o600 {
			t.Errorf("fichier en %v, attendu 0600", st.Mode().Perm())
		}
		if st, _ := os.Stat(s.Dossier); st.Mode().Perm() != 0o700 {
			t.Errorf("dossier en %v, attendu 0700", st.Mode().Perm())
		}
	}
	// Pas de fichier temporaire laissé derrière.
	if _, err := os.Stat(s.Fichier() + ".tmp"); !os.IsNotExist(err) {
		t.Error("le fichier temporaire est resté")
	}
}

// Effacer un état absent n'est pas une erreur ; effacer un état présent
// le fait disparaître.
func TestEffacer(t *testing.T) {
	s := Stockage{Dossier: t.TempDir()}
	if err := s.Effacer(); err != nil {
		t.Fatalf("effacer sans état : %v", err)
	}
	if err := s.Ecrire(Etat{ClePrivee: "cle"}); err != nil {
		t.Fatal(err)
	}
	if err := s.Effacer(); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Lire(); !os.IsNotExist(err) {
		t.Errorf("l'état est encore lisible : %v", err)
	}
}
