// sas : le client CyberSas pour Linux, pensé pour les machines sans écran.
//
//	sas rejoindre --serveur https://vpn.exemple.fr --cle sas-... [--nom maison]
//	sas demon          tient le tunnel ouvert (à lancer au démarrage)
//	sas appareils      ce que cet appareil peut joindre
//	sas etat           l'inscription de cet appareil
//	sas quitter        se désinscrit et oublie tout
//
// La clé privée est générée ici et reste dans /var/lib/sas, lisible par
// root seul. Le serveur n'en voit que la moitié publique.
package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/Cybertrist/CyberSas/internal/noise"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/tun"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
)

type etat struct {
	Serveur     string                     `json:"serveur"`
	ClePrivee   string                     `json:"cle_privee"`
	Inscription protocole.ReponseConnexion `json:"inscription"`
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

// client HTTPS. SAS_CA ajoute une autorité, celle du labo par exemple, aux
// racines du système.
func client() *http.Client {
	racines, _ := x509.SystemCertPool()
	if racines == nil {
		racines = x509.NewCertPool()
	}
	if ca := os.Getenv("SAS_CA"); ca != "" {
		b, err := os.ReadFile(ca)
		if err != nil || !racines.AppendCertsFromPEM(b) {
			meurt("autorité %s illisible", ca)
		}
	}
	return &http.Client{Timeout: 20 * time.Second,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: racines, MinVersion: tls.VersionTLS12}}}
}

func appel(methode, url, jeton string, corps, reponse any) error {
	var b []byte
	if corps != nil {
		b, _ = json.Marshal(corps)
	}
	req, _ := http.NewRequest(methode, url, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if jeton != "" {
		req.Header.Set("Authorization", "Bearer "+jeton)
	}
	rep, err := client().Do(req)
	if err != nil {
		return err
	}
	defer rep.Body.Close()
	if rep.StatusCode != http.StatusOK {
		var e protocole.Erreur
		json.NewDecoder(rep.Body).Decode(&e)
		return fmt.Errorf("%s (%d)", e.Erreur, rep.StatusCode)
	}
	if reponse != nil {
		return json.NewDecoder(rep.Body).Decode(reponse)
	}
	return nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage : sas rejoindre|demon|appareils|etat|quitter")
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
		fmt.Printf("%s  %s  sur %s  (réseau %s)\n", a.Nom, a.Adresse, e.Serveur, e.Inscription.Reseau)
	case "quitter":
		e, err := lireEtat()
		if err != nil {
			meurt("pas inscrit")
		}
		if err := appel("POST", e.Serveur+protocole.CheminDeconnexion, e.Inscription.Jeton, nil, nil); err != nil {
			fmt.Fprintf(os.Stderr, "sas : le serveur n'a pas confirmé (%v), l'état local est effacé quand même\n", err)
		}
		os.Remove(fichierEtat())
		fmt.Println("désinscrit")
	default:
		meurt("commande inconnue : %s", os.Args[1])
	}
}

func rejoindre(args []string) {
	f := flag.NewFlagSet("rejoindre", flag.ExitOnError)
	serveur := f.String("serveur", "", "adresse de l'API, https://vpn.exemple.fr")
	cle := f.String("cle", "", "clé d'inscription donnée par sasd cle")
	nom, _ := os.Hostname()
	f.StringVar(&nom, "nom", nom, "nom de cet appareil dans le VPN")
	f.Parse(args)
	if *serveur == "" || *cle == "" {
		meurt("il faut --serveur et --cle")
	}
	// On garde la clé déjà générée : se réinscrire ne change pas d'adresse.
	e, _ := lireEtat()
	var prive []byte
	if k, err := base64.StdEncoding.DecodeString(e.ClePrivee); err == nil && len(k) == 32 {
		prive = k
	} else {
		k, err := noise.GenererCle()
		if err != nil {
			meurt("%v", err)
		}
		prive = k.Bytes()
	}
	k, _ := noise.ClePrivee(prive)
	d := protocole.DemandeConnexion{
		CleInscription: *cle, Nom: nom, Systeme: runtime.GOOS,
		ClePublique: base64.StdEncoding.EncodeToString(k.PublicKey().Bytes()),
	}
	var r protocole.ReponseConnexion
	if err := appel("POST", *serveur+protocole.CheminConnexion, "", d, &r); err != nil {
		meurt("inscription refusée : %v", err)
	}
	if err := ecrireEtat(etat{Serveur: *serveur, ClePrivee: base64.StdEncoding.EncodeToString(prive), Inscription: r}); err != nil {
		meurt("%v", err)
	}
	fmt.Printf("inscrit : %s, %s\n", r.Appareil.Nom, r.Appareil.Adresse)
}

func appareils() {
	e, err := lireEtat()
	if err != nil {
		meurt("pas inscrit")
	}
	var liste []protocole.Appareil
	if err := appel("GET", e.Serveur+protocole.CheminAppareils, e.Inscription.Jeton, nil, &liste); err != nil {
		meurt("%v", err)
	}
	t := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	for _, a := range liste {
		etat := "hors ligne"
		if a.EnLigne {
			etat = "en ligne"
		}
		qui := a.Proprietaire
		if a.Etiquette != "" {
			qui = "étiquette " + a.Etiquette
		}
		moi := ""
		if a.Moi {
			moi = "(cet appareil)"
		}
		fmt.Fprintf(t, "%s\t%s\t%s\t%s\t%s\n", a.Nom, a.Adresse, qui, etat, moi)
	}
	t.Flush()
}

// demon ouvre l'interface, attend une inscription, et tient le tunnel.
// Il relit l'état toutes les deux secondes : une nouvelle inscription est
// prise en compte sans redémarrer.
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

	var moteur *tunnel.Moteur
	var dernier, cle []byte
	var courant etat
	var point netip.AddrPort
	var resolu time.Time
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for {
		b, err := os.ReadFile(fichierEtat())
		if err == nil && !bytes.Equal(b, dernier) {
			var e etat
			if err := json.Unmarshal(b, &e); err != nil {
				return err
			}
			prive, err := base64.StdEncoding.DecodeString(e.ClePrivee)
			if err != nil {
				return err
			}
			k, err := noise.ClePrivee(prive)
			if err != nil {
				return err
			}
			switch {
			case moteur == nil:
				moteur = tunnel.Nouveau(k, iface, conn, journal)
				go func() {
					if err := moteur.Lancer(ctx); err != nil {
						journal.Error("tunnel arrêté", "erreur", err)
						arret()
					}
				}()
			case !bytes.Equal(prive, cle):
				// Nouvelle inscription, nouvelle clé : les sessions de
				// l'ancienne ne valent plus rien.
				moteur.DefinirCle(k)
			}
			cle = prive
			if p, err := configurer(iface, moteur, e); err != nil {
				journal.Error("configuration", "erreur", err)
			} else {
				dernier, courant, point = b, e, p
				journal.Info("tunnel configuré", "appareil", e.Inscription.Appareil.Nom, "adresse", e.Inscription.Appareil.Adresse, "serveur", p)
			}
		} else if err == nil && moteur != nil && time.Since(resolu) > 30*time.Second {
			// L'adresse du serveur peut changer (nouvelle IP, nouveau VPS) :
			// on la redemande régulièrement.
			resolu = time.Now()
			if a, err := net.ResolveUDPAddr("udp", courant.Inscription.Serveur.Point); err == nil && a.AddrPort() != point {
				if p, err := configurer(iface, moteur, courant); err == nil {
					journal.Info("le serveur a changé d'adresse", "avant", point, "apres", p)
					point = p
				}
			}
		} else if errors.Is(err, os.ErrNotExist) && moteur != nil {
			moteur.DefinirPairs(nil)
			dernier = nil
		}
		select {
		case <-ctx.Done():
			return nil
		case <-t.C:
		}
	}
}

// configurer monte l'interface et donne le serveur au moteur. Rend
// l'adresse du serveur telle qu'elle vient d'être résolue.
func configurer(iface *tun.Tun, m *tunnel.Moteur, e etat) (netip.AddrPort, error) {
	r := e.Inscription
	reseau, err := netip.ParsePrefix(r.Reseau)
	if err != nil {
		return netip.AddrPort{}, err
	}
	adresse, err := netip.ParseAddr(r.Appareil.Adresse)
	if err != nil {
		return netip.AddrPort{}, err
	}
	if err := iface.Configurer(netip.PrefixFrom(adresse, reseau.Bits()), tunnel.MTU); err != nil {
		return netip.AddrPort{}, err
	}
	point, err := net.ResolveUDPAddr("udp", r.Serveur.Point)
	if err != nil {
		return netip.AddrPort{}, fmt.Errorf("point %s : %w", r.Serveur.Point, err)
	}
	cle, err := base64.StdEncoding.DecodeString(r.Serveur.ClePublique)
	if err != nil || len(cle) != 32 {
		return netip.AddrPort{}, errors.New("clé publique du serveur invalide")
	}
	var pub [32]byte
	copy(pub[:], cle)
	m.DefinirPairs([]tunnel.Pair{{
		Publique: pub, Adresses: []netip.Prefix{reseau},
		Point: point.AddrPort(), Maintien: 25 * time.Second,
	}})
	return point.AddrPort(), nil
}
