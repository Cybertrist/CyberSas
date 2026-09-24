// sasd : le serveur CyberSas.
//
//	sasd                               fait tourner le serveur
//	sasd cle --etiquette maison        clé d'inscription pour une machine
//	sasd cle --utilisateur a@b.fr      clé pour l'appareil d'une personne, sans Google
//	sasd appareils                     les appareils inscrits
//	sasd retirer <nom>                 coupe un appareil
//
// La configuration vient de l'environnement, voir config().
package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
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
	"syscall"
	"text/tabwriter"
	"time"

	"github.com/Cybertrist/CyberSas/internal/base"
	"github.com/Cybertrist/CyberSas/internal/dns"
	"github.com/Cybertrist/CyberSas/internal/noise"
	"github.com/Cybertrist/CyberSas/internal/serveur"
	"github.com/Cybertrist/CyberSas/internal/tun"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
)

func env(nom, defaut string) string {
	if v := os.Getenv(nom); v != "" {
		return v
	}
	return defaut
}

type reglages struct {
	serveur.Config
	etat, ecoute string
	port         int
}

func config() reglages {
	reseau := netip.MustParsePrefix(env("SAS_RESEAU", "10.77.0.0/24"))
	domaine := env("SAS_DOMAINE", "sas.local")
	port := 51820
	fmt.Sscan(env("SAS_PORT", "51820"), &port)
	return reglages{
		Config: serveur.Config{
			Domaine:       domaine,
			Point:         env("SAS_POINT", fmt.Sprintf("vpn.%s:%d", domaine, port)),
			Reseau:        reseau,
			Serveur:       reseau.Masked().Addr().Next(),
			Interface:     env("SAS_INTERFACE", "sas0"),
			Equipe:        env("SAS_EQUIPE", "/config/equipe.txt"),
			Politique:     env("SAS_POLITIQUE", "/config/politique.json"),
			ClientsGoogle: env("SAS_CLIENTS_GOOGLE", "/config/clients_google"),
			DureeAppareil: 30 * 24 * time.Hour,
		},
		etat:   env("SAS_ETAT", "/var/lib/sasd"),
		ecoute: env("SAS_ECOUTE", "127.0.0.1:8080"),
		port:   port,
	}
}

func meurt(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "sasd : "+format+"\n", args...)
	os.Exit(1)
}

func main() {
	cfg := config()
	if len(os.Args) > 1 {
		b, err := base.Ouvrir(filepath.Join(cfg.etat, "sas.db"))
		if err != nil {
			meurt("%v", err)
		}
		switch os.Args[1] {
		case "cle":
			cmdCle(b, os.Args[2:])
		case "appareils":
			cmdAppareils(b)
		case "retirer":
			if len(os.Args) != 3 {
				meurt("usage : sasd retirer <nom>")
			}
			if err := b.SupprimerParNom(os.Args[2]); err != nil {
				meurt("%s : %v", os.Args[2], err)
			}
			fmt.Printf("%s retiré, coupé à la prochaine synchronisation (5 s au plus)\n", os.Args[2])
		default:
			meurt("commande inconnue : %s", os.Args[1])
		}
		return
	}
	if err := servir(cfg); err != nil {
		meurt("%v", err)
	}
}

func cmdCle(b *base.Base, args []string) {
	f := flag.NewFlagSet("cle", flag.ExitOnError)
	etiquette := f.String("etiquette", "", "étiquette de la machine (maison, nas…)")
	utilisateur := f.String("utilisateur", "", "adresse de la personne à qui appartient l'appareil")
	duree := f.Duration("duree", 10*time.Minute, "durée de validité")
	f.Parse(args)
	if (*etiquette == "") == (*utilisateur == "") {
		meurt("il faut --etiquette ou --utilisateur, pas les deux")
	}
	brut := make([]byte, 24)
	rand.Read(brut)
	cle := "sas-" + base64.RawURLEncoding.EncodeToString(brut)
	if err := b.CreerCle(cle, *etiquette, *utilisateur, time.Now().Add(*duree)); err != nil {
		meurt("%v", err)
	}
	fmt.Println(cle)
}

func cmdAppareils(b *base.Base) {
	liste, err := b.Appareils()
	if err != nil {
		meurt("%v", err)
	}
	t := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(t, "NOM\tADRESSE\tPROPRIÉTAIRE\tÉTIQUETTE\tSYSTÈME\tVU LE")
	for _, a := range liste {
		fmt.Fprintf(t, "%s\t%s\t%s\t%s\t%s\t%s\n", a.Nom, a.Adresse, tiret(a.Proprietaire), tiret(a.Etiquette), tiret(a.Systeme), a.Vu.Format("02/01 15:04"))
	}
	t.Flush()
}

func tiret(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

// cleServeur relit la clé privée du serveur, ou la crée au premier
// démarrage. Elle ne quitte jamais ce fichier.
func cleServeur(dossier string) ([]byte, error) {
	chemin := filepath.Join(dossier, "cle_serveur")
	if b, err := os.ReadFile(chemin); err == nil {
		return b, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	k, err := noise.GenererCle()
	if err != nil {
		return nil, err
	}
	return k.Bytes(), os.WriteFile(chemin, k.Bytes(), 0o600)
}

func servir(cfg reglages) error {
	journal := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := os.MkdirAll(cfg.etat, 0o700); err != nil {
		return err
	}
	brut, err := cleServeur(cfg.etat)
	if err != nil {
		return fmt.Errorf("clé du serveur : %w", err)
	}
	prive, err := noise.ClePrivee(brut)
	if err != nil {
		return err
	}
	b, err := base.Ouvrir(filepath.Join(cfg.etat, "sas.db"))
	if err != nil {
		return err
	}

	iface, err := tun.Ouvrir(cfg.Interface)
	if err != nil {
		return err
	}
	if err := iface.Configurer(netip.PrefixFrom(cfg.Serveur, cfg.Reseau.Bits()), tunnel.MTU); err != nil {
		return err
	}
	conn, err := net.ListenUDP("udp", &net.UDPAddr{Port: cfg.port})
	if err != nil {
		return err
	}

	ctx, arret := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer arret()

	moteur := tunnel.Nouveau(prive, iface, conn, journal.With("composant", "tunnel"))
	go func() {
		if err := moteur.Lancer(ctx); err != nil {
			journal.Error("tunnel arrêté", "erreur", err)
			arret()
		}
	}()

	resolveur := dns.Nouveau("sas.internal", env("SAS_DNS_AMONT", "1.1.1.1:53"))
	go func() {
		if err := resolveur.Lancer(net.JoinHostPort(cfg.Serveur.String(), "53")); err != nil {
			journal.Error("DNS arrêté", "erreur", err)
		}
	}()

	srv := serveur.Nouveau(cfg.Config, b, moteur, resolveur, prive.PublicKey().Bytes(), journal)
	if err := srv.Synchroniser(); err != nil {
		return err
	}
	go srv.Boucle(ctx)

	api := &http.Server{Addr: cfg.ecoute, Handler: srv.Routes(), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		api.Close()
	}()
	journal.Info("serveur prêt", "cle_publique", base64.StdEncoding.EncodeToString(prive.PublicKey().Bytes()),
		"point", cfg.Point, "reseau", cfg.Reseau, "api", cfg.ecoute)
	if err := api.ListenAndServe(); err != nil && ctx.Err() == nil {
		return err
	}
	return nil
}
