package politique

import (
	"net/netip"
	"strings"
	"testing"
)

var (
	serveur = netip.MustParseAddr("10.77.0.1")
	equipe  = Equipe{"admin@x.fr": "admins", "alice@x.fr": "equipe"}
	apps    = []Appareil{
		{Adresse: netip.MustParseAddr("10.77.0.2"), Etiquette: "maison"},
		{Adresse: netip.MustParseAddr("10.77.0.3"), Proprietaire: "alice@x.fr"},
		{Adresse: netip.MustParseAddr("10.77.0.4"), Proprietaire: "alice@x.fr"},
		{Adresse: netip.MustParseAddr("10.77.0.5"), Proprietaire: "admin@x.fr"},
		{Adresse: netip.MustParseAddr("10.77.0.6"), Proprietaire: "bob@x.fr"}, // plus dans l'équipe
	}
	pol = Politique{Regles: []Regle{
		{De: []string{"groupe:admins"}, Vers: []string{"*"}, Ports: []string{"*"}},
		{De: []string{"*"}, Vers: []string{"soi"}, Ports: []string{"*"}},
		{De: []string{"groupe:equipe"}, Vers: []string{"etiquette:maison"}, Ports: []string{"tcp:80", "tcp:443"}},
		{De: []string{"serveur"}, Vers: []string{"etiquette:maison"}, Ports: []string{"tcp:80"}},
	}}
)

func a(s string) netip.Addr { return netip.MustParseAddr(s) }

func TestJoignables(t *testing.T) {
	flux := pol.Compiler(equipe, apps, serveur)
	cas := []struct {
		depuis string
		vers   []string
		pas    []string
	}{
		{"10.77.0.3", []string{"10.77.0.2", "10.77.0.4"}, []string{"10.77.0.5", "10.77.0.6"}}, // alice
		{"10.77.0.5", []string{"10.77.0.2", "10.77.0.3"}, []string{"10.77.0.6"}},              // admin, mais bob est sorti
		{"10.77.0.2", nil, []string{"10.77.0.3", "10.77.0.5"}},                                // maison
		{"10.77.0.6", nil, []string{"10.77.0.2", "10.77.0.3"}},                                // bob, sorti
	}
	for _, c := range cas {
		j := Joignables(flux, a(c.depuis))
		for _, v := range c.vers {
			if !j[a(v)] {
				t.Errorf("%s devrait joindre %s", c.depuis, v)
			}
		}
		for _, v := range c.pas {
			if j[a(v)] {
				t.Errorf("%s ne devrait pas joindre %s", c.depuis, v)
			}
		}
	}
}

func TestNft(t *testing.T) {
	r := Nft(pol.Compiler(equipe, apps, serveur), "sas0", serveur)
	for _, attendu := range []string{
		`ip saddr { 10.77.0.3, 10.77.0.4 } ip daddr { 10.77.0.2 } tcp dport 80 accept`,
		`ip saddr { 10.77.0.1 } ip daddr { 10.77.0.2 } tcp dport 80 accept`,
		`oifname != "sas0" counter drop`,
		"delete table inet cybersas",
	} {
		if !strings.Contains(r, attendu) {
			t.Errorf("règle manquante : %s\n%s", attendu, r)
		}
	}
	if strings.Contains(r, "10.77.0.6") {
		t.Error("bob n'est plus dans l'équipe, il ne doit apparaître dans aucune règle")
	}
}

func TestPortsIllisibles(t *testing.T) {
	for _, p := range []string{"tcp", "tcp:abc", "tcp:90-80", "ssh"} {
		if _, err := lirePorts([]string{p}); err == nil {
			t.Errorf("%q aurait dû être refusé", p)
		}
	}
}
