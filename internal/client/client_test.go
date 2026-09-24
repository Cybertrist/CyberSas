package client

import (
	"crypto/rand"
	"encoding/base64"
	"net/netip"
	"testing"

	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

func b64(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return base64.StdEncoding.EncodeToString(b)
}

func TestConstruireAvecVerrou(t *testing.T) {
	pubV, priveV, _ := verrou.Generer()
	texteV := base64.StdEncoding.EncodeToString(pubV)
	cleServeur := b64(32)
	signe, intrus := b64(32), b64(32)
	k, _ := cle32(signe)
	sig := verrou.Signer(priveV, k, netip.MustParseAddr("10.77.0.2"))

	r := protocole.EtatReseau{
		Serveur: protocole.Serveur{ClePublique: cleServeur, Adresse: "10.77.0.1"},
		Verrou:  texteV,
		Pairs: []protocole.Appareil{
			{Numero: 2, Nom: "maison", Adresse: "10.77.0.2", ClePublique: signe, Signature: base64.StdEncoding.EncodeToString(sig)},
			// Un serveur piraté glisse sa propre clé sous un autre nom.
			{Numero: 9, Nom: "maison-bis", Adresse: "10.77.0.9", ClePublique: intrus},
			// Ou réutilise une signature valide pour une autre adresse.
			{Numero: 3, Nom: "vol", Adresse: "10.77.0.3", ClePublique: signe, Signature: base64.StdEncoding.EncodeToString(sig)},
		},
		Entrant: []protocole.RegleEntrante{{Sources: []string{"10.77.0.2"}, Ports: []string{"tcp:22"}}},
	}
	pairs, ecartes, err := Construire(r, cleServeur, texteV, netip.MustParseAddrPort("192.0.2.1:51820"))
	if err != nil {
		t.Fatal(err)
	}
	if len(pairs) != 2 || pairs[1].Numero != 2 {
		t.Fatalf("attendu : le serveur et maison seulement, obtenu %d pairs", len(pairs))
	}
	if len(pairs[1].Entrant) != 1 || pairs[1].Entrant[0].Debut != 22 {
		t.Fatal("la règle entrante de maison n'a pas suivi")
	}
	if len(ecartes) != 2 {
		t.Fatalf("les deux pairs non signés auraient dû être écartés : %v", ecartes)
	}
}

func TestConstruireRefuseAutreServeur(t *testing.T) {
	r := protocole.EtatReseau{Serveur: protocole.Serveur{ClePublique: b64(32), Adresse: "10.77.0.1"}}
	if _, _, err := Construire(r, b64(32), "", netip.AddrPort{}); err == nil {
		t.Fatal("une clé de serveur différente de celle retenue a été acceptée")
	}
}

func TestConstruireRefuseAutreVerrou(t *testing.T) {
	a, _, _ := verrou.Generer()
	b, _, _ := verrou.Generer()
	cle := b64(32)
	r := protocole.EtatReseau{Serveur: protocole.Serveur{ClePublique: cle, Adresse: "10.77.0.1"},
		Verrou: base64.StdEncoding.EncodeToString(b)}
	if _, _, err := Construire(r, cle, base64.StdEncoding.EncodeToString(a), netip.AddrPort{}); err == nil {
		t.Fatal("un changement de verrou a été accepté")
	}
	// Retirer le verrou n'est pas plus accepté : ce serait le contourner.
	r.Verrou = ""
	if _, _, err := Construire(r, cle, base64.StdEncoding.EncodeToString(a), netip.AddrPort{}); err == nil {
		t.Fatal("la disparition du verrou a été acceptée")
	}
}
