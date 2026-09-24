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
}

func Nouveau(domaine, amont string) *Serveur {
	return &Serveur{domaine: mdns.Fqdn(strings.ToLower(domaine)), amont: amont, noms: map[string]netip.Addr{}}
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
	s.mu.RUnlock()
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
