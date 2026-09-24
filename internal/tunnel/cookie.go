package tunnel

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/binary"
	"errors"
	"net/netip"
	"sync"
	"time"

	"golang.org/x/crypto/blake2s"
	"golang.org/x/crypto/chacha20poly1305"
)

// Protection contre l'inondation, reprise du mécanisme de WireGuard.
//
// Une poignée de main coûte deux échanges X25519 au serveur. Sans
// protection, n'importe qui pourrait lui en envoyer des milliers par
// seconde. Deux codes, calculés sur le message, l'en empêchent :
//
//   - mac1 est calculé avec la clé publique du destinataire. Celui qui ne
//     la connaît pas ne peut pas produire un message que le serveur prendra
//     la peine de déchiffrer. La vérification ne coûte qu'un hachage.
//   - mac2 est calculé avec un cookie que le serveur a donné à cette
//     adresse IP. Quand il est sous charge, le serveur exige un mac2 valide,
//     et répond aux autres par un cookie. Obtenir un cookie prouve qu'on
//     reçoit bien les paquets envoyés à son adresse : on ne peut plus
//     inonder le serveur depuis des adresses usurpées.

var (
	etiquetteMac1   = []byte("mac1----")
	etiquetteCookie = []byte("cookie--")
)

// clesMac : dérivées de la clé publique du destinataire des messages.
type clesMac struct {
	mac1, cookie [32]byte
}

func deriverClesMac(publique []byte) clesMac {
	return clesMac{
		mac1:   blake2s.Sum256(append(append([]byte(nil), etiquetteMac1...), publique...)),
		cookie: blake2s.Sum256(append(append([]byte(nil), etiquetteCookie...), publique...)),
	}
}

// mac : BLAKE2s avec clé, sortie de 16 octets.
func mac(cle []byte, donnees []byte) (r [tailleMac]byte) {
	h, _ := blake2s.New128(cle)
	h.Write(donnees)
	copy(r[:], h.Sum(nil))
	return
}

// signerMacs écrit mac1 puis mac2 dans les 32 derniers octets du message.
// cookie peut être nul : mac2 reste alors à zéro. Rend mac1, dont le
// destinataire se servira pour chiffrer un éventuel cookie.
func signerMacs(msg []byte, cles clesMac, cookie *[tailleMac]byte) [tailleMac]byte {
	n := len(msg)
	m1 := mac(cles.mac1[:], msg[:n-2*tailleMac])
	copy(msg[n-2*tailleMac:], m1[:])
	if cookie != nil {
		m2 := mac(cookie[:], msg[:n-tailleMac])
		copy(msg[n-tailleMac:], m2[:])
	}
	return m1
}

// mac1Valide : comparaison en temps constant.
func mac1Valide(msg []byte, cles clesMac) bool {
	n := len(msg)
	attendu := mac(cles.mac1[:], msg[:n-2*tailleMac])
	return subtle.ConstantTimeCompare(attendu[:], msg[n-2*tailleMac:n-tailleMac]) == 1
}

func mac2Valide(msg []byte, cookie [tailleMac]byte) bool {
	n := len(msg)
	attendu := mac(cookie[:], msg[:n-tailleMac])
	return subtle.ConstantTimeCompare(attendu[:], msg[n-tailleMac:]) == 1
}

// fabrique des cookies, côté serveur. Un cookie est un MAC de l'adresse
// de l'expéditeur, sous une clé secrète renouvelée toutes les deux minutes.
type fabrique struct {
	mu     sync.Mutex
	secret [32]byte
	tourne time.Time
}

func (f *fabrique) cookie(src netip.AddrPort) [tailleMac]byte {
	f.mu.Lock()
	if time.Since(f.tourne) > dureeCookie {
		rand.Read(f.secret[:])
		f.tourne = time.Now()
	}
	secret := f.secret
	f.mu.Unlock()
	a := src.Addr().As16()
	d := binary.BigEndian.AppendUint16(a[:], src.Port())
	return mac(secret[:], d)
}

// reponseCookie fabrique le message qui donne son cookie à l'expéditeur.
// Le cookie est chiffré, avec en données associées le mac1 du message
// reçu : seul celui qui a envoyé ce message peut s'en servir.
func (f *fabrique) reponseCookie(indice uint32, mac1 [tailleMac]byte, src netip.AddrPort, cles clesMac) []byte {
	c := f.cookie(src)
	a, _ := chacha20poly1305.NewX(cles.cookie[:])
	msg := binary.LittleEndian.AppendUint32(entete(typeCookie), indice)
	nonce := make([]byte, chacha20poly1305.NonceSizeX)
	rand.Read(nonce)
	msg = append(msg, nonce...)
	return a.Seal(msg, nonce, c[:], mac1[:])
}

func lireCookie(msg []byte, cles clesMac, dernierMac1 [tailleMac]byte) ([tailleMac]byte, error) {
	var c [tailleMac]byte
	if len(msg) != tailleCookie {
		return c, errors.New("cookie : taille")
	}
	a, _ := chacha20poly1305.NewX(cles.cookie[:])
	clair, err := a.Open(nil, msg[8:32], msg[32:], dernierMac1[:])
	if err != nil {
		return c, err
	}
	copy(c[:], clair)
	return c, nil
}

// charge : combien de poignées de main le serveur traite par seconde.
type charge struct {
	mu      sync.Mutex
	seuil   int
	seconde time.Time
	compte  int
	parIP   limiteur[netip.Prefix]
}

// sousCharge compte une poignée de main de plus, et dit si le seuil de la
// seconde en cours est dépassé.
func (c *charge) sousCharge() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	if now.Sub(c.seconde) >= time.Second {
		c.seconde, c.compte = now, 0
	}
	c.compte++
	return c.compte > c.seuil
}

// autoriser : une adresse qui a prouvé la possession de son IP (mac2 valide)
// garde droit à dix poignées de main par seconde. Le seau est celui de son
// réseau, /32 en IPv4 et /64 en IPv6 : qui possède un /64 possède des
// milliards d'adresses, il ne doit pas avoir autant de seaux.
func (c *charge) autoriser(a netip.Addr) bool {
	a = a.Unmap()
	bits := 32
	if a.Is6() {
		bits = 64
	}
	p, _ := a.Prefix(bits)
	return c.parIP.autoriser(p)
}

// limiteur : un seau de jetons par clé, dix par seconde, vingt d'avance.
// La table est bornée ; pleine, elle oublie d'abord les seaux inactifs
// depuis plus d'une seconde, qui sont de toute façon pleins.
type limiteur[K comparable] struct {
	mu    sync.Mutex
	seaux map[K]*seau
}

type seau struct {
	jetons float64
	vu     time.Time
}

const (
	jetonsParSeconde = 10
	jetonsMax        = 20
	maxSeaux         = 100000
)

func (l *limiteur[K]) autoriser(cle K) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if l.seaux == nil {
		l.seaux = map[K]*seau{}
	}
	s := l.seaux[cle]
	if s == nil {
		if len(l.seaux) >= maxSeaux {
			l.oublier(now, time.Second)
			if len(l.seaux) >= maxSeaux {
				return false
			}
		}
		s = &seau{jetons: jetonsMax, vu: now}
		l.seaux[cle] = s
	}
	s.jetons = min(jetonsMax, s.jetons+now.Sub(s.vu).Seconds()*jetonsParSeconde)
	s.vu = now
	if s.jetons < 1 {
		return false
	}
	s.jetons--
	return true
}

// oublier les seaux inactifs depuis ce délai. Appelée avec l.mu tenu.
func (l *limiteur[K]) oublier(now time.Time, inactif time.Duration) {
	for k, s := range l.seaux {
		if now.Sub(s.vu) > inactif {
			delete(l.seaux, k)
		}
	}
}

func (l *limiteur[K]) nettoyer() {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.oublier(time.Now(), time.Minute)
}
