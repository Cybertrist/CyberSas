// sas : le client CyberSas pour Linux, pensé pour les machines sans écran.
//
//	SAS_CLE=sas-... sas rejoindre --serveur https://vpn.exemple.fr [--nom maison] [--verrou <clé>]
//	sas demon                       tient le tunnel ouvert (à lancer au démarrage)
//	sas appareils                   les pairs de cet appareil, et ceux refusés
//	sas etat                        l'inscription et la clé publique de cet appareil
//	sas quitter                     se désinscrit et oublie tout
//
// Et, sur l'ordinateur de l'admin seulement, jamais sur le serveur :
//
//	sas verrou creer --fichier F                    crée la clé du verrou
//	sas verrou signer --fichier F --cle K[,K...]    signe ces appareils-là, et eux seuls
//	sas verrou politique --fichier F < politique.json
//	sas verrou revoquer --fichier F --cle K < revocations.json
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
	"io"
	"log/slog"
	"net"
	"net/netip"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/Cybertrist/CyberSas/internal/client"
	"github.com/Cybertrist/CyberSas/internal/noise"
	"github.com/Cybertrist/CyberSas/internal/politique"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/tun"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

type etat struct {
	Serveur     string                     `json:"serveur"`
	ClePrivee   string                     `json:"cle_privee"`
	Inscription protocole.ReponseConnexion `json:"inscription"`
	// Retenu : ce que l'appareil a appris et ne laisse plus changer (clé du
	// serveur, verrou, versions signées déjà vues, clés révoquées).
	Retenu client.Retenu `json:"retenu"`
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

// ecrireEtat : fichier temporaire, synchronisé sur disque, puis renommé.
// Une coupure de courant ne laisse jamais un état à moitié écrit, ce qui
// ferait perdre la clé privée.
func ecrireEtat(e etat) error {
	if err := os.MkdirAll(dossier, 0o700); err != nil {
		return err
	}
	if err := os.Chmod(dossier, 0o700); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(e, "", "  ")
	tmp := fichierEtat() + ".tmp"
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.Write(b); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	f.Close()
	if err := os.Rename(tmp, fichierEtat()); err != nil {
		return err
	}
	if d, err := os.Open(dossier); err == nil {
		d.Sync()
		d.Close()
	}
	return nil
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
		fmt.Printf("%s  %s  sur %s  (réseau %s, verrou %s)\n", client.Propre(a.Nom), a.Adresse, e.Serveur,
			e.Inscription.Reseau, client.EmpreinteVerrou(e.Retenu.Verrou))
		fmt.Printf("clé publique : %s  (empreinte %s)\n", e.Retenu.MaCle, client.EmpreinteCle(e.Retenu.MaCle))
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
	verrouAttendu := f.String("verrou", "", "clé publique du verrou, si l'admin l'a donnée (recommandé)")
	oublier := f.Bool("oublier", false, "accepter un autre serveur ou un autre verrou que ceux déjà retenus")
	nom, _ := os.Hostname()
	f.StringVar(&nom, "nom", nom, "nom de cet appareil dans le VPN")
	f.Parse(args)
	// La clé d'inscription passe par l'environnement : en argument, elle
	// serait visible de tous dans la liste des processus.
	cle := os.Getenv("SAS_CLE")
	if *serveur == "" || cle == "" {
		meurt("il faut --serveur, et la clé d'inscription dans SAS_CLE")
	}
	// On garde la clé déjà générée : se réinscrire ne change pas d'adresse.
	ancien, dejaInscrit := lireEtat()
	var brut []byte
	if k, err := base64.StdEncoding.DecodeString(ancien.ClePrivee); err == nil && len(k) == 32 {
		brut = k
	} else {
		k, err := noise.GenererCle()
		if err != nil {
			meurt("%v", err)
		}
		brut = k.Bytes()
	}
	prive, _ := noise.ClePrivee(brut)
	if *verrouAttendu == "" && dejaInscrit == nil {
		*verrouAttendu = ancien.Retenu.Verrou
	}
	r, err := api(*serveur).Inscrire(prive, nom, runtime.GOOS, client.Justificatif{CleInscription: cle}, *verrouAttendu)
	if err != nil {
		meurt("inscription refusée : %v", err)
	}
	// Ce qu'on a retenu ne change pas sans qu'on le demande : un serveur
	// piraté qui ferait se réinscrire l'appareil ne ferait pas disparaître le
	// verrou pour autant.
	if dejaInscrit == nil && !*oublier {
		if ancien.Retenu.CleServeur != "" && ancien.Retenu.CleServeur != r.Serveur.ClePublique {
			meurt("le serveur a changé de clé (%s, avant %s) : refus. --oublier pour l'accepter",
				client.EmpreinteCle(r.Serveur.ClePublique), client.EmpreinteCle(ancien.Retenu.CleServeur))
		}
		if ancien.Retenu.Verrou != r.Verrou {
			meurt("le verrou a changé (%s, avant %s) : refus. --oublier pour l'accepter",
				client.EmpreinteVerrou(r.Verrou), client.EmpreinteVerrou(ancien.Retenu.Verrou))
		}
	}
	reseau, err1 := netip.ParsePrefix(r.Reseau)
	moi, err2 := netip.ParseAddr(r.Appareil.Adresse)
	if err1 != nil || err2 != nil || !moi.Is4() || !reseau.Contains(moi) {
		meurt("réponse du serveur incohérente : adresse %q dans %q", r.Appareil.Adresse, r.Reseau)
	}
	ret := client.Retenu{CleServeur: r.Serveur.ClePublique, Verrou: r.Verrou, Moi: moi, Reseau: reseau,
		MaCle: base64.StdEncoding.EncodeToString(prive.PublicKey().Bytes())}
	if dejaInscrit == nil && ancien.Retenu.Verrou == r.Verrou {
		ret.VersionPolitique, ret.VersionRevocations, ret.Revoquees =
			ancien.Retenu.VersionPolitique, ancien.Retenu.VersionRevocations, ancien.Retenu.Revoquees
	}
	if err := ecrireEtat(etat{Serveur: *serveur, ClePrivee: base64.StdEncoding.EncodeToString(brut), Inscription: r, Retenu: ret}); err != nil {
		meurt("%v", err)
	}
	fmt.Printf("inscrit : %s, %s\n", client.Propre(r.Appareil.Nom), r.Appareil.Adresse)
	fmt.Printf("clé publique : %s  (empreinte %s)\n", ret.MaCle, client.EmpreinteCle(ret.MaCle))
	if r.Verrou != "" {
		fmt.Printf("verrou retenu : %s. Donnez la clé publique ci-dessus à l'admin, pour qu'il la signe.\n", client.EmpreinteVerrou(r.Verrou))
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
	ret := e.Retenu
	_, ecartes, err := client.Construire(r, &ret, netip.AddrPort{}, time.Now())
	if err != nil {
		meurt("%v", err)
	}
	refus := map[string]string{}
	var autres []client.Ecarte
	for _, x := range ecartes {
		if x.Adresse != "" && x.Adresse != ret.Moi.String() {
			refus[x.Adresse] = x.Raison
		} else {
			autres = append(autres, x)
		}
	}
	t := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(t, "%s\t%s\t%s\t%s\t(cet appareil)\n", client.Propre(r.Moi.Nom), r.Moi.Adresse, qui(r.Moi), "en ligne")
	for _, a := range r.Pairs {
		etat := "hors ligne"
		if a.EnLigne {
			etat = "en ligne"
		}
		note := ""
		if raison, ok := refus[a.Adresse]; ok {
			note = "REFUSÉ : " + raison
		}
		fmt.Fprintf(t, "%s\t%s\t%s\t%s\t%s\n", client.Propre(a.Nom), client.Propre(a.Adresse), qui(a), etat, note)
	}
	t.Flush()
	for _, x := range autres {
		fmt.Printf("note : %s : %s\n", x.Nom, x.Raison)
	}
}

func qui(a protocole.Appareil) string {
	if a.Etiquette != "" {
		return "étiquette " + client.Propre(a.Etiquette)
	}
	return client.Propre(a.Proprietaire)
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
				journal.Error("état illisible", "erreur", err)
				break
			}
			brut, err1 := base64.StdEncoding.DecodeString(e.ClePrivee)
			k, err2 := noise.ClePrivee(brut)
			if err1 != nil || err2 != nil {
				journal.Error("clé privée illisible")
				break
			}
			switch {
			case moteur == nil:
				moteur = tunnel.Nouveau(tunnel.Config{Prive: k, Tun: iface, Conn: conn, Journal: journal, Adresse: e.Retenu.Moi})
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
			moteur.DefinirAdresse(e.Retenu.Moi)
			cle, dernier, courant, demande = brut, b, e, time.Time{}
			if err := iface.Configurer(netip.PrefixFrom(e.Retenu.Moi, e.Retenu.Reseau.Bits()), tunnel.MTU); err != nil {
				journal.Error("interface", "erreur", err)
			}
		case errors.Is(err, os.ErrNotExist) && moteur != nil && dernier != nil:
			moteur.DefinirPairs(nil)
			dernier = nil
		}

		if dernier != nil && time.Since(demande) >= 10*time.Second {
			demande = time.Now()
			refus, err := appliquerReseau(moteur, &courant)
			switch {
			case errors.Is(err, client.ErrDesinscrit):
				journal.Warn("le serveur ne connaît plus cet appareil : tunnel coupé")
				moteur.DefinirPairs(nil)
			case err != nil:
				journal.Error("état du réseau", "erreur", err)
			case refus != derniersRef:
				if refus != "" {
					journal.Warn("refusé par ce client", "detail", refus)
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

// appliquerReseau : l'état du réseau, vérifié, devient la liste des pairs.
// Ce que l'appareil apprend en chemin (versions signées, révocations) est
// écrit sur disque : il ne l'oublie pas en redémarrant.
func appliquerReseau(m *tunnel.Moteur, e *etat) (string, error) {
	r, err := lireReseau(*e)
	if err != nil {
		return "", err
	}
	point, err := net.ResolveUDPAddr("udp", e.Inscription.Serveur.Point)
	if err != nil {
		return "", fmt.Errorf("point %s : %w", e.Inscription.Serveur.Point, err)
	}
	ret := e.Retenu
	pairs, ecartes, err := client.Construire(r, &ret, point.AddrPort(), time.Now())
	if err != nil {
		return "", err
	}
	if ret.VersionPolitique != e.Retenu.VersionPolitique || ret.VersionRevocations != e.Retenu.VersionRevocations {
		nouveau := *e
		nouveau.Retenu = ret
		if err := ecrireEtat(nouveau); err != nil {
			return "", err
		}
	}
	m.DefinirPairs(pairs)
	var refus []string
	for _, x := range ecartes {
		refus = append(refus, fmt.Sprintf("%s (%s) : %s", x.Nom, x.Adresse, x.Raison))
	}
	return strings.Join(refus, " ; "), nil
}

// --- le verrou, côté admin ------------------------------------------------------

func lireVerrou(fichier string) ed25519.PrivateKey {
	texte, err := os.ReadFile(fichier)
	if err != nil {
		meurt("%v", err)
	}
	graine, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(texte)))
	if err != nil || len(graine) != ed25519.SeedSize {
		meurt("clé de verrou illisible")
	}
	return ed25519.NewKeyFromSeed(graine)
}

func cmdVerrou(args []string) {
	if len(args) == 0 {
		meurt("usage : sas verrou creer|signer|politique|revoquer --fichier F")
	}
	f := flag.NewFlagSet("verrou", flag.ExitOnError)
	fichier := f.String("fichier", "", "clé privée du verrou")
	cles := f.String("cle", "", "clés publiques à signer ou à révoquer, séparées par des virgules")
	duree := f.Duration("duree", 90*24*time.Hour, "durée de validité des certificats")
	f.Parse(args[1:])
	if *fichier == "" {
		meurt("il faut --fichier")
	}
	switch args[0] {
	case "creer":
		// O_EXCL : on ne remplace jamais une clé de verrou existante, et l'on
		// ne suit pas un lien symbolique posé à sa place.
		sortie, err := os.OpenFile(*fichier, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			meurt("%v (on ne remplace pas une clé de verrou)", err)
		}
		pub, prive, err := verrou.Generer()
		if err != nil {
			meurt("%v", err)
		}
		fmt.Fprintln(sortie, base64.StdEncoding.EncodeToString(prive.Seed()))
		if err := sortie.Close(); err != nil {
			meurt("%v", err)
		}
		fmt.Println(base64.StdEncoding.EncodeToString(pub))
		fmt.Fprintf(os.Stderr, "verrou créé, empreinte %s. La clé privée reste dans %s : jamais sur le serveur.\n",
			verrou.Empreinte(pub), *fichier)

	case "signer":
		signer(lireVerrou(*fichier), *cles, *duree)

	case "politique":
		prive := lireVerrou(*fichier)
		brut, err := io.ReadAll(io.LimitReader(os.Stdin, 1<<20))
		if err != nil {
			meurt("%v", err)
		}
		var p politique.Politique
		if err := json.Unmarshal(brut, &p); err != nil {
			meurt("politique illisible : %v", err)
		}
		if _, err := politique.Verifier(p); err != nil {
			meurt("politique invalide : %v", err)
		}
		if p.Version == 0 {
			meurt("la politique doit porter un numéro de version, qui croît à chaque modification")
		}
		json.NewEncoder(os.Stdout).Encode(map[string]any{"version": p.Version,
			"signature": base64.StdEncoding.EncodeToString(verrou.SignerPolitique(prive, p.Version, brut))})
		fmt.Fprintf(os.Stderr, "politique version %d signée (%d règles)\n", p.Version, len(p.Regles))

	case "revoquer":
		prive := lireVerrou(*fichier)
		var l protocole.ListeRevocations
		if brut, _ := io.ReadAll(io.LimitReader(os.Stdin, 1<<20)); len(bytes.TrimSpace(brut)) > 0 {
			if err := json.Unmarshal(brut, &l); err != nil {
				meurt("liste actuelle illisible : %v", err)
			}
		}
		for _, k := range strings.Split(*cles, ",") {
			if k = strings.TrimSpace(k); k != "" && !slices.Contains(l.Cles, k) {
				l.Cles = append(l.Cles, k)
				fmt.Fprintf(os.Stderr, "révoquée : %s\n", client.EmpreinteCle(k))
			}
		}
		var brutes [][32]byte
		for _, c := range l.Cles {
			b, err := base64.StdEncoding.DecodeString(c)
			if err != nil || len(b) != 32 {
				meurt("clé illisible : %s", c)
			}
			brutes = append(brutes, [32]byte(b))
		}
		l.Version++
		l.Signature = base64.StdEncoding.EncodeToString(verrou.SignerRevocations(prive, l.Version, brutes))
		json.NewEncoder(os.Stdout).Encode(l)

	default:
		meurt("usage : sas verrou creer|signer|politique|revoquer --fichier F")
	}
}

// signer : l'admin désigne les clés à signer, qu'il a lues sur les
// appareils eux-mêmes (sas etat, ou l'écran de l'appli). La liste venue
// du serveur ne sert qu'à connaître les autres champs : on ne signe
// jamais un appareil simplement parce que le serveur le présente, sinon un
// serveur piraté ferait signer sa propre clé.
func signer(prive ed25519.PrivateKey, cles string, duree time.Duration) {
	voulues := map[string]bool{}
	for _, k := range strings.Split(cles, ",") {
		if k = strings.TrimSpace(k); k != "" {
			voulues[k] = true
		}
	}
	if len(voulues) == 0 {
		meurt("il faut --cle : les clés publiques des appareils à signer, lues sur les appareils eux-mêmes")
	}
	var liste []protocole.Appareil
	if err := json.NewDecoder(io.LimitReader(os.Stdin, 1<<20)).Decode(&liste); err != nil {
		meurt("entrée illisible : %v", err)
	}
	expire := time.Now().Add(duree).Truncate(time.Second)
	var sortie []protocole.Appareil
	for _, a := range liste {
		if !voulues[a.ClePublique] {
			continue
		}
		delete(voulues, a.ClePublique)
		k, err := base64.StdEncoding.DecodeString(a.ClePublique)
		adresse, err2 := netip.ParseAddr(a.Adresse)
		if err != nil || err2 != nil || len(k) != 32 || !adresse.Is4() {
			fmt.Fprintf(os.Stderr, "ignoré, illisible : %s\n", client.Propre(a.Nom))
			continue
		}
		c := verrou.Certificat{Cle: [32]byte(k), Adresse: adresse, Etiquette: a.Etiquette,
			Proprietaire: a.Proprietaire, Groupe: a.Groupe, Expire: expire}
		sig, err := c.Signer(prive)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ignoré : %s : %v\n", client.Propre(a.Nom), err)
			continue
		}
		a.Signature, a.SignatureExpire = base64.StdEncoding.EncodeToString(sig), expire
		fmt.Fprintf(os.Stderr, "signé : %s, %s, %s, groupe %q, empreinte %s, jusqu'au %s\n",
			client.Propre(a.Nom), a.Adresse, qui(a), client.Propre(a.Groupe), client.EmpreinteCle(a.ClePublique), expire.Format("02/01/2006"))
		sortie = append(sortie, a)
	}
	for k := range voulues {
		fmt.Fprintf(os.Stderr, "introuvable sur le serveur : %s (rien signé pour elle)\n", client.EmpreinteCle(k))
	}
	json.NewEncoder(os.Stdout).Encode(sortie)
}
