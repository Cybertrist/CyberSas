package b64

import (
	"encoding/base64"
	"testing"
)

// Une seule écriture par valeur : tout ce qui est accepté se réencode à
// l'identique, et toute valeur a son écriture acceptée.
func FuzzDecoder(f *testing.F) {
	f.Add("AAAA")
	f.Add("AB==")
	f.Add("AQ==")
	f.Add("AA\nAA")
	f.Fuzz(func(t *testing.T, s string) {
		b, err := Decoder(s)
		if err == nil && base64.StdEncoding.EncodeToString(b) != s {
			t.Fatalf("%q accepté, mais s'écrit %q", s, base64.StdEncoding.EncodeToString(b))
		}
		canonique := base64.StdEncoding.EncodeToString([]byte(s))
		if r, err := Decoder(canonique); err != nil || string(r) != s {
			t.Fatalf("écriture canonique %q refusée : %v", canonique, err)
		}
	})
}
