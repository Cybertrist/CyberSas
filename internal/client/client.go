// Package client : ce que tout client CyberSas fait, quelle que soit la
// plateforme. Le client Linux (cmd/sas) s'en sert, et les applis Android et
// Windows s'en serviront à l'identique, compilées depuis ce même code.
//
// Trois choses :
//   - s'inscrire, en prouvant qu'on détient sa clé privée ;
//   - traduire l'état du réseau, donné par le serveur, en pairs pour le
//     moteur du tunnel ;
//   - ne croire le serveur que sur ce qu'il ne peut pas falsifier : sa
//     propre clé, retenue à l'inscription, et les signatures du verrou.
package client

import (
	"bytes"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/netip"
	"strings"
	"time"

	"github.com/Cybertrist/CyberSas/internal/politique"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/tunnel"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

// ErrDesinscrit : le serveur ne connaît plus cet appareil (retiré, expiré).
var ErrDesinscrit = errors.New("appareil désinscrit")

// API : le client HTTPS de l'API. AutoriteEnPlus ajoute une autorité de
// certification aux racines du système, celle du labo par exemple.
type API struct {
	Base string
	http *http.Client
}

func NouvelleAPI(base string, autoriteEnPlus []byte) (*API, error) {
	racines, _ := x509.SystemCertPool()
	if racines == nil {
		racines = x509.NewCertPool()
	}
	if len(autoriteEnPlus) > 0 && !racines.AppendCertsFromPEM(autoriteEnPlus) {
		return nil, errors.New("autorité de certification illisible")
	}
	return &API{Base: strings.TrimRight(base, "/"), http: &http.Client{Timeout: 20 * time.Second,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: racines, MinVersion: tls.VersionTLS12}}}}, nil
}

func (a *API) Appel(methode, chemin, jeton string, corps, reponse any) error {
	var b []byte
	if corps != nil {
		b, _ = json.Marshal(corps)
	}
	req, err := http.NewRequest(methode, a.Base+chemin, bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if jeton != "" {
		req.Header.Set("Authorization", "Bearer "+jeton)
	}
	rep, err := a.http.Do(req)
	if err != nil {
		return err
	}
	defer rep.Body.Close()
	if rep.StatusCode == http.StatusUnauthorized && jeton != "" {
		return ErrDesinscrit
	}
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

// Justificatif : un jeton Google, ou une clé d'inscription.
type Justificatif struct {
	JetonGoogle, CleInscription string
}

// Inscrire : demande la clé du serveur, calcule la preuve de possession,
// puis s'inscrit. Si verrouAttendu est donné, l'inscription échoue si le
// serveur annonce un autre verrou : c'est ainsi qu'un admin prudent
// installe un appareil, en lui donnant l'empreinte du verrou d'avance.
func (a *API) Inscrire(prive *ecdh.PrivateKey, nom, systeme string, j Justificatif, verrouAttendu string) (protocole.ReponseConnexion, error) {
	var r protocole.ReponseConnexion
	var srv protocole.Serveur
	if err := a.Appel("GET", protocole.CheminServeur, "", nil, &srv); err != nil {
		return r, fmt.Errorf("clé du serveur : %w", err)
	}
	cleServeur, err := base64.StdEncoding.DecodeString(srv.ClePublique)
	if err != nil || len(cleServeur) != 32 {
		return r, errors.New("clé du serveur invalide")
	}
	h := time.Now().Unix()
	preuve, err := protocole.Prouver(prive, cleServeur, h)
	if err != nil {
		return r, err
	}
	d := protocole.DemandeConnexion{JetonGoogle: j.JetonGoogle, CleInscription: j.CleInscription, Nom: nom, Systeme: systeme,
		ClePublique: base64.StdEncoding.EncodeToString(prive.PublicKey().Bytes()), Horodatage: h, Preuve: preuve}
	if err := a.Appel("POST", protocole.CheminConnexion, "", d, &r); err != nil {
		return r, err
	}
	// La réponse doit parler de la clé que l'on vient d'utiliser : sinon,
	// quelqu'un s'est glissé entre la demande de clé et l'inscription.
	if r.Serveur.ClePublique != srv.ClePublique {
		return r, errors.New("le serveur a changé de clé pendant l'inscription")
	}
	if verrouAttendu != "" && r.Verrou != verrouAttendu {
		return r, fmt.Errorf("le serveur annonce un autre verrou que celui attendu (%s)", EmpreinteVerrou(r.Verrou))
	}
	return r, nil
}

func EmpreinteVerrou(b64 string) string {
	if b64 == "" {
		return "aucun"
	}
	pub, err := verrou.LirePublique(b64)
	if err != nil {
		return "illisible"
	}
	return verrou.Empreinte(pub)
}

// Ecarte : un pair que le serveur annonce, mais que ce client refuse.
type Ecarte struct {
	Nom, Adresse, Raison string
}

// Construire traduit l'état du réseau en pairs pour le moteur.
//
// cleServeur est celle retenue à l'inscription : si le serveur en annonce
// une autre, on refuse tout. verrouRetenu, si non vide, est la clé du
// verrou retenue à l'inscription : tout pair sans signature valide est
// écarté, même si le serveur le présente.
func Construire(r protocole.EtatReseau, cleServeur, verrouRetenu string, point netip.AddrPort) ([]tunnel.Pair, []Ecarte, error) {
	if r.Serveur.ClePublique != cleServeur {
		return nil, nil, errors.New("le serveur annonce une autre clé que celle retenue à l'inscription : refus")
	}
	var cleVerrou ed25519.PublicKey
	if verrouRetenu != "" {
		if r.Verrou != verrouRetenu {
			return nil, nil, fmt.Errorf("le serveur annonce un autre verrou (%s) que celui retenu (%s) : refus",
				EmpreinteVerrou(r.Verrou), EmpreinteVerrou(verrouRetenu))
		}
		var err error
		if cleVerrou, err = verrou.LirePublique(verrouRetenu); err != nil {
			return nil, nil, err
		}
	}
	adresseServeur, err := netip.ParseAddr(r.Serveur.Adresse)
	if err != nil {
		return nil, nil, fmt.Errorf("adresse du serveur : %w", err)
	}
	pubServeur, err := cle32(cleServeur)
	if err != nil {
		return nil, nil, err
	}

	entrant := map[netip.Addr][]tunnel.Regle{}
	for _, e := range r.Entrant {
		regles, err := VersRegles(e.Ports)
		if err != nil {
			return nil, nil, err
		}
		for _, s := range e.Sources {
			if a, err := netip.ParseAddr(s); err == nil {
				entrant[a] = append(entrant[a], regles...)
			}
		}
	}

	pairs := []tunnel.Pair{{Publique: pubServeur, Adresses: []netip.Prefix{netip.PrefixFrom(adresseServeur, 32)},
		Point: point, Maintien: 25 * time.Second, Entrant: entrant[adresseServeur]}}
	var ecartes []Ecarte
	for _, p := range r.Pairs {
		pub, err1 := cle32(p.ClePublique)
		adresse, err2 := netip.ParseAddr(p.Adresse)
		if err1 != nil || err2 != nil || adresse == adresseServeur || p.Numero == 0 {
			ecartes = append(ecartes, Ecarte{p.Nom, p.Adresse, "annonce malformée"})
			continue
		}
		if cleVerrou != nil {
			sig, _ := base64.StdEncoding.DecodeString(p.Signature)
			if !verrou.Verifier(cleVerrou, pub, adresse, sig) {
				ecartes = append(ecartes, Ecarte{p.Nom, p.Adresse, "pas signé par le verrou"})
				continue
			}
		}
		pairs = append(pairs, tunnel.Pair{Publique: pub, Adresses: []netip.Prefix{netip.PrefixFrom(adresse, 32)},
			Numero: p.Numero, ParRelais: true, Entrant: entrant[adresse]})
	}
	return pairs, ecartes, nil
}

func cle32(b64 string) ([32]byte, error) {
	var k [32]byte
	b, err := base64.StdEncoding.DecodeString(b64)
	if err != nil || len(b) != 32 {
		return k, errors.New("clé publique invalide")
	}
	copy(k[:], b)
	return k, nil
}

// VersRegles traduit des ports de la politique en règles du moteur.
func VersRegles(ports []string) ([]tunnel.Regle, error) {
	lus, err := politique.LirePorts(ports)
	if err != nil {
		return nil, err
	}
	var r []tunnel.Regle
	for _, p := range lus {
		switch p.Proto {
		case "*":
			r = append(r, tunnel.Regle{})
		case "icmp":
			r = append(r, tunnel.Regle{Proto: 1})
		case "tcp":
			r = append(r, tunnel.Regle{Proto: 6, Debut: p.Debut, Fin: p.Fin})
		case "udp":
			r = append(r, tunnel.Regle{Proto: 17, Debut: p.Debut, Fin: p.Fin})
		}
	}
	return r, nil
}
