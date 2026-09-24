package protocole

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"testing"
	"time"
)

func TestPreuve(t *testing.T) {
	serveur, _ := ecdh.X25519().GenerateKey(rand.Reader)
	appareil, _ := ecdh.X25519().GenerateKey(rand.Reader)
	voleur, _ := ecdh.X25519().GenerateKey(rand.Reader)
	now := time.Now()
	pub := appareil.PublicKey().Bytes()

	d := DemandeConnexion{JetonGoogle: "jeton-de-la-victime", Nom: "portable", Systeme: "android",
		ClePublique: base64.StdEncoding.EncodeToString(pub), Horodatage: now.Unix()}
	if err := d.Prouver(appareil, serveur.PublicKey().Bytes()); err != nil {
		t.Fatal(err)
	}
	if !d.VerifierPreuve(serveur, pub, now) {
		t.Fatal("preuve valide refusée")
	}

	// Le voleur connaît la clé publique de l'appareil, pas sa clé privée.
	faux := d
	faux.Prouver(voleur, serveur.PublicKey().Bytes())
	if faux.VerifierPreuve(serveur, pub, now) {
		t.Fatal("une preuve faite avec une autre clé est acceptée")
	}
	// La preuve de la victime, recollée à un autre justificatif, un autre
	// nom ou un autre horodatage, ne vaut plus rien.
	for nom, modif := range map[string]func(*DemandeConnexion){
		"justificatif": func(x *DemandeConnexion) { x.JetonGoogle = "jeton-de-l-attaquant" },
		"clé":          func(x *DemandeConnexion) { x.JetonGoogle, x.CleInscription = "", "sas-cle" },
		"nom":          func(x *DemandeConnexion) { x.Nom = "autre" },
		"système":      func(x *DemandeConnexion) { x.Systeme = "linux" },
		"horodatage":   func(x *DemandeConnexion) { x.Horodatage++ },
	} {
		x := d
		modif(&x)
		if x.VerifierPreuve(serveur, pub, now) {
			t.Errorf("preuve toujours valide après changement de : %s", nom)
		}
	}
	// Périmée.
	if d.VerifierPreuve(serveur, pub, now.Add(FenetrePreuve+time.Second)) {
		t.Fatal("une preuve périmée est acceptée")
	}
}

func TestRejeux(t *testing.T) {
	var r Rejeux
	now := time.Now()
	if r.DejaVue("p", now) {
		t.Fatal("preuve jamais vue signalée comme vue")
	}
	r.Retenir("p", now)
	if !r.DejaVue("p", now.Add(time.Minute)) {
		t.Fatal("une preuve rejouée dans la fenêtre doit être reconnue")
	}
	if r.DejaVue("p", now.Add(3*FenetrePreuve)) {
		t.Fatal("après la fenêtre, l'horodatage suffit à refuser : la preuve peut être oubliée")
	}
}
