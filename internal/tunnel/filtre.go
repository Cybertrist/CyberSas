package tunnel

import (
	"sync"
	"time"
)

// Le filtre : ce qu'un pair a le droit d'ouvrir chez nous.
//
// Avec le chiffrement de bout en bout, le serveur ne voit plus les paquets
// entre appareils : il ne peut plus appliquer les règles d'accès. C'est
// donc l'appareil qui reçoit qui filtre, avec les règles que le serveur lui
// transmet. Un appareil malveillant ne peut rien y changer : il ne contrôle
// que ce qu'il envoie, pas ce que les autres acceptent.
//
// Ce qui est envoyé n'est jamais filtré. Le suivi des connexions retient
// chaque flux sortant, pour laisser entrer les réponses : ouvrir une page
// sur un autre appareil ne demande aucune règle dans l'autre sens.

// Regle : un protocole et une plage de ports. Proto 0 veut dire tout.
type Regle struct {
	Proto      uint8
	Debut, Fin uint16
}

type regles struct {
	toutes bool
	liste  []Regle
}

func (r *regles) autorise(ip ipv4) bool {
	if r == nil {
		return false
	}
	if r.toutes {
		return true
	}
	for _, x := range r.liste {
		switch {
		case x.Proto == 0:
			return true
		case x.Proto != ip.proto:
		case x.Proto == protoICMP:
			return true
		case ip.ports && ip.portDst >= x.Debut && ip.portDst <= x.Fin:
			return true
		}
	}
	return false
}

// suivi des connexions sortantes.
//
// Chaque pair a son propre budget d'entrées : un pair bavard ne peut pas
// remplir la table au point d'empêcher les réponses venant des autres.
type cleFlux struct {
	proto                  uint8
	local, distant         [4]byte
	portLocal, portDistant uint16
}

type flux struct {
	fin  time.Time
	pair *pair
}

type suivi struct {
	mu      sync.Mutex
	flux    map[cleFlux]flux
	parPair map[*pair]int
}

const fluxParPair = 10000

func dureeFlux(proto uint8) time.Duration {
	switch proto {
	case protoTCP:
		return 5 * time.Minute
	case protoUDP:
		return time.Minute
	}
	return 30 * time.Second
}

// suivable : ce qu'on retient. Pour l'ICMP, seules les demandes d'écho
// (type 8) : leur réponse (type 0) pourra entrer, rien d'autre.
func suivable(ip ipv4) bool {
	if !ip.ports {
		return false
	}
	return ip.proto != protoICMP || ip.typeICMP == 8
}

// noter retient un paquet qui sort vers ce pair : sa réponse pourra entrer.
func (s *suivi) noter(ip ipv4, p *pair) {
	if !suivable(ip) {
		return
	}
	k := cleFlux{ip.proto, ip.source, ip.dest, ip.portSrc, ip.portDst}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.flux == nil {
		s.flux, s.parPair = map[cleFlux]flux{}, map[*pair]int{}
	}
	if f, ok := s.flux[k]; ok {
		s.flux[k] = flux{time.Now().Add(dureeFlux(ip.proto)), f.pair}
		return
	}
	if s.parPair[p] >= fluxParPair {
		return
	}
	s.flux[k] = flux{time.Now().Add(dureeFlux(ip.proto)), p}
	s.parPair[p]++
}

// retour : ce paquet qui entre, venant de ce pair, répond-il à un flux que
// nous avons ouvert vers lui ?
func (s *suivi) retour(ip ipv4, p *pair) bool {
	if !ip.ports || (ip.proto == protoICMP && ip.typeICMP != 0) {
		return false
	}
	k := cleFlux{ip.proto, ip.dest, ip.source, ip.portDst, ip.portSrc}
	s.mu.Lock()
	defer s.mu.Unlock()
	f, ok := s.flux[k]
	return ok && f.pair == p && time.Now().Before(f.fin)
}

func (s *suivi) nettoyer() {
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, f := range s.flux {
		if now.After(f.fin) {
			delete(s.flux, k)
			if s.parPair[f.pair]--; s.parPair[f.pair] <= 0 {
				delete(s.parPair, f.pair)
			}
		}
	}
}

// reponseAutorisee : ce paquet sortant répond-il à ce qu'une règle laisse
// déjà entrer ? Alors inutile de le retenir : l'aller comme le retour sont
// couverts par la règle, et un pair autorisé ne peut pas remplir notre
// table en nous faisant répondre à des milliers de connexions.
func reponseAutorisee(ip ipv4, r *regles) bool {
	inverse := ip
	inverse.source, inverse.dest = ip.dest, ip.source
	inverse.portSrc, inverse.portDst = ip.portDst, ip.portSrc
	return ip.proto != protoICMP && r.autorise(inverse)
}
