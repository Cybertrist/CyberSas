// Package verrou : le verrou du réseau, pour ne pas avoir à croire le
// serveur sur parole.
//
// Le chiffrement de bout en bout empêche le serveur de lire ce qui passe
// entre deux appareils. Mais c'est lui qui distribue les clés publiques : un
// serveur piraté pourrait annoncer, sous le nom de « maison », une clé qui
// est la sienne, et s'intercaler. Le verrou ferme cette porte.
//
// L'admin garde une clé de signature Ed25519 hors du serveur, sur son
// propre ordinateur. Il signe la clé publique et l'adresse de chaque
// appareil qu'il accepte. Les appareils connaissent la clé publique du
// verrou, et refusent tout pair dont la signature ne vérifie pas, même si
// le serveur le leur présente. Pour s'intercaler, il faudrait donc voler la
// clé du verrou, qui n'a jamais touché le serveur.
//
// C'est le principe du « Tailnet Lock » de Tailscale, en plus simple : une
// seule clé de signature, pas de chaîne de délégation.
package verrou

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"net/netip"
)

// contexte : préfixe de tout message signé. Une signature faite pour
// autre chose ne peut pas servir ici.
const contexte = "CyberSas verrou v1\x00"

// Message : ce qui est signé pour un appareil. La clé publique et
// l'adresse vont ensemble : le serveur ne peut pas donner à une clé
// signée l'adresse d'un autre appareil.
func Message(cle [32]byte, adresse netip.Addr) []byte {
	a := adresse.As4()
	m := append([]byte(contexte), cle[:]...)
	return append(m, a[:]...)
}

func Generer() (ed25519.PublicKey, ed25519.PrivateKey, error) {
	return ed25519.GenerateKey(rand.Reader)
}

func Signer(prive ed25519.PrivateKey, cle [32]byte, adresse netip.Addr) []byte {
	return ed25519.Sign(prive, Message(cle, adresse))
}

func Verifier(publique ed25519.PublicKey, cle [32]byte, adresse netip.Addr, signature []byte) bool {
	if len(publique) != ed25519.PublicKeySize || len(signature) != ed25519.SignatureSize {
		return false
	}
	return ed25519.Verify(publique, Message(cle, adresse), signature)
}

// Empreinte : de quoi comparer la clé du verrou à voix haute, ou d'un coup
// d'œil entre deux écrans.
func Empreinte(publique ed25519.PublicKey) string {
	h := sha256.Sum256(publique)
	s := base64.RawStdEncoding.EncodeToString(h[:9])
	return fmt.Sprintf("%s-%s-%s", s[0:4], s[4:8], s[8:12])
}

func LirePublique(b64 string) (ed25519.PublicKey, error) {
	b, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(b) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("clé de verrou invalide")
	}
	return ed25519.PublicKey(b), nil
}
