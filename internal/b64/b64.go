// Package b64 : le seul décodeur base64 à utiliser pour ce qui vient de
// l'extérieur (clés, signatures, preuves).
//
// Le décodeur standard de Go est permissif : il ignore les bits de
// bourrage du dernier caractère et les retours à la ligne. Une même clé a
// donc plusieurs écritures valides. Comparer deux clés sous forme de texte
// devient alors trompeur : un serveur piraté pouvait réécrire la clé d'un
// appareil révoqué pour qu'elle ne figure plus, en texte, dans la liste de
// révocation, tout en restant la même clé une fois décodée.
//
// Ici, une chaîne n'est acceptée que si la réencoder redonne exactement la
// même chaîne : chaque valeur n'a qu'une écriture.
package b64

import (
	"encoding/base64"
	"errors"
)

var ErrNonCanonique = errors.New("base64 non canonique")

// Decoder : base64 standard, avec bourrage, et une seule écriture possible.
func Decoder(s string) ([]byte, error) {
	b, err := base64.StdEncoding.Strict().DecodeString(s)
	if err != nil {
		return nil, err
	}
	if base64.StdEncoding.EncodeToString(b) != s {
		return nil, ErrNonCanonique
	}
	return b, nil
}

// Cle32 : une clé de 32 octets, en écriture canonique.
func Cle32(s string) ([32]byte, error) {
	var k [32]byte
	b, err := Decoder(s)
	if err != nil || len(b) != 32 {
		return k, errors.New("clé publique invalide")
	}
	copy(k[:], b)
	return k, nil
}
