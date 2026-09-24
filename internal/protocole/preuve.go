package protocole

import (
	"crypto/ecdh"
	"crypto/hmac"
	"encoding/base64"
	"encoding/binary"
	"hash"
	"time"

	"golang.org/x/crypto/blake2s"
)

// Preuve de possession de la clé privée, à l'inscription.
//
// Sans elle, n'importe qui pourrait inscrire la clé publique d'un autre
// appareil (les clés publiques circulent) et s'approprier sa fiche. Une clé
// X25519 ne signe pas ; on fait donc comme Noise : un échange de clés entre
// la clé de l'appareil et celle du serveur donne un secret que seuls ces deux-
// là peuvent calculer, et l'on en tire un code sur l'horodatage de la demande.

const contextePreuve = "CyberSas inscription v1"

// FenetrePreuve : écart toléré entre l'horloge de l'appareil et celle du
// serveur. Une preuve plus vieille est refusée, ce qui borne tout rejeu.
const FenetrePreuve = 5 * time.Minute

func codePreuve(secret []byte, appareil, serveur []byte, horodatage int64) []byte {
	m := hmac.New(func() hash.Hash { h, _ := blake2s.New256(nil); return h }, secret)
	m.Write([]byte(contextePreuve))
	m.Write(appareil)
	m.Write(serveur)
	m.Write(binary.BigEndian.AppendUint64(nil, uint64(horodatage)))
	return m.Sum(nil)
}

// Prouver, côté appareil.
func Prouver(prive *ecdh.PrivateKey, publiqueServeur []byte, horodatage int64) (string, error) {
	pub, err := ecdh.X25519().NewPublicKey(publiqueServeur)
	if err != nil {
		return "", err
	}
	secret, err := prive.ECDH(pub)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(codePreuve(secret, prive.PublicKey().Bytes(), publiqueServeur, horodatage)), nil
}

// VerifierPreuve, côté serveur. Comparaison en temps constant.
func VerifierPreuve(serveur *ecdh.PrivateKey, publiqueAppareil []byte, horodatage int64, preuve string, maintenant time.Time) bool {
	ecart := maintenant.Sub(time.Unix(horodatage, 0))
	if ecart > FenetrePreuve || ecart < -FenetrePreuve {
		return false
	}
	recue, err := base64.StdEncoding.DecodeString(preuve)
	if err != nil {
		return false
	}
	pub, err := ecdh.X25519().NewPublicKey(publiqueAppareil)
	if err != nil {
		return false
	}
	secret, err := serveur.ECDH(pub)
	if err != nil {
		return false
	}
	return hmac.Equal(recue, codePreuve(secret, publiqueAppareil, serveur.PublicKey().Bytes(), horodatage))
}
