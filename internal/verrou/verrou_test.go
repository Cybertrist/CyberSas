package verrou

import (
	"errors"
	"net/netip"
	"strings"
	"testing"
	"time"
)

func certificat() Certificat {
	var c Certificat
	c.Cle[0] = 7
	c.Adresse = netip.MustParseAddr("10.77.0.5")
	c.Etiquette = "maison"
	c.Expire = time.Now().Add(time.Hour)
	return c
}

func TestCertificat(t *testing.T) {
	pub, prive, _ := Generer()
	c := certificat()
	sig, err := c.Signer(prive)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	if !c.Verifier(pub, sig, now) {
		t.Fatal("certificat valide refusé")
	}
	// Chaque champ est couvert : en changer un seul invalide la signature.
	for nom, modif := range map[string]func(*Certificat){
		"adresse":      func(c *Certificat) { c.Adresse = netip.MustParseAddr("10.77.0.6") },
		"clé":          func(c *Certificat) { c.Cle[0] = 8 },
		"étiquette":    func(c *Certificat) { c.Etiquette = "nas" },
		"propriétaire": func(c *Certificat) { c.Proprietaire = "bob@x.fr" },
		"groupe":       func(c *Certificat) { c.Groupe = "admins" },
		"expiration":   func(c *Certificat) { c.Expire = c.Expire.Add(time.Hour) },
	} {
		autre := c
		modif(&autre)
		if autre.Verifier(pub, sig, now) {
			t.Errorf("signature toujours acceptée après changement de : %s", nom)
		}
	}
	// Les champs sont délimités : « ab » + « c » n'est pas « a » + « bc ».
	a, b := c, c
	a.Etiquette, a.Proprietaire = "ab", "c"
	b.Etiquette, b.Proprietaire = "a", "bc"
	ma, _ := a.Message()
	mb, _ := b.Message()
	if string(ma) == string(mb) {
		t.Fatal("deux certificats différents donnent le même message")
	}
	// Au-delà de 65 535 octets, la longueur déborderait et deux champs se
	// confondraient : tout texte plus long que MaxChamp est refusé.
	long := c
	long.Groupe = strings.Repeat("a", 1<<16+1)
	if _, err := long.Message(); !errors.Is(err, ErrChamp) {
		t.Fatalf("groupe de 64 Kio signable : %v", err)
	}
	long.Groupe = strings.Repeat("a", MaxChamp)
	if _, err := long.Message(); err != nil {
		t.Fatalf("groupe de %d octets refusé : %v", MaxChamp, err)
	}
	// Expiré : refusé.
	if c.Verifier(pub, sig, c.Expire.Add(time.Second)) {
		t.Fatal("certificat expiré accepté")
	}
	// Autre verrou.
	pub2, _, _ := Generer()
	if c.Verifier(pub2, sig, now) {
		t.Fatal("signature acceptée par un autre verrou")
	}
}

func TestAdresseIPv6Refusee(t *testing.T) {
	_, prive, _ := Generer()
	c := certificat()
	for _, a := range []string{"2001:db8::1", "::ffff:10.77.0.5"} {
		c.Adresse = netip.MustParseAddr(a)
		if _, err := c.Signer(prive); err == nil {
			t.Errorf("%s : une adresse non IPv4 a été signée", a)
		}
		if c.Verifier(nil, make([]byte, 64), time.Now()) {
			t.Errorf("%s acceptée", a)
		}
	}
}

func TestPolitiqueEtRevocations(t *testing.T) {
	pub, prive, _ := Generer()
	pol := []byte(`{"version": 3, "regles": []}`)
	sig := SignerPolitique(prive, 3, pol)
	if !VerifierPolitique(pub, 3, pol, sig) {
		t.Fatal("politique valide refusée")
	}
	if VerifierPolitique(pub, 2, pol, sig) || VerifierPolitique(pub, 3, append(pol, ' '), sig) {
		t.Fatal("politique modifiée ou mal numérotée acceptée")
	}

	var a, b [32]byte
	a[0], b[0] = 1, 2
	r := SignerRevocations(prive, 5, [][32]byte{a, b})
	if !VerifierRevocations(pub, 5, [][32]byte{b, a}, r) {
		t.Fatal("l'ordre des clés ne doit pas changer la signature")
	}
	if VerifierRevocations(pub, 5, [][32]byte{a}, r) {
		t.Fatal("une liste raccourcie a été acceptée")
	}
	// Un document d'un type ne se fait pas passer pour un autre.
	if VerifierPolitique(pub, 5, contenuRevocations([][32]byte{a, b}), r) {
		t.Fatal("une liste de révocation acceptée comme politique")
	}
}
