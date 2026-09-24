// Package politique décide qui peut joindre quoi dans le VPN, et traduit
// cette décision en règles de pare-feu pour le serveur.
//
// Tout le trafic entre appareils passe par le serveur : c'est là que les
// règles s'appliquent, dans le noyau, par nftables. Un appareil ne peut
// pas les contourner, puisqu'il n'a de session qu'avec le serveur.
package politique

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/netip"
	"os"
	"slices"
	"strconv"
	"strings"
)

// Une règle ouvre des ports, de certains appareils vers d'autres.
//
// Sélecteurs de De et Vers :
//
//	"*"                 tous les appareils
//	"groupe:admins"     les appareils des personnes de ce groupe
//	"etiquette:maison"  les machines inscrites sous cette étiquette
//	"utilisateur:a@b"   les appareils d'une personne
//	"serveur"           le serveur lui-même (Nginx, qui publie les services)
//	"soi"               dans Vers seulement : les autres appareils de la
//	                    même personne
//
// Ports : "*" (tout), "icmp", "tcp:443", "udp:53", "tcp:8000-8100".
type Regle struct {
	De    []string `json:"de"`
	Vers  []string `json:"vers"`
	Ports []string `json:"ports"`
}

type Politique struct {
	Regles []Regle `json:"regles"`
}

// Equipe : adresse Google, en minuscules, vers le groupe.
type Equipe map[string]string

type Appareil struct {
	Adresse      netip.Addr
	Proprietaire string
	Etiquette    string
}

type Port struct {
	Proto      string // "*", "tcp", "udp", "icmp"
	Debut, Fin uint16
}

// Flux : ce qu'une règle autorise, une fois les sélecteurs résolus.
type Flux struct {
	Sources, Dest []netip.Addr
	Ports         []Port
}

func Charger(chemin string) (Politique, error) {
	var p Politique
	b, err := os.ReadFile(chemin)
	if err != nil {
		return p, err
	}
	if err := json.Unmarshal(b, &p); err != nil {
		return p, fmt.Errorf("%s : %w", chemin, err)
	}
	for i, r := range p.Regles {
		if _, err := lirePorts(r.Ports); err != nil {
			return p, fmt.Errorf("%s, règle %d : %w", chemin, i+1, err)
		}
	}
	return p, nil
}

// ChargerEquipe lit « adresse groupe » par ligne ; # commente.
func ChargerEquipe(chemin string) (Equipe, error) {
	f, err := os.Open(chemin)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	e := Equipe{}
	s := bufio.NewScanner(f)
	for s.Scan() {
		ch := strings.Fields(s.Text())
		if len(ch) >= 2 && !strings.HasPrefix(ch[0], "#") {
			e[strings.ToLower(ch[0])] = ch[1]
		}
	}
	return e, s.Err()
}

func lirePorts(liste []string) ([]Port, error) {
	var r []Port
	for _, s := range liste {
		switch {
		case s == "*":
			r = append(r, Port{Proto: "*"})
		case s == "icmp":
			r = append(r, Port{Proto: "icmp"})
		case strings.HasPrefix(s, "tcp:"), strings.HasPrefix(s, "udp:"):
			proto, plage, _ := strings.Cut(s, ":")
			d, f, estPlage := strings.Cut(plage, "-")
			debut, err := strconv.ParseUint(d, 10, 16)
			if err != nil {
				return nil, fmt.Errorf("port illisible : %q", s)
			}
			fin := debut
			if estPlage {
				if fin, err = strconv.ParseUint(f, 10, 16); err != nil || fin < debut {
					return nil, fmt.Errorf("plage illisible : %q", s)
				}
			}
			r = append(r, Port{Proto: proto, Debut: uint16(debut), Fin: uint16(fin)})
		default:
			return nil, fmt.Errorf("port inconnu : %q", s)
		}
	}
	return r, nil
}

func correspond(sel string, a Appareil, e Equipe) bool {
	switch {
	case sel == "*":
		return true
	case strings.HasPrefix(sel, "groupe:"):
		return a.Proprietaire != "" && e[a.Proprietaire] == strings.TrimPrefix(sel, "groupe:")
	case strings.HasPrefix(sel, "etiquette:"):
		return a.Etiquette != "" && a.Etiquette == strings.TrimPrefix(sel, "etiquette:")
	case strings.HasPrefix(sel, "utilisateur:"):
		return a.Proprietaire != "" && a.Proprietaire == strings.ToLower(strings.TrimPrefix(sel, "utilisateur:"))
	}
	return false
}

func choisir(sels []string, apps []Appareil, e Equipe, serveur netip.Addr) []netip.Addr {
	var r []netip.Addr
	if slices.Contains(sels, "serveur") {
		r = append(r, serveur)
	}
	for _, a := range apps {
		// Une personne sortie de l'équipe n'apparaît plus dans aucune
		// règle, même si ses appareils n'ont pas encore été purgés.
		if a.Proprietaire != "" && e[a.Proprietaire] == "" {
			continue
		}
		for _, s := range sels {
			if correspond(s, a, e) {
				r = append(r, a.Adresse)
				break
			}
		}
	}
	return r
}

// Compiler résout les sélecteurs sur les appareils du moment.
func (p Politique) Compiler(e Equipe, apps []Appareil, serveur netip.Addr) []Flux {
	var flux []Flux
	for _, r := range p.Regles {
		ports, _ := lirePorts(r.Ports)
		sources := choisir(r.De, apps, e, serveur)
		if len(sources) == 0 {
			continue
		}
		if d := choisir(r.Vers, apps, e, serveur); len(d) > 0 {
			flux = append(flux, Flux{sources, d, ports})
		}
		if !slices.Contains(r.Vers, "soi") {
			continue
		}
		// « soi » : pour chaque personne, de ses appareils vers ses appareils.
		parPersonne := map[string][]netip.Addr{}
		for _, a := range apps {
			if a.Proprietaire != "" && e[a.Proprietaire] != "" {
				parPersonne[a.Proprietaire] = append(parPersonne[a.Proprietaire], a.Adresse)
			}
		}
		for _, siens := range parPersonne {
			var s []netip.Addr
			for _, x := range siens {
				if slices.Contains(sources, x) {
					s = append(s, x)
				}
			}
			if len(s) > 0 && len(siens) > 1 {
				flux = append(flux, Flux{s, siens, ports})
			}
		}
	}
	return flux
}

// Joignables : les adresses qu'un appareil a le droit d'atteindre. Sert à
// l'appli, qui n'affiche que ce qu'on peut ouvrir.
func Joignables(flux []Flux, depuis netip.Addr) map[netip.Addr]bool {
	r := map[netip.Addr]bool{}
	for _, f := range flux {
		if slices.Contains(f.Sources, depuis) {
			for _, d := range f.Dest {
				if d != depuis {
					r[d] = true
				}
			}
		}
	}
	return r
}
