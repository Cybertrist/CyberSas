package noise

import (
	"bytes"
	"crypto/ecdh"
	"testing"

	reference "github.com/flynn/noise"
)

// Ces fuzz confrontent notre lecture des deux messages à celle de
// flynn/noise, sur des octets quelconques : les deux doivent accepter et
// refuser exactement les mêmes messages, et lire la même chose.

func cleFixe(t testing.TB, octet byte) *ecdh.PrivateKey {
	k, err := ClePrivee(bytes.Repeat([]byte{octet}, 32))
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func referenceDe(k *ecdh.PrivateKey) reference.DHKey {
	return reference.DHKey{Private: k.Bytes(), Public: k.PublicKey().Bytes()}
}

func FuzzLireMessage1(f *testing.F) {
	serveur, appareil := cleFixe(f, 1), cleFixe(f, 2)
	init := NouvelInitiateur(appareil, serveur.PublicKey().Bytes(), prologue)
	init.e = cleFixe(f, 3)
	m1, err := init.Message1([]byte("horodatage"))
	if err != nil {
		f.Fatal(err)
	}
	f.Add(m1)
	f.Add(m1[:TailleMsg1+tailleTag])
	f.Add(make([]byte, TailleMsg1+tailleTag))

	f.Fuzz(func(t *testing.T, m []byte) {
		publique, charge, err := NouveauRepondeur(serveur, prologue).LireMessage1(m)

		rep, errRef := reference.NewHandshakeState(reference.Config{
			CipherSuite: suite(), Pattern: reference.HandshakeIK,
			Prologue: prologue, StaticKeypair: referenceDe(serveur),
		})
		if errRef != nil {
			t.Fatal(errRef)
		}
		chargeRef, _, _, errRef := rep.ReadMessage(nil, m)

		if (err == nil) != (errRef == nil) {
			t.Fatalf("désaccord avec la référence : nous %v, elle %v", err, errRef)
		}
		if err != nil {
			return
		}
		if !bytes.Equal(publique, rep.PeerStatic()) || !bytes.Equal(charge, chargeRef) {
			t.Fatal("même message accepté, mais lu différemment")
		}
		// Sans la clé de l'appareil, seul le message qu'il a écrit passe.
		if !bytes.Equal(m, m1) {
			t.Fatalf("message forgé accepté : %x", m)
		}
	})
}

func FuzzLireMessage2(f *testing.F) {
	serveur, appareil := cleFixe(f, 1), cleFixe(f, 2)

	// Le message 2 valide, écrit par la référence en face du nôtre.
	preparer := func(t testing.TB) (*Initiateur, *reference.HandshakeState) {
		init := NouvelInitiateur(appareil, serveur.PublicKey().Bytes(), prologue)
		init.e = cleFixe(t, 3)
		m1, err := init.Message1(nil)
		if err != nil {
			t.Fatal(err)
		}
		ref, err := reference.NewHandshakeState(reference.Config{
			CipherSuite: suite(), Pattern: reference.HandshakeIK, Initiator: true,
			Prologue: prologue, StaticKeypair: referenceDe(appareil), PeerStatic: serveur.PublicKey().Bytes(),
			// flynn/noise tire toujours son éphémère : on lui donne un
			// hasard qui redonne les octets de cleFixe(3).
			Random: bytes.NewReader(bytes.Repeat([]byte{3}, 32)),
		})
		if err != nil {
			t.Fatal(err)
		}
		m1Ref, _, _, err := ref.WriteMessage(nil, nil)
		if err != nil || !bytes.Equal(m1, m1Ref) {
			t.Fatalf("les deux initiateurs n'écrivent pas le même message 1 : %v\n%x\n%x", err, m1, m1Ref)
		}
		return init, ref
	}
	// Le vrai message 2, en graine : notre répondeur, éphémère fixé.
	premier := NouvelInitiateur(appareil, serveur.PublicKey().Bytes(), prologue)
	premier.e = cleFixe(f, 3)
	m1, err := premier.Message1(nil)
	if err != nil {
		f.Fatal(err)
	}
	rep := NouveauRepondeur(serveur, prologue)
	if _, _, err := rep.LireMessage1(m1); err != nil {
		f.Fatal(err)
	}
	rep.e = cleFixe(f, 4)
	m2, _, err := rep.Message2([]byte("ok"))
	preparer(f) // les deux initiateurs doivent déjà s'accorder sur le message 1
	if err != nil {
		f.Fatal(err)
	}
	f.Add(m2)
	f.Add(make([]byte, TailleMsg2+tailleTag))

	f.Fuzz(func(t *testing.T, m []byte) {
		init, ref := preparer(t)
		charge, _, err := init.LireMessage2(m)
		chargeRef, _, _, errRef := ref.ReadMessage(nil, m)
		if (err == nil) != (errRef == nil) {
			t.Fatalf("désaccord avec la référence : nous %v, elle %v", err, errRef)
		}
		if err == nil && (!bytes.Equal(charge, chargeRef) || !bytes.Equal(m, m2)) {
			t.Fatalf("message 2 forgé ou mal lu : %x", m)
		}
	})
}
