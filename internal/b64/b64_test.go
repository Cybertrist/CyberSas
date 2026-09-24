package b64

import (
	"encoding/base64"
	"testing"
)

func TestUneSeuleEcriture(t *testing.T) {
	cle := make([]byte, 32)
	for i := range cle {
		cle[i] = byte(i * 7)
	}
	s := base64.StdEncoding.EncodeToString(cle)
	if _, err := Cle32(s); err != nil {
		t.Fatal(err)
	}
	// Mêmes octets, autre écriture : bits de bourrage non nuls, puis un
	// retour à la ligne glissé au milieu. Le décodeur standard accepte les
	// deux ; le nôtre les refuse.
	bourrage := []byte(s)
	i := len(bourrage) - 2
	bourrage[i] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[(indice(bourrage[i])+1)%64]
	if b, err := base64.StdEncoding.DecodeString(string(bourrage)); err != nil || string(b) != string(cle) {
		t.Fatal("hypothèse du test fausse : le décodeur standard devait accepter cette variante")
	}
	for _, variante := range []string{string(bourrage), s[:10] + "\n" + s[10:]} {
		if _, err := Decoder(variante); err == nil {
			t.Errorf("écriture non canonique acceptée : %q", variante)
		}
	}
}

func indice(c byte) int {
	const a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i := range a {
		if a[i] == c {
			return i
		}
	}
	return -1
}
