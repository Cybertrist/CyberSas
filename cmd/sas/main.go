// sas : le client CyberSas pour Linux, pensé pour les machines sans écran.
//
//	sas rejoindre --serveur https://vpn.exemple.fr --cle sas-... [--nom maison] [--verrou <clé>]
//	sas demon                       tient le tunnel ouvert (à lancer au démarrage)
//	sas appareils                   les pairs de cet appareil, et ceux refusés
//	sas etat                        l'inscription de cet appareil
//	sas quitter                     se désinscrit et oublie tout
//
// Et, sur l'ordinateur de l'admin seulement, jamais sur le serveur :
//
//	sas verrou creer --fichier F    crée la clé du verrou du réseau
//	sas verrou signer --fichier F   signe les appareils lus sur l'entrée
//
// La clé privée de l'appareil est générée ici et reste dans /var/lib/sas,
// lisible par root seul. Le serveur n'en voit que la moitié publique.
package main

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/Cybertrist/CyberSas/internal/client"
	"github.com/Cybertrist/CyberSas/internal/noise"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/tun"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

type etat struct {
	Serveur     string                     `json:"serveur"`
	ClePrivee   string                     `json:"cle_privee"`
	Inscription protocole.ReponseConnexion `json:"inscription"`
	// Verrou retenu à l'inscription. Il ne change plus : un serveur qui en
	// annoncerait un autre, ou plus aucun, serait refusé.
	Verrou string `json:"verrou,omitempty"`
}

var dossier = func() string {
	if d := os.Getenv("SAS_ETAT"); d != "" {
		return d
	}
	return "/var/lib/sas"
}()

func fichierEtat() string { return filepath.Join(dossier, "etat.json") }

func meurt(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "sas : "+format+"\n", args...)
	os.Exit(1)
}

func lireEtat() (etat, error) {
	var e etat
	b, err := os.ReadFile(fichierEtat())
	if err != nil {
		return e, err
	}
	return e, json.Unmarshal(b, &e)
}

func ecrireEtat(e etat) error {
	if err := os.MkdirAll(dossier, 0o700); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(e, "", "  ")
	tmp := fichierEtat() + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, fichierEtat())
}

// api : SAS_CA ajoute une autorité, celle du labo par exemple, aux racines
// du système.
func api(base string) *client.API {
	var ca []byte
	if chemin := os.Getenv("SAS_CA"); chemin != "" {
		var err error
		if ca, err = os.ReadFile(chemin); err != nil {
			meurt("autorité %s illisible", chemin)
		}
	}
	a, err := client.NouvelleAPI(base, ca)
	if err != nil {
		meurt("%v", err)
	}
	return a
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage : sas rejoindre|demon|appareils|etat|quitter|verrou")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "rejoindre":
		rejoindre(os.Args[2:])
	case "demon":
		if err := demon(); err != nil {
			meurt("%v", err)
		}
	case "appareils":
		appareils()
	case "etat":
		e, err := lireEtat()
		if err != nil {
			meurt("pas inscrit")
		}
		a := e.Inscription.Appareil
		fmt.Printf("%s  %s  sur %s  (réseau %s, verrou %s)\n", a.Nom, a.Adresse, e.Serveur, e.Inscription.Reseau, client.EmpreinteVerrou(e.Verrou))
	case "quitter":
		e, err := lireEtat()
		if err != nil {
			meurt("pas inscrit")
		}
		if err := api(e.Serveur).Appel("POST", protocole.CheminDeconnexion, e.Inscription.Jeton, nil, nil); err != nil {
			fmt.Fprintf(os.Stderr, "sas : le serveur n'a pas confirmé (%v), l'état local est effacé quand même\n", err)
		}
		os.Remove(fichierEtat())
		fmt.Println("désinscrit")
	case "verrou":
		cmdVerrou(os.Args[2:])
	default:
		meurt("commande inconnue : %s", os.Args[1])
	}
}

func rejoindre(args []string) {
	f := flag.NewFlagSet("rejoindre", flag.ExitOnError)
	serveur := f.String("serveur", "", "adresse de l'API, https://vpn.exemple.fr")
	cle := f.String("cle", "", "clé d'inscription donnée par sasd cle")
	verrouAttendu := f.String("verrou", "", "clé publique du verrou, si l'admin l'a donnée (recommandé)")
	nom, _ := os.Hostname()
	f.StringVar(&nom, "nom", nom, "nom de cet appareil dans le VPN")
	f.Parse(args)
	if *serveur == "" || *cle == "" {
		meurt("il faut --serveur et --cle")
	}
	// On garde la clé déjà générée : se réinscrire ne change pas d'adresse.
	e, _ := lireEtat()
	var brut []byte
	if k, err := base64.StdEncoding.DecodeString(e.ClePrivee); err == nil && len(k) == 32 {
		brut = k
	} else {
		k, err := noise.GenererCle()
		if err != nil {
			meurt("%v", err)
		}
		brut = k.Bytes()
	}
	prive, _ := noise.ClePrivee(brut)
	r, err := api(*serveur).Inscrire(prive, nom, runtime.GOOS, client.Justificatif{CleInscription: *cle}, *verrouAttendu)
	if err != nil {
		meurt("inscription refusée : %v", err)
	}
	if err := ecrireEtat(etat{Serveur: *serveur, ClePrivee: base64.StdEncoding.EncodeToString(brut), Inscription: r, Verrou: r.Verrou}); err != nil {
		meurt("%v", err)
	}
	fmt.Printf("inscrit : %s, %s\n", r.Appareil.Nom, r.Appareil.Adresse)
	if r.Verrou != "" {
		fmt.Printf("verrou retenu : %s (à comparer avec celui de l'admin)\n", client.EmpreinteVerrou(r.Verrou))
	}
}

func lireReseau(e etat) (protocole.EtatReseau, error) {
	var r protocole.EtatReseau
	err := api(e.Serveur).Appel("GET", protocole.CheminReseau, e.Inscription.Jeton, nil, &r)
	return r, err
}

func appareils() {
	e, err := lireEtat()
	if err != nil {
		meurt("pas inscrit")
	}
	r, err := lireReseau(e)
	if err != nil {
		meurt("%v", err)
	}
	_, ecartes, err := client.Construire(r, e.Inscription.Serveur.ClePublique, e.Verrou, netip.AddrPort{})
	if err != nil {
		meurt("%v", err)
	}
	refus := map[string]string{}
	for _, x := range ecartes {
		refus[x.Adresse] = x.Raison
	}
	t := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	moi := r.Moi
	fmt.Fprintf(t, "%s\t%s\t%s\t%s\t(cet appareil)\n", moi.Nom, moi.Adresse, qui(moi), "en ligne")
	for _, a := range r.Pairs {
		etat := "hors ligne"
		if a.EnLigne {
			etat = "en ligne"
		}
		note := ""
		if raison, ok := refus[a.Adresse]; ok {
			note = "REFUSÉ : " + raison
		}
		fmt.Fprintf(t, "%s\t%s\t%s\t%s\t%s\n", a.Nom, a.Adresse, qui(a), etat, note)
	}
	t.Flush()
}

func qui(a protocole.Appareil) string {
	if a.Etiquette != "" {
		return "étiquette " + a.Etiquette
	}
	return a.Proprietaire
}

// demon ouvre l'interface, attend une inscription, et tient le tunnel.
// Toutes les deux secondes il relit son état local ; toutes les dix, il
// redemande au serveur l'état du réseau.
func demon() error {
	journal := slog.New(slog.NewTextHandler(os.Stderr, nil))
	iface, err := tun.Ouvrir("sas0")
	if err != nil {
		return err
	}
	conn, err := net.ListenUDP("udp", &net.UDPAddr{})
	if err != nil {
		return err
	}
	ctx, arret := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer arret()

	var (
		moteur      *tunnel.Moteur
		dernier     []byte
		cle         []byte
		courant     etat
		demande     time.Time
		derniersRef string
	)
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		b, err := os.ReadFile(fichierEtat())
		switch {
		case err == nil && !bytes.Equal(b, dernier):
			var e etat
			if err := json.Unmarshal(b, &e); err != nil {
				return err
			}
			brut, err := base64.StdEncoding.DecodeString(e.ClePrivee)
			if err != nil {
				return err
			}
			k, err := noise.ClePrivee(brut)
			if err != nil {
				return err
			}
			switch {
			case moteur == nil:
				moteur = tunnel.Nouveau(tunnel.Config{Prive: k, Tun: iface, Conn: conn, Journal: journal})
				go func() {
					if err := moteur.Lancer(ctx); err != nil {
						journal.Error("tunnel arrêté", "erreur", err)
						arret()
					}
				}()
			case !bytes.Equal(brut, cle):
				// Nouvelle inscription, nouvelle clé : les sessions de
				// l'ancienne ne valent plus rien.
				moteur.DefinirCle(k)
			}
			cle, dernier, courant, demande = brut, b, e, time.Time{}
			if err := configurerInterface(iface, e); err != nil {
				journal.Error("interface", "erreur", err)
			}
		case errors.Is(err, os.ErrNotExist) && moteur != nil && dernier != nil:
			moteur.DefinirPairs(nil)
			dernier = nil
		}

		if dernier != nil && time.Since(demande) >= 10*time.Second {
			demande = time.Now()
			refus, err := appliquerReseau(moteur, courant)
			switch {
			case errors.Is(err, client.ErrDesinscrit):
				journal.Warn("le serveur ne connaît plus cet appareil : tunnel coupé")
				moteur.DefinirPairs(nil)
			case err != nil:
				journal.Error("état du réseau", "erreur", err)
			case refus != derniersRef:
				if refus != "" {
					journal.Warn("pairs refusés", "detail", refus)
				}
				derniersRef = refus
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
		}
	}
}

func configurerInterface(iface *tun.Tun, e etat) error {
	reseau, err := netip.ParsePrefix(e.Inscription.Reseau)
	if err != nil {
		return err
	}
	adresse, err := netip.ParseAddr(e.Inscription.Appareil.Adresse)
	if err != nil {
		return err
	}
	return iface.Configurer(netip.PrefixFrom(adresse, reseau.Bits()), tunnel.MTU)
}

// appliquerReseau : l'état du réseau, vérifié, devient la liste des pairs.
// L'adresse du serveur est redemandée à chaque fois : un changement d'IP ne
// perd pas le client.
func appliquerReseau(m *tunnel.Moteur, e etat) (string, error) {
	r, err := lireReseau(e)
	if err != nil {
		return "", err
	}
	point, err := net.ResolveUDPAddr("udp", e.Inscription.Serveur.Point)
	if err != nil {
		return "", fmt.Errorf("point %s : %w", e.Inscription.Serveur.Point, err)
	}
	pairs, ecartes, err := client.Construire(r, e.Inscription.Serveur.ClePublique, e.Verrou, point.AddrPort())
	if err != nil {
		return "", err
	}
	m.DefinirPairs(pairs)
	var refus []string
	for _, x := range ecartes {
		refus = append(refus, fmt.Sprintf("%s (%s) : %s", x.Nom, x.Adresse, x.Raison))
	}
	return strings.Join(refus, " ; "), nil
}

// --- le verrou, côté admin ------------------------------------------------------

func cmdVerrou(args []string) {
	if len(args) == 0 {
		meurt("usage : sas verrou creer|signer --fichier F")
	}
	f := flag.NewFlagSet("verrou", flag.ExitOnError)
	fichier := f.String("fichier", "", "clé privée du verrou")
	tout := f.Bool("tout", false, "signer aussi les appareils déjà signés")
	f.Parse(args[1:])
	if *fichier == "" {
		meurt("il faut --fichier")
	}
	switch args[0] {
	case "creer":
		if _, err := os.Stat(*fichier); err == nil {
			meurt("%s existe déjà : on ne remplace pas une clé de verrou", *fichier)
		}
		pub, prive, err := verrou.Generer()
		if err != nil {
			meurt("%v", err)
		}
		if err := os.WriteFile(*fichier, []byte(base64.StdEncoding.EncodeToString(prive.Seed())+"\n"), 0o600); err != nil {
			meurt("%v", err)
		}
		fmt.Println(base64.StdEncoding.EncodeToString(pub))
		fmt.Fprintf(os.Stderr, "verrou créé, empreinte %s. La clé privée reste dans %s : jamais sur le serveur.\n",
			verrou.Empreinte(pub), *fichier)
	case "signer":
		texte, err := os.ReadFile(*fichier)
		if err != nil {
			meurt("%v", err)
		}
		graine, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(texte)))
		if err != nil || len(graine) != ed25519.SeedSize {
			meurt("clé de verrou illisible")
		}
		prive := ed25519.NewKeyFromSeed(graine)
		var liste []protocole.Appareil
		if err := json.NewDecoder(os.Stdin).Decode(&liste); err != nil {
			meurt("entrée illisible : %v", err)
		}
		var sortie []protocole.Appareil
		for _, a := range liste {
			if a.Signature != "" && !*tout {
				continue
			}
			k, err := base64.StdEncoding.DecodeString(a.ClePublique)
			adresse, err2 := netip.ParseAddr(a.Adresse)
			if err != nil || err2 != nil || len(k) != 32 {
				fmt.Fprintf(os.Stderr, "ignoré, illisible : %s\n", a.Nom)
				continue
			}
			var pub [32]byte
			copy(pub[:], k)
			a.Signature = base64.StdEncoding.EncodeToString(verrou.Signer(prive, pub, adresse))
			fmt.Fprintf(os.Stderr, "signé : %s (%s, %s)\n", a.Nom, a.Adresse, qui(a))
			sortie = append(sortie, a)
		}
		json.NewEncoder(os.Stdout).Encode(sortie)
	default:
		meurt("usage : sas verrou creer|signer --fichier F")
	}
}
