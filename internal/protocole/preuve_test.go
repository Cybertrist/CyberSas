package protocole

import (
	"crypto/ecdh"
	"crypto/rand"
	"testing"
	"time"
)

func TestPreuve(t *testing.T) {
	serveur, _ := ecdh.X25519().GenerateKey(rand.Reader)
	appareil, _ := ecdh.X25519().GenerateKey(rand.Reader)
	voleur, _ := ecdh.X25519().GenerateKey(rand.Reader)
	now := time.Now()
	h := now.Unix()

	p, err := Prouver(appareil, serveur.PublicKey().Bytes(), h)
	if err != nil {
		t.Fatal(err)
	}
	if !VerifierPreuve(serveur, appareil.PublicKey().Bytes(), h, p, now) {
		t.Fatal("preuve valide refusée")
	}
	// Le voleur connaît la clé publique de l'appareil, pas sa clé privée.
	faux, _ := Prouver(voleur, serveur.PublicKey().Bytes(), h)
	if VerifierPreuve(serveur, appareil.PublicKey().Bytes(), h, faux, now) {
		t.Fatal("une preuve faite avec une autre clé est acceptée")
	}
	// Une preuve trop vieille ne sert plus.
	if VerifierPreuve(serveur, appareil.PublicKey().Bytes(), h, p, now.Add(FenetrePreuve+time.Second)) {
		t.Fatal("une preuve périmée est acceptée")
	}
	// Changer l'horodatage casse le code.
	if VerifierPreuve(serveur, appareil.PublicKey().Bytes(), h+1, p, now) {
		t.Fatal("une preuve est acceptée avec un autre horodatage")
	}
}
