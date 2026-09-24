package verrou

import (
	"net/netip"
	"testing"
)

func TestSignature(t *testing.T) {
	pub, prive, _ := Generer()
	var cle [32]byte
	cle[0] = 7
	a := netip.MustParseAddr("10.77.0.5")
	sig := Signer(prive, cle, a)
	if !Verifier(pub, cle, a, sig) {
		t.Fatal("signature valide refusée")
	}
	// Même clé, autre adresse : le serveur ne peut pas réattribuer.
	if Verifier(pub, cle, netip.MustParseAddr("10.77.0.6"), sig) {
		t.Fatal("signature acceptée pour une autre adresse")
	}
	// Autre clé, même adresse : le serveur ne peut pas substituer.
	autre := cle
	autre[0] = 8
	if Verifier(pub, autre, a, sig) {
		t.Fatal("signature acceptée pour une autre clé")
	}
	// Autre verrou.
	pub2, _, _ := Generer()
	if Verifier(pub2, cle, a, sig) {
		t.Fatal("signature acceptée par un autre verrou")
	}
	if Verifier(pub, cle, a, nil) || Verifier(nil, cle, a, sig) {
		t.Fatal("entrée vide acceptée")
	}
}
