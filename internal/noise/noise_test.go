package noise

import (
	"bytes"
	"crypto/rand"
	"testing"

	reference "github.com/flynn/noise"
	"golang.org/x/crypto/chacha20poly1305"
)

// Ces tests confrontent notre poignée de main à flynn/noise, une
// implémentation indépendante et largement utilisée. Si un seul octet de
// notre assemblage était faux, les clés ne tomberaient pas d'accord.

var prologue = []byte("CyberSas essai")

func suite() reference.CipherSuite {
	return reference.NewCipherSuite(reference.DH25519, reference.CipherChaChaPoly, reference.HashBLAKE2s)
}

func paireReference(t *testing.T) reference.DHKey {
	k, err := suite().GenerateKeypair(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

// Chiffre avec une clé de transport de chez nous, au compteur 0.
func sceller(t *testing.T, cle [32]byte, clair []byte) []byte {
	a, err := chacha20poly1305.New(cle[:])
	if err != nil {
		t.Fatal(err)
	}
	return a.Seal(nil, Nonce(0), clair, nil)
}

func ouvrir(t *testing.T, cle [32]byte, c []byte) []byte {
	a, _ := chacha20poly1305.New(cle[:])
	clair, err := a.Open(nil, Nonce(0), c, nil)
	if err != nil {
		t.Fatalf("déchiffrement impossible avec la clé de session : %v", err)
	}
	return clair
}

func TestNotreInitiateurContreLaReference(t *testing.T) {
	serveur := paireReference(t)
	nous, _ := GenererCle()

	rep, err := reference.NewHandshakeState(reference.Config{
		CipherSuite: suite(), Random: rand.Reader, Pattern: reference.HandshakeIK,
		Prologue: prologue, StaticKeypair: serveur,
	})
	if err != nil {
		t.Fatal(err)
	}

	init := NouvelInitiateur(nous, serveur.Public, prologue)
	m1, err := init.Message1([]byte("horodatage"))
	if err != nil {
		t.Fatal(err)
	}
	charge, _, _, err := rep.ReadMessage(nil, m1)
	if err != nil {
		t.Fatalf("la référence refuse notre message 1 : %v", err)
	}
	if string(charge) != "horodatage" {
		t.Fatalf("charge lue par la référence : %q", charge)
	}
	if !bytes.Equal(rep.PeerStatic(), nous.PublicKey().Bytes()) {
		t.Fatal("la référence n'a pas retrouvé notre clé statique")
	}

	m2, versRep, versInit, err := rep.WriteMessage(nil, []byte("ok"))
	if err != nil {
		t.Fatal(err)
	}
	c, cles, err := init.LireMessage2(m2)
	if err != nil {
		t.Fatalf("nous refusons le message 2 de la référence : %v", err)
	}
	if string(c) != "ok" {
		t.Fatalf("charge du message 2 : %q", c)
	}

	// Aller : nous chiffrons, la référence déchiffre.
	clair, err := versRep.Decrypt(nil, nil, sceller(t, cles.Envoi, []byte("aller")))
	if err != nil || string(clair) != "aller" {
		t.Fatalf("clé d'envoi différente de celle de la référence : %v", err)
	}
	// Retour : la référence chiffre, nous déchiffrons.
	c2, err := versInit.Encrypt(nil, nil, []byte("retour"))
	if err != nil {
		t.Fatal(err)
	}
	if string(ouvrir(t, cles.Reception, c2)) != "retour" {
		t.Fatal("clé de réception différente de celle de la référence")
	}
}

func TestLaReferenceContreNotreRepondeur(t *testing.T) {
	client := paireReference(t)
	nous, _ := GenererCle()

	ini, err := reference.NewHandshakeState(reference.Config{
		CipherSuite: suite(), Random: rand.Reader, Pattern: reference.HandshakeIK, Initiator: true,
		Prologue: prologue, StaticKeypair: client, PeerStatic: nous.PublicKey().Bytes(),
	})
	if err != nil {
		t.Fatal(err)
	}
	m1, _, _, err := ini.WriteMessage(nil, []byte("bonjour"))
	if err != nil {
		t.Fatal(err)
	}

	rep := NouveauRepondeur(nous, prologue)
	publique, charge, err := rep.LireMessage1(m1)
	if err != nil {
		t.Fatalf("nous refusons le message 1 de la référence : %v", err)
	}
	if !bytes.Equal(publique, client.Public) || string(charge) != "bonjour" {
		t.Fatal("clé ou charge du client mal lue")
	}
	m2, cles, err := rep.Message2(nil)
	if err != nil {
		t.Fatal(err)
	}
	_, versRep, versInit, err := ini.ReadMessage(nil, m2)
	if err != nil {
		t.Fatalf("la référence refuse notre message 2 : %v", err)
	}

	c, _ := versRep.Encrypt(nil, nil, []byte("aller"))
	if string(ouvrir(t, cles.Reception, c)) != "aller" {
		t.Fatal("clé de réception différente de celle de la référence")
	}
	clair, err := versInit.Decrypt(nil, nil, sceller(t, cles.Envoi, []byte("retour")))
	if err != nil || string(clair) != "retour" {
		t.Fatalf("clé d'envoi différente de celle de la référence : %v", err)
	}
}

func TestMauvaiseCleServeur(t *testing.T) {
	vrai, _ := GenererCle()
	faux, _ := GenererCle()
	client, _ := GenererCle()
	// Le client croit parler à « faux » : le vrai serveur ne doit rien lire.
	m1, _ := NouvelInitiateur(client, faux.PublicKey().Bytes(), prologue).Message1(nil)
	if _, _, err := NouveauRepondeur(vrai, prologue).LireMessage1(m1); err == nil {
		t.Fatal("un message destiné à une autre clé a été accepté")
	}
}

func TestMessageModifie(t *testing.T) {
	serveur, _ := GenererCle()
	client, _ := GenererCle()
	m1, _ := NouvelInitiateur(client, serveur.PublicKey().Bytes(), prologue).Message1([]byte("x"))
	for i := range m1 {
		abime := append([]byte(nil), m1...)
		abime[i] ^= 0x01
		if _, _, err := NouveauRepondeur(serveur, prologue).LireMessage1(abime); err == nil {
			t.Fatalf("octet %d modifié, message accepté quand même", i)
		}
	}
}

func TestReponseForgeeNeCassePasLaPoignee(t *testing.T) {
	serveur, _ := GenererCle()
	client, _ := GenererCle()
	ini := NouvelInitiateur(client, serveur.PublicKey().Bytes(), prologue)
	m1, _ := ini.Message1(nil)
	rep := NouveauRepondeur(serveur, prologue)
	rep.LireMessage1(m1)
	m2, _, _ := rep.Message2(nil)

	// Un attaquant répond le premier, avec n'importe quoi.
	faux := make([]byte, len(m2))
	rand.Read(faux)
	if _, _, err := ini.LireMessage2(faux); err == nil {
		t.Fatal("réponse forgée acceptée")
	}
	// La vraie réponse doit toujours passer.
	if _, _, err := ini.LireMessage2(m2); err != nil {
		t.Fatalf("la vraie réponse est refusée après une réponse forgée : %v", err)
	}
}

func TestProloguesDifferents(t *testing.T) {
	serveur, _ := GenererCle()
	client, _ := GenererCle()
	m1, _ := NouvelInitiateur(client, serveur.PublicKey().Bytes(), []byte("v1")).Message1(nil)
	if _, _, err := NouveauRepondeur(serveur, []byte("v2")).LireMessage1(m1); err == nil {
		t.Fatal("deux versions du protocole se sont comprises")
	}
}
