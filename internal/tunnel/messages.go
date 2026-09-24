// Package tunnel est le moteur du VPN CyberSas : il lit les paquets IP de
// l'interface virtuelle, les chiffre, les envoie en UDP, et fait l'inverse
// à l'arrivée.
//
// Le protocole, en bref (le détail est dans docs/protocole.md) :
//
//   - Trois messages. Initiation et réponse forment la poignée de main
//     Noise IK (package noise). Données transporte un paquet IP chiffré.
//   - Seul le client initie. Le serveur ne connaît l'adresse d'un appareil
//     qu'une fois que celui-ci s'est authentifié, et la met à jour s'il
//     change de réseau.
//   - Chaque session a sa paire de clés et vit trois minutes au plus. Le
//     client en renégocie une toutes les deux minutes.
//   - Chaque paquet de données porte un compteur, qui sert de nonce. Un
//     compteur déjà vu, ou trop ancien, est rejeté : rejouer un paquet
//     capturé ne sert à rien.
//   - Un paquet ne sort du tunnel que si son adresse source appartient à
//     l'appareil qui l'a chiffré : on ne peut pas se faire passer pour un
//     autre appareil, même en étant dans le VPN.
package tunnel

import (
	"encoding/binary"
	"time"

	"github.com/Cybertrist/CyberSas/internal/noise"
)

// Prologue : haché au départ de chaque poignée de main. Une autre version
// du protocole ne pourra pas s'entendre avec celle-ci par erreur.
var Prologue = []byte("CyberSas tunnel v1")

const (
	typeInitiation = 1
	typeReponse    = 2
	typeDonnees    = 3

	tailleHorodatage = 12
	tailleTag        = 16

	// type (1) + réservé (3) + indice de l'émetteur (4) + Noise
	tailleInitiation = 8 + noise.TailleMsg1 + tailleHorodatage + tailleTag
	// type + réservé + indice de l'émetteur + indice du destinataire + Noise
	tailleReponse = 12 + noise.TailleMsg2 + tailleTag
	// type + réservé + indice du destinataire (4) + compteur (8)
	enteteDonnees = 16

	// MTU de l'interface : 1500 moins l'en-tête IPv6 (40), UDP (8), notre
	// en-tête (16) et le tag (16), arrondi au multiple de 16 inférieur.
	MTU = 1420
)

const (
	renouvelerApres  = 120 * time.Second
	rejeterApres     = 180 * time.Second
	relancerApres    = 5 * time.Second
	abandonnerApres  = 90 * time.Second
	renouvelerApresN = uint64(1) << 60
	rejeterApresN    = ^uint64(0) - (1 << 13)
	maxEnAttente     = 32
	// Le serveur répond à un paquet de maintien s'il n'a rien envoyé depuis
	// ce délai : le client sait ainsi que la liaison vit.
	maintienPassif = 10 * time.Second
)

// Des données parties sans rien en retour depuis ce délai : la session est
// sans doute morte de l'autre côté (serveur redémarré), on en rouvre une
// sans attendre le renouvellement. Chaque moteur en garde sa copie, que
// les tests abrègent.
const sansReponseDefaut = 15 * time.Second

func entete(t byte) []byte {
	return []byte{t, 0, 0, 0}
}

// horodatage TAI64N : secondes depuis 1970 décalées de 2^62, puis les
// nanosecondes. Il croît avec le temps et se compare octet par octet : le
// serveur refuse une initiation qui n'est pas plus récente que la dernière
// vue, ce qui empêche de rejouer une initiation capturée.
func horodatage(t time.Time) []byte {
	var b [tailleHorodatage]byte
	binary.BigEndian.PutUint64(b[:8], uint64(t.Unix())+(1<<62))
	binary.BigEndian.PutUint32(b[8:], uint32(t.Nanosecond()))
	return b[:]
}

// Lecture minimale d'un paquet IPv4 : version, longueur totale, adresses.
type ipv4 struct {
	longueur int
	source   [4]byte
	dest     [4]byte
}

func lireIPv4(p []byte) (ipv4, bool) {
	if len(p) < 20 || p[0]>>4 != 4 {
		return ipv4{}, false
	}
	var r ipv4
	r.longueur = int(binary.BigEndian.Uint16(p[2:4]))
	if r.longueur < 20 || r.longueur > len(p) {
		return ipv4{}, false
	}
	copy(r.source[:], p[12:16])
	copy(r.dest[:], p[16:20])
	return r, true
}
