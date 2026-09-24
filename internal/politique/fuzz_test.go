package politique

import (
	"encoding/json"
	"net/netip"
	"testing"
)

// Une politique quelconque, même absurde, ne doit ni faire tomber le
// serveur, ni ouvrir un flux vers une adresse qui n'est pas un appareil.
func FuzzPolitique(f *testing.F) {
	f.Add(`{"version":1,"regles":[{"de":["*"],"vers":["soi"],"ports":["*"]}]}`)
	f.Add(`{"regles":[{"de":["groupe:equipe"],"vers":["etiquette:maison"],"ports":["tcp:80-90","icmp"]}]}`)
	f.Add(`{"regles":[{"de":["serveur"],"vers":["alice@x.fr"],"ports":["udp:0-65535"]}]}`)
	f.Add(`{"regles":[{"de":["*"],"vers":["*"],"ports":["tcp:65536"]}]}`)

	connues := map[netip.Addr]bool{serveur: true}
	for _, a := range apps {
		connues[a.Adresse] = true
	}
	reseau := netip.MustParsePrefix("10.77.0.0/24")

	f.Fuzz(func(t *testing.T, texte string) {
		var p Politique
		if json.Unmarshal([]byte(texte), &p) != nil {
			return
		}
		if _, err := Verifier(p); err != nil {
			return
		}
		flux := p.Compiler(equipe, apps, serveur)
		for _, fl := range flux {
			for _, a := range append(append([]netip.Addr(nil), fl.Sources...), fl.Dest...) {
				if !connues[a] {
					t.Fatalf("flux vers une adresse inconnue : %v", a)
				}
			}
		}
		premier, second := Nft(flux, "sas0", serveur, reseau), Nft(flux, "sas0", serveur, reseau)
		if premier != second {
			t.Fatal("le même flux donne deux pare-feux différents")
		}
		Relations(flux, serveur)
		for _, a := range apps {
			Entrant(flux, a.Adresse)
		}
	})
}
