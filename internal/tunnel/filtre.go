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
type cleFlux struct {
	proto                  uint8
	local, distant         [4]byte
	portLocal, portDistant uint16
}

type suivi struct {
	mu   sync.Mutex
	flux map[cleFlux]time.Time
}

const maxFlux = 100000

func dureeFlux(proto uint8) time.Duration {
	switch proto {
	case protoTCP:
		return 5 * time.Minute
	case protoUDP:
		return time.Minute
	}
	return 30 * time.Second
}

// noter retient un paquet qui sort, sa réponse pourra entrer.
func (s *suivi) noter(ip ipv4) {
	if !ip.ports {
		return
	}
	k := cleFlux{ip.proto, ip.source, ip.dest, ip.portSrc, ip.portDst}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.flux == nil {
		s.flux = map[cleFlux]time.Time{}
	}
	if _, ok := s.flux[k]; !ok && len(s.flux) >= maxFlux {
		return
	}
	s.flux[k] = time.Now().Add(dureeFlux(ip.proto))
}

// retour : ce paquet qui entre répond-il à un flux que nous avons ouvert ?
func (s *suivi) retour(ip ipv4) bool {
	if !ip.ports {
		return false
	}
	k := cleFlux{ip.proto, ip.dest, ip.source, ip.portDst, ip.portSrc}
	s.mu.Lock()
	defer s.mu.Unlock()
	fin, ok := s.flux[k]
	return ok && time.Now().Before(fin)
}

func (s *suivi) nettoyer() {
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, fin := range s.flux {
		if now.After(fin) {
			delete(s.flux, k)
		}
	}
}
