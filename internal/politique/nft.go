package politique

import (
	"fmt"
	"net/netip"
	"os/exec"
	"slices"
	"strings"
)

// Nft écrit le jeu de règles du serveur. Il remplace l'ancien d'un bloc :
// nft l'applique de façon atomique, il n'y a jamais d'instant où le
// pare-feu est à moitié chargé.
//
// Trois chemins passent par l'interface du VPN :
//
//	transit : d'un appareil à un autre, à travers le noyau du serveur.
//	          Toujours fermé. Entre appareils, tout passe chiffré de bout en
//	          bout par le relais du moteur ; un paquet en clair qui tenterait
//	          de traverser serait un contournement.
//	sortie  : du serveur vers un appareil (Nginx qui publie un service)
//	entree  : d'un appareil vers le serveur (le DNS du VPN)
//
// Les deux derniers commencent fermés, laissent passer les réponses aux
// connexions déjà ouvertes, puis n'autorisent que ce que la politique dit.
func Nft(flux []Flux, iface string, serveur netip.Addr) string {
	var sortie, entree []string
	for _, f := range flux {
		src, dst := sansServeur(f.Sources, serveur), sansServeur(f.Dest, serveur)
		depuisServeur := slices.Contains(f.Sources, serveur)
		versServeur := slices.Contains(f.Dest, serveur)
		for _, p := range f.Ports {
			if depuisServeur && len(dst) > 0 {
				sortie = append(sortie, regle([]netip.Addr{serveur}, dst, p))
			}
			if versServeur && len(src) > 0 {
				entree = append(entree, regle(src, []netip.Addr{serveur}, p))
			}
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "table inet cybersas\ndelete table inet cybersas\n")
	fmt.Fprintf(&b, "table inet cybersas {\n")
	fmt.Fprintf(&b, "\tchain transit {\n\t\ttype filter hook forward priority filter; policy accept;\n"+
		"\t\tiifname \"%s\" counter drop comment \"aucun paquet ne traverse le serveur en clair\"\n"+
		"\t\toifname \"%s\" counter drop comment \"ni n'entre dans le VPN depuis ailleurs\"\n\t}\n", iface, iface)
	chaine(&b, "sortie", "output", iface, "oifname", "depuis_serveur", sortie)
	chaine(&b, "entree", "input", iface, "iifname", "vers_serveur",
		append([]string{
			fmt.Sprintf("ip daddr %s udp dport 53 accept", serveur),
			fmt.Sprintf("ip daddr %s tcp dport 53 accept", serveur),
			fmt.Sprintf("ip daddr %s icmp type echo-request accept", serveur),
		}, entree...))
	b.WriteString("}\n")
	return b.String()
}

func chaine(b *strings.Builder, nom, crochet, iface, sens, sousChaine string, regles []string) {
	fmt.Fprintf(b, "\tchain %s {\n\t\ttype filter hook %s priority filter; policy accept;\n\t\t%s \"%s\" jump %s\n\t}\n",
		nom, crochet, sens, iface, sousChaine)
	fmt.Fprintf(b, "\tchain %s {\n\t\tct state established,related accept\n", sousChaine)
	for _, r := range regles {
		fmt.Fprintf(b, "\t\t%s\n", r)
	}
	fmt.Fprintf(b, "\t\tcounter drop\n\t}\n")
}

func sansServeur(l []netip.Addr, serveur netip.Addr) []netip.Addr {
	return slices.DeleteFunc(slices.Clone(l), func(a netip.Addr) bool { return a == serveur })
}

func ensemble(l []netip.Addr) string {
	s := make([]string, len(l))
	for i, a := range l {
		s[i] = a.String()
	}
	slices.Sort(s)
	s = slices.Compact(s)
	return "{ " + strings.Join(s, ", ") + " }"
}

func regle(src, dst []netip.Addr, p Port) string {
	r := fmt.Sprintf("ip saddr %s ip daddr %s", ensemble(src), ensemble(dst))
	switch p.Proto {
	case "*":
	case "icmp":
		r += " meta l4proto icmp"
	default:
		if p.Debut == p.Fin {
			r += fmt.Sprintf(" %s dport %d", p.Proto, p.Debut)
		} else {
			r += fmt.Sprintf(" %s dport %d-%d", p.Proto, p.Debut, p.Fin)
		}
	}
	return r + " accept"
}

// Appliquer charge le jeu de règles dans le noyau.
func Appliquer(regles string) error {
	cmd := exec.Command("nft", "-f", "-")
	cmd.Stdin = strings.NewReader(regles)
	if sortie, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("nft : %v : %s", err, sortie)
	}
	return nil
}
