package pont

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"strings"
	"time"

	"github.com/Cybertrist/CyberSas/internal/appareil"
	"github.com/Cybertrist/CyberSas/internal/b64"
	"github.com/Cybertrist/CyberSas/internal/client"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

// dureeCertificat : comme « sas verrou signer » par défaut.
const dureeCertificat = 90 * 24 * time.Hour

// appel : un appel à l'API, au nom de cet appareil.
func appel(dossier, methode, chemin string, corps, reponse any) error {
	e, err := appareil.Stockage{Dossier: dossier}.Lire()
	if err != nil {
		return errors.New("pas inscrit")
	}
	a, err := api(e.Serveur, e.Autorite)
	if err != nil {
		return err
	}
	return a.Appel(methode, chemin, e.Inscription.Jeton, corps, reponse)
}

// Libeller change le nom affiché d'un appareil : le sien si cle est vide.
func Libeller(dossier, cle, libelle string) error {
	return appel(dossier, "POST", protocole.CheminLibelle, protocole.DemandeLibelle{ClePublique: cle, Libelle: libelle}, nil)
}

// Fiche : un appareil vu par l'admin, pour l'écran des demandes.
type Fiche struct {
	Nom          string `json:"nom"`
	Libelle      string `json:"libelle"`
	Adresse      string `json:"adresse"`
	Proprietaire string `json:"proprietaire"`
	Etiquette    string `json:"etiquette"`
	Groupe       string `json:"groupe"`
	Systeme      string `json:"systeme"`
	Cle          string `json:"cle"`
	Empreinte    string `json:"empreinte"`
	Signe        bool   `json:"signe"`
}

// Appareils : tous les appareils du réseau, signés ou non, en JSON
// ([]Fiche). Réservé aux admins.
func Appareils(dossier string) (string, error) {
	var liste []protocole.Appareil
	if err := appel(dossier, "GET", protocole.CheminAppareils, nil, &liste); err != nil {
		return "", err
	}
	r := []Fiche{}
	for _, a := range liste {
		r = append(r, Fiche{Nom: client.Propre(a.Nom), Libelle: client.Propre(a.Libelle), Adresse: a.Adresse,
			Proprietaire: client.Propre(a.Proprietaire), Etiquette: client.Propre(a.Etiquette), Groupe: client.Propre(a.Groupe),
			Systeme: client.Propre(a.Systeme), Cle: a.ClePublique, Empreinte: client.EmpreinteCle(a.ClePublique), Signe: a.Signature != ""})
	}
	b, _ := json.Marshal(r)
	return string(b), nil
}

// lireVerrou : la graine de la clé privée du verrou, en base64 (le contenu
// de etat/verrou/cle). Elle doit aller avec le verrou que cet appareil a
// retenu à l'inscription : sinon, ses signatures ne vaudraient rien.
func lireVerrou(dossier, graine string) (ed25519.PrivateKey, error) {
	// Un copier-coller emporte souvent un espace, un retour à la ligne ou
	// des guillemets : on ne garde que l'alphabet du base64.
	propre := strings.Map(func(r rune) rune {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '+' || r == '/' || r == '=' {
			return r
		}
		return -1
	}, graine)
	g, err := b64.Decoder(propre)
	if err != nil || len(g) != ed25519.SeedSize {
		return nil, fmt.Errorf("clé du verrou illisible : %d caractères reçus, 44 attendus", len(propre))
	}
	prive := ed25519.NewKeyFromSeed(g)
	e, err := appareil.Stockage{Dossier: dossier}.Lire()
	if err != nil {
		return nil, errors.New("pas inscrit")
	}
	attendu, err := verrou.LirePublique(e.Retenu.Verrou)
	if err != nil {
		return nil, errors.New("ce réseau n'a pas de verrou")
	}
	if !prive.Public().(ed25519.PublicKey).Equal(attendu) {
		return nil, errors.New("cette clé n'est pas celle du verrou de ce réseau")
	}
	return prive, nil
}

// VerifierVerrou : l'empreinte du verrou si la graine est bien la sienne.
func VerifierVerrou(dossier, graine string) (string, error) {
	prive, err := lireVerrou(dossier, graine)
	if err != nil {
		return "", err
	}
	return verrou.Empreinte(prive.Public().(ed25519.PublicKey)), nil
}

// Signer signe, avec la clé du verrou, les appareils dont la clé publique
// est dans cles (séparées par des virgules), et envoie les certificats au
// serveur. Comme « sas verrou signer » : on ne signe que les clés
// désignées, lues sur les appareils eux-mêmes, jamais tout ce que le
// serveur présente. Rend le nombre d'appareils signés.
func Signer(dossier, graine, cles string) (int, error) {
	prive, err := lireVerrou(dossier, graine)
	if err != nil {
		return 0, err
	}
	voulues := map[string]bool{}
	for _, k := range strings.Split(cles, ",") {
		if k = strings.TrimSpace(k); k != "" {
			voulues[k] = true
		}
	}
	var liste []protocole.Appareil
	if err := appel(dossier, "GET", protocole.CheminAppareils, nil, &liste); err != nil {
		return 0, err
	}
	expire := time.Now().Add(dureeCertificat).Truncate(time.Second)
	var sortie []protocole.Appareil
	for _, a := range liste {
		if !voulues[a.ClePublique] {
			continue
		}
		delete(voulues, a.ClePublique)
		k, err1 := b64.Cle32(a.ClePublique)
		adresse, err2 := netip.ParseAddr(a.Adresse)
		if err1 != nil || err2 != nil || !adresse.Is4() {
			return 0, fmt.Errorf("fiche illisible : %s", client.Propre(a.Nom))
		}
		c := verrou.Certificat{Cle: k, Adresse: adresse, Etiquette: a.Etiquette, Proprietaire: a.Proprietaire,
			Groupe: a.Groupe, Expire: expire}
		sig, err := c.Signer(prive)
		if err != nil {
			return 0, fmt.Errorf("%s : %w", client.Propre(a.Nom), err)
		}
		a.Signature, a.SignatureExpire = base64.StdEncoding.EncodeToString(sig), expire
		sortie = append(sortie, a)
	}
	if len(voulues) > 0 {
		return 0, errors.New("un appareil à signer n'est plus sur le serveur")
	}
	if len(sortie) == 0 {
		return 0, nil
	}
	if err := appel(dossier, "POST", protocole.CheminSignatures, sortie, nil); err != nil {
		return 0, err
	}
	return len(sortie), nil
}

// Retirer : un admin retire un appareil (une demande refusée).
func Retirer(dossier, cle string) error {
	return appel(dossier, "POST", protocole.CheminRetrait, protocole.DemandeRetrait{ClePublique: cle}, nil)
}

// Reseau : l'état du réseau lu directement sur l'API, sans tunnel (Vue en
// JSON). L'appli s'en sert quand le tunnel est coupé : on sait alors qui
// est admin, quand expire son certificat, et qui est en ligne. Les pairs
// sont vérifiés comme par le tunnel (client.Construire).
func Reseau(dossier string) (string, error) {
	s := appareil.Stockage{Dossier: dossier}
	e, err := s.Lire()
	if err != nil {
		return "", errors.New("pas inscrit")
	}
	a, err := api(e.Serveur, e.Autorite)
	if err != nil {
		return "", err
	}
	r, err := appareil.LireReseau(a, e)
	if err != nil {
		return "", err
	}
	ret := e.Retenu
	_, ecartes, err := client.Construire(r, &ret, netip.AddrPort{}, time.Now())
	if err != nil {
		return "", err
	}
	return vueJSON(appareil.Vue{Reseau: r, Ecartes: ecartes}, false, "", time.Now()), nil
}
