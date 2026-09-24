// Package dns répond aux noms du VPN : maison.sas.internal donne
// l'adresse de la machine « maison ». Les autres noms sont transmis à un
// résolveur public, pour que les appareils qui passent tout leur DNS par le
// VPN puissent encore naviguer.
package dns

import (
	"net/netip"
	"strings"
	"sync"

	mdns "github.com/miekg/dns"
)

type Serveur struct {
	domaine string // « sas.internal. »
	amont   string
	mu      sync.RWMutex
	noms    map[string]netip.Addr
	// filtre dit si l'appareil à l'adresse de peut connaître celui à
	// l'adresse vers. Nil : tout le monde voit tout.
	filtre func(de, vers netip.Addr) bool
}

func Nouveau(domaine, amont string) *Serveur {
	return &Serveur{domaine: mdns.Fqdn(strings.ToLower(domaine)), amont: amont, noms: map[string]netip.Addr{}}
}

// DefinirFiltre : à appeler avant de lancer le serveur.
func (s *Serveur) DefinirFiltre(f func(de, vers netip.Addr) bool) {
	s.mu.Lock()
	s.filtre = f
	s.mu.Unlock()
}

// Definir remplace la table : nom court vers adresse.
func (s *Serveur) Definir(noms map[string]netip.Addr) {
	t := make(map[string]netip.Addr, len(noms))
	for n, a := range noms {
		t[strings.ToLower(n)+"."+s.domaine] = a
	}
	s.mu.Lock()
	s.noms = t
	s.mu.Unlock()
}

func (s *Serveur) ServeDNS(w mdns.ResponseWriter, r *mdns.Msg) {
	if len(r.Question) != 1 {
		m := new(mdns.Msg)
		m.SetRcode(r, mdns.RcodeFormatError)
		w.WriteMsg(m)
		return
	}
	q := r.Question[0]
	nom := strings.ToLower(q.Name)
	if nom != s.domaine && !strings.HasSuffix(nom, "."+s.domaine) {
		s.transmettre(w, r)
		return
	}
	m := new(mdns.Msg)
	m.SetReply(r)
	m.Authoritative = true
	s.mu.RLock()
	a, ok := s.noms[nom]
	filtre := s.filtre
	s.mu.RUnlock()
	// Un nom que le demandeur n'a pas le droit de connaître n'existe pas
	// pour lui : même réponse que pour un nom inconnu, pour ne rien laisser
	// deviner.
	if ok && filtre != nil {
		de, err := netip.ParseAddrPort(w.RemoteAddr().String())
		if err != nil || !filtre(de.Addr().Unmap(), a) {
			ok = false
		}
	}
	switch {
	case !ok:
		m.Rcode = mdns.RcodeNameError
	case q.Qtype == mdns.TypeA || q.Qtype == mdns.TypeANY:
		m.Answer = append(m.Answer, &mdns.A{
			Hdr: mdns.RR_Header{Name: q.Name, Rrtype: mdns.TypeA, Class: mdns.ClassINET, Ttl: 30},
			A:   a.AsSlice(),
		})
	}
	w.WriteMsg(m)
}

func (s *Serveur) transmettre(w mdns.ResponseWriter, r *mdns.Msg) {
	c := new(mdns.Client)
	if w.RemoteAddr().Network() == "tcp" {
		c.Net = "tcp"
	}
	rep, _, err := c.Exchange(r, s.amont)
	if err != nil {
		m := new(mdns.Msg)
		m.SetRcode(r, mdns.RcodeServerFailure)
		w.WriteMsg(m)
		return
	}
	w.WriteMsg(rep)
}

// Lancer écoute en UDP et en TCP sur l'adresse donnée.
func (s *Serveur) Lancer(adresse string) error {
	erreurs := make(chan error, 2)
	for _, reseau := range []string{"udp", "tcp"} {
		srv := &mdns.Server{Addr: adresse, Net: reseau, Handler: s}
		go func() { erreurs <- srv.ListenAndServe() }()
	}
	return <-erreurs
}
