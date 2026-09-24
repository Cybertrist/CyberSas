package tunnel

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"encoding/binary"
	"log/slog"
	"net"
	"net/netip"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Cybertrist/CyberSas/internal/noise"
)

// Tun : l'interface réseau virtuelle, qui rend et prend des paquets IP
// bruts. Sous Linux, /dev/net/tun ; sous Android, le descripteur donné par
// VpnService ; dans les tests, une simple file.
type Tun interface {
	Read([]byte) (int, error)
	Write([]byte) (int, error)
	Close() error
}

// Pair : un appareil avec qui l'on échange.
type Pair struct {
	Publique [32]byte
	// Les adresses que ce pair a le droit d'utiliser comme source, et
	// celles vers lesquelles on lui envoie les paquets.
	Adresses []netip.Prefix
	// Point, s'il est donné, fait de nous l'initiateur : c'est le client
	// qui connaît l'adresse du serveur. Sinon, on l'apprend du pair.
	Point netip.AddrPort
	// Maintien : un paquet vide à cet intervalle garde ouverte la
	// traduction d'adresse de la box. Zéro pour ne rien envoyer.
	Maintien time.Duration
}

type EtatPair struct {
	Publique        [32]byte
	Point           netip.AddrPort
	DernierePoignee time.Time
	Recus, Envoyes  uint64
}

type pair struct {
	pub      [32]byte
	adresses atomic.Pointer[[]netip.Prefix]

	mu                             sync.Mutex
	point                          netip.AddrPort
	initie                         bool
	maintien                       time.Duration
	courante, precedente, suivante *session
	poignee                        *noise.Initiateur
	indicePoignee                  uint32
	derniereTentative              time.Time
	debutTentatives                time.Time
	dernierHorodatage              []byte
	dernierEnvoi, dernierePoignee  time.Time
	recus, envoyes                 uint64
	attente                        [][]byte
	// derniereReception : dernier paquet authentifié reçu de ce pair.
	// sansReponseDepuis : premier paquet de données envoyé depuis.
	derniereReception, sansReponseDepuis time.Time
}

func (p *pair) autorise(a netip.Addr) bool {
	for _, pr := range *p.adresses.Load() {
		if pr.Contains(a) {
			return true
		}
	}
	return false
}

// Moteur : un bout du tunnel. Le serveur en a un avec un pair par
// appareil, un client en a un avec un seul pair, le serveur.
type Moteur struct {
	prive   atomic.Pointer[ecdh.PrivateKey]
	tun     Tun
	conn    *net.UDPConn
	journal *slog.Logger

	// Ordre des verrous : toujours pair.mu avant Moteur.mu, jamais l'inverse.
	mu      sync.RWMutex
	pairs   map[[32]byte]*pair
	indices map[uint32]*pair

	sansReponseMax time.Duration
}

func Nouveau(prive *ecdh.PrivateKey, tun Tun, conn *net.UDPConn, journal *slog.Logger) *Moteur {
	if journal == nil {
		journal = slog.New(slog.DiscardHandler)
	}
	m := &Moteur{tun: tun, conn: conn, journal: journal,
		pairs: map[[32]byte]*pair{}, indices: map[uint32]*pair{}, sansReponseMax: sansReponseDefaut}
	m.prive.Store(prive)
	return m
}

// DefinirCle change la clé privée de ce bout du tunnel, après une nouvelle
// inscription. Toutes les sessions établies avec l'ancienne tombent : il
// faut redonner les pairs ensuite.
func (m *Moteur) DefinirCle(prive *ecdh.PrivateKey) {
	m.mu.Lock()
	m.prive.Store(prive)
	m.pairs = map[[32]byte]*pair{}
	m.indices = map[uint32]*pair{}
	m.mu.Unlock()
}

// DefinirPairs remplace la liste des pairs. Ceux qui disparaissent perdent
// leurs sessions sur-le-champ : un appareil retiré est coupé.
func (m *Moteur) DefinirPairs(liste []Pair) {
	type maj struct {
		p *pair
		c Pair
	}
	var majs []maj
	m.mu.Lock()
	vus := map[[32]byte]bool{}
	for _, c := range liste {
		p := m.pairs[c.Publique]
		if p == nil {
			p = &pair{pub: c.Publique}
			m.pairs[c.Publique] = p
		}
		a := slices.Clone(c.Adresses)
		p.adresses.Store(&a)
		vus[c.Publique] = true
		majs = append(majs, maj{p, c})
	}
	for k, p := range m.pairs {
		if !vus[k] {
			delete(m.pairs, k)
			for i, q := range m.indices {
				if q == p {
					delete(m.indices, i)
				}
			}
		}
	}
	m.mu.Unlock()
	for _, x := range majs {
		x.p.mu.Lock()
		if x.c.Point.IsValid() {
			x.p.point, x.p.initie = x.c.Point, true
		}
		x.p.maintien = x.c.Maintien
		x.p.mu.Unlock()
	}
}

func (m *Moteur) Etat() []EtatPair {
	m.mu.RLock()
	liste := make([]*pair, 0, len(m.pairs))
	for _, p := range m.pairs {
		liste = append(liste, p)
	}
	m.mu.RUnlock()
	var r []EtatPair
	for _, p := range liste {
		p.mu.Lock()
		r = append(r, EtatPair{p.pub, p.point, p.dernierePoignee, p.recus, p.envoyes})
		p.mu.Unlock()
	}
	return r
}

// Lancer fait tourner le moteur jusqu'à l'annulation du contexte.
func (m *Moteur) Lancer(ctx context.Context) error {
	erreurs := make(chan error, 2)
	go func() { erreurs <- m.boucleTun() }()
	go func() { erreurs <- m.boucleUDP() }()
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			m.conn.Close()
			m.tun.Close()
			return nil
		case err := <-erreurs:
			return err
		case <-t.C:
			m.minuterie()
		}
	}
}

func (m *Moteur) ecrire(msg []byte, point netip.AddrPort) {
	if point.IsValid() {
		m.conn.WriteToUDPAddrPort(msg, point)
	}
}

// router choisit le pair dont une adresse contient la destination, le
// préfixe le plus précis l'emportant.
func (m *Moteur) router(dest netip.Addr) *pair {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var meilleur *pair
	bits := -1
	for _, p := range m.pairs {
		for _, pr := range *p.adresses.Load() {
			if pr.Contains(dest) && pr.Bits() > bits {
				meilleur, bits = p, pr.Bits()
			}
		}
	}
	return meilleur
}

// --- sortie : de l'interface vers le réseau ----------------------------------

func (m *Moteur) boucleTun() error {
	buf := make([]byte, MTU+128)
	for {
		n, err := m.tun.Read(buf)
		if err != nil {
			return err
		}
		ip, ok := lireIPv4(buf[:n])
		if !ok {
			continue
		}
		if p := m.router(netip.AddrFrom4(ip.dest)); p != nil {
			m.envoyerPaquet(p, append([]byte(nil), buf[:ip.longueur]...))
		}
	}
}

func (m *Moteur) envoyerPaquet(p *pair, paquet []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()
	s := p.courante
	if !s.utilisable() {
		// Le serveur n'initie jamais : sans session, le paquet est perdu,
		// et le client en rouvrira une de lui-même.
		if p.initie && len(p.attente) < maxEnAttente {
			p.attente = append(p.attente, paquet)
		}
		m.lancerPoignee(p)
		return
	}
	if s.aRenouveler() {
		m.lancerPoignee(p)
	}
	p.envoyes++
	p.dernierEnvoi = time.Now()
	if p.initie && p.sansReponseDepuis.IsZero() {
		p.sansReponseDepuis = p.dernierEnvoi
	}
	m.ecrire(s.chiffrer(paquet), p.point)
}

// lancerPoignee envoie une initiation, au plus toutes les cinq secondes.
// Appelée avec p.mu tenu.
func (m *Moteur) lancerPoignee(p *pair) {
	if !p.initie || !p.point.IsValid() {
		return
	}
	now := time.Now()
	if p.poignee != nil && now.Sub(p.derniereTentative) < relancerApres {
		return
	}
	if p.debutTentatives.IsZero() {
		p.debutTentatives = now
	}
	ini := noise.NouvelInitiateur(m.prive.Load(), p.pub[:], Prologue)
	corps, err := ini.Message1(horodatage(now))
	if err != nil {
		m.journal.Warn("initiation impossible", "erreur", err)
		return
	}
	idx := indiceAleatoire()
	m.mu.Lock()
	if p.indicePoignee != 0 {
		delete(m.indices, p.indicePoignee)
	}
	m.indices[idx] = p
	m.mu.Unlock()
	p.poignee, p.indicePoignee, p.derniereTentative = ini, idx, now

	msg := binary.LittleEndian.AppendUint32(entete(typeInitiation), idx)
	m.ecrire(append(msg, corps...), p.point)
}

// --- entrée : du réseau vers l'interface ------------------------------------

func (m *Moteur) boucleUDP() error {
	buf := make([]byte, 1<<16)
	for {
		n, src, err := m.conn.ReadFromUDPAddrPort(buf)
		if err != nil {
			return err
		}
		if n < 4 {
			continue
		}
		src = netip.AddrPortFrom(src.Addr().Unmap(), src.Port())
		msg := buf[:n]
		switch msg[0] {
		case typeInitiation:
			m.recevoirInitiation(msg, src)
		case typeReponse:
			m.recevoirReponse(msg)
		case typeDonnees:
			m.recevoirDonnees(msg, src)
		}
	}
}

func (m *Moteur) recevoirInitiation(msg []byte, src netip.AddrPort) {
	if len(msg) != tailleInitiation {
		return
	}
	envoyeur := binary.LittleEndian.Uint32(msg[4:8])
	r := noise.NouveauRepondeur(m.prive.Load(), Prologue)
	publique, charge, err := r.LireMessage1(msg[8:])
	if err != nil || len(charge) != tailleHorodatage {
		return
	}
	var cle [32]byte
	copy(cle[:], publique)
	m.mu.RLock()
	p := m.pairs[cle]
	m.mu.RUnlock()
	if p == nil {
		m.journal.Info("initiation d'une clé inconnue", "source", src)
		return
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	// Une initiation qui n'est pas plus récente que la dernière est un
	// rejeu : on l'ignore sans répondre.
	if p.dernierHorodatage != nil && bytes.Compare(charge, p.dernierHorodatage) <= 0 {
		m.journal.Warn("initiation rejouée", "source", src)
		return
	}
	corps, cles, err := r.Message2(nil)
	if err != nil {
		return
	}
	p.dernierHorodatage = charge
	locale := indiceAleatoire()
	s := nouvelleSession(locale, envoyeur, cles, false)
	m.mu.Lock()
	if p.suivante != nil {
		delete(m.indices, p.suivante.locale)
	}
	m.indices[locale] = p
	m.mu.Unlock()
	// La session n'est promue qu'au premier paquet de données reçu avec
	// elle : c'est la preuve que le client détient bien les mêmes clés.
	p.suivante = s
	if !p.initie {
		p.point = src
	}
	rep := binary.LittleEndian.AppendUint32(entete(typeReponse), locale)
	rep = binary.LittleEndian.AppendUint32(rep, envoyeur)
	m.ecrire(append(rep, corps...), src)
}

func (m *Moteur) recevoirReponse(msg []byte) {
	if len(msg) != tailleReponse {
		return
	}
	envoyeur := binary.LittleEndian.Uint32(msg[4:8])
	dest := binary.LittleEndian.Uint32(msg[8:12])
	m.mu.RLock()
	p := m.indices[dest]
	m.mu.RUnlock()
	if p == nil {
		return
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.poignee == nil || p.indicePoignee != dest {
		return
	}
	_, cles, err := p.poignee.LireMessage2(msg[12:])
	if err != nil {
		return
	}
	s := nouvelleSession(dest, envoyeur, cles, true)
	m.mu.Lock()
	if p.precedente != nil {
		delete(m.indices, p.precedente.locale)
	}
	m.mu.Unlock()
	p.precedente, p.courante = p.courante, s
	p.poignee, p.indicePoignee = nil, 0
	p.debutTentatives = time.Time{}
	p.dernierePoignee = time.Now()
	p.derniereReception, p.sansReponseDepuis = p.dernierePoignee, time.Time{}

	// Les paquets en attente partent. S'il n'y en a pas, un paquet vide
	// confirme la session au serveur, qui ne s'en sert qu'à partir de là.
	attente := p.attente
	p.attente = nil
	if len(attente) == 0 {
		attente = [][]byte{nil}
	}
	for _, paquet := range attente {
		m.ecrire(s.chiffrer(paquet), p.point)
		p.envoyes++
	}
	p.dernierEnvoi = time.Now()
}

func (m *Moteur) recevoirDonnees(msg []byte, src netip.AddrPort) {
	if len(msg) < enteteDonnees+tailleTag {
		return
	}
	dest := binary.LittleEndian.Uint32(msg[4:8])
	m.mu.RLock()
	p := m.indices[dest]
	m.mu.RUnlock()
	if p == nil {
		return
	}
	p.mu.Lock()
	var s *session
	for _, c := range []*session{p.courante, p.suivante, p.precedente} {
		if c != nil && c.locale == dest {
			s = c
			break
		}
	}
	p.mu.Unlock()
	if s == nil || time.Since(s.creee) >= rejeterApres {
		return
	}
	clair, ok := s.dechiffrer(msg)
	if !ok {
		return
	}

	p.mu.Lock()
	if s == p.suivante {
		m.mu.Lock()
		if p.precedente != nil {
			delete(m.indices, p.precedente.locale)
		}
		m.mu.Unlock()
		p.precedente, p.courante, p.suivante = p.courante, s, nil
		p.dernierePoignee = time.Now()
	}
	// Itinérance : le serveur suit l'appareil s'il change de réseau. Seul un
	// paquet authentifié, et jamais vu, peut déplacer le point.
	if !p.initie {
		p.point = src
	}
	p.recus++
	now := time.Now()
	p.derniereReception, p.sansReponseDepuis = now, time.Time{}
	// Maintien passif : le serveur répond à un maintien s'il est resté
	// muet. Le client, lui, ne répond jamais aux maintiens, sinon les deux
	// se renverraient la balle.
	if len(clair) == 0 && !p.initie && now.Sub(p.dernierEnvoi) >= maintienPassif && p.courante.utilisable() {
		m.ecrire(p.courante.chiffrer(nil), p.point)
		p.envoyes++
		p.dernierEnvoi = now
	}
	p.mu.Unlock()

	if len(clair) == 0 {
		return // paquet de maintien
	}
	ip, ok := lireIPv4(clair)
	if !ok {
		return
	}
	if !p.autorise(netip.AddrFrom4(ip.source)) {
		m.journal.Warn("source usurpée", "source", netip.AddrFrom4(ip.source), "point", src)
		return
	}
	m.tun.Write(clair[:ip.longueur])
}

// --- minuterie ---------------------------------------------------------------

func (m *Moteur) minuterie() {
	m.mu.RLock()
	liste := make([]*pair, 0, len(m.pairs))
	for _, p := range m.pairs {
		liste = append(liste, p)
	}
	m.mu.RUnlock()

	now := time.Now()
	for _, p := range liste {
		p.mu.Lock()
		for _, s := range []**session{&p.precedente, &p.courante, &p.suivante} {
			if *s != nil && now.Sub((*s).creee) >= rejeterApres {
				m.mu.Lock()
				delete(m.indices, (*s).locale)
				m.mu.Unlock()
				*s = nil
			}
		}
		if p.initie {
			// Session à renouveler, ou morte de l'autre côté : des données
			// sont parties sans retour, ou même les maintiens ne reviennent
			// plus.
			morte := (!p.sansReponseDepuis.IsZero() && now.Sub(p.sansReponseDepuis) > m.sansReponseMax) ||
				(p.maintien > 0 && p.courante != nil && now.Sub(p.derniereReception) > p.maintien+m.sansReponseMax)
			if p.courante.aRenouveler() || morte {
				m.lancerPoignee(p)
			}
			if p.maintien > 0 && p.courante.utilisable() && now.Sub(p.dernierEnvoi) >= p.maintien {
				m.ecrire(p.courante.chiffrer(nil), p.point)
				p.envoyes++
				p.dernierEnvoi = now
			}
			// Serveur injoignable depuis trop longtemps : on ne garde pas
			// indéfiniment de vieux paquets.
			if !p.debutTentatives.IsZero() && now.Sub(p.debutTentatives) > abandonnerApres {
				p.attente = nil
			}
		}
		p.mu.Unlock()
	}
}
