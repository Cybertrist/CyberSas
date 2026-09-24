package tunnel

import (
	"context"
	"crypto/ecdh"
	"encoding/binary"
	"errors"
	"net"
	"net/netip"
	"sync"
	"testing"
	"time"

	"github.com/Cybertrist/CyberSas/internal/noise"
)

// tunFactice : une interface virtuelle en mémoire. Ce que le moteur écrit
// arrive dans sortie ; ce qu'on pousse dans entree, le moteur le lit.
type tunFactice struct {
	entree, sortie chan []byte
	ferme          chan struct{}
	once           sync.Once
}

func nouveauTun() *tunFactice {
	return &tunFactice{entree: make(chan []byte, 16), sortie: make(chan []byte, 16), ferme: make(chan struct{})}
}

func (t *tunFactice) Read(b []byte) (int, error) {
	select {
	case p := <-t.entree:
		return copy(b, p), nil
	case <-t.ferme:
		return 0, errors.New("fermé")
	}
}

func (t *tunFactice) Write(b []byte) (int, error) {
	t.sortie <- append([]byte(nil), b...)
	return len(b), nil
}

func (t *tunFactice) Close() error { t.once.Do(func() { close(t.ferme) }); return nil }

// paquet IPv4 minimal, sans somme de contrôle : le moteur ne la lit pas.
func paquet(source, dest string, charge string) []byte {
	p := make([]byte, 20+len(charge))
	p[0] = 0x45
	binary.BigEndian.PutUint16(p[2:4], uint16(len(p)))
	s, d := netip.MustParseAddr(source).As4(), netip.MustParseAddr(dest).As4()
	copy(p[12:16], s[:])
	copy(p[16:20], d[:])
	copy(p[20:], charge)
	return p
}

func attendre(t *testing.T, c chan []byte) []byte {
	t.Helper()
	select {
	case p := <-c:
		return p
	case <-time.After(3 * time.Second):
		t.Fatal("rien n'est sorti du tunnel")
		return nil
	}
}

func rienNeSort(t *testing.T, c chan []byte) {
	t.Helper()
	select {
	case p := <-c:
		t.Fatalf("un paquet est sorti alors qu'il aurait dû être rejeté : %q", p[20:])
	case <-time.After(400 * time.Millisecond):
	}
}

func publique(k *ecdh.PrivateKey) (r [32]byte) {
	copy(r[:], k.PublicKey().Bytes())
	return
}

type banc struct {
	serveurTun, clientTun *tunFactice
	serveurPort           netip.AddrPort
	clientConn            *net.UDPConn
	clePrivee             *ecdh.PrivateKey
	clePubliqueServeur    [32]byte
	annuler               context.CancelFunc
	// capture : tout ce que le client envoie passe par ce relais, pour
	// pouvoir rejouer ou abîmer des paquets.
	capture chan []byte
}

func nouveauBanc(t *testing.T) *banc {
	cleServeur, _ := noise.GenererCle()
	cleClient, _ := noise.GenererCle()
	b := &banc{serveurTun: nouveauTun(), clientTun: nouveauTun(), clePrivee: cleClient, clePubliqueServeur: publique(cleServeur), capture: make(chan []byte, 64)}

	cs, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	cc, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	relais, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	b.serveurPort = cs.LocalAddr().(*net.UDPAddr).AddrPort()
	b.clientConn = cc

	ctx, annuler := context.WithCancel(context.Background())
	b.annuler = annuler
	t.Cleanup(func() { annuler(); relais.Close() })

	// Relais client <-> serveur : copie aussi chaque paquet du client.
	go func() {
		buf := make([]byte, 2048)
		var client netip.AddrPort
		for {
			n, src, err := relais.ReadFromUDPAddrPort(buf)
			if err != nil {
				return
			}
			if src == b.serveurPort {
				relais.WriteToUDPAddrPort(buf[:n], client)
				continue
			}
			client = src
			b.capture <- append([]byte(nil), buf[:n]...)
			relais.WriteToUDPAddrPort(buf[:n], b.serveurPort)
		}
	}()

	serveur := Nouveau(cleServeur, b.serveurTun, cs, nil)
	serveur.DefinirPairs([]Pair{{Publique: publique(cleClient), Adresses: []netip.Prefix{netip.MustParsePrefix("10.77.0.2/32")}}})
	client := Nouveau(cleClient, b.clientTun, cc, nil)
	client.DefinirPairs([]Pair{{Publique: publique(cleServeur), Adresses: []netip.Prefix{netip.MustParsePrefix("10.77.0.0/24")},
		Point: relais.LocalAddr().(*net.UDPAddr).AddrPort()}})
	go serveur.Lancer(ctx)
	go client.Lancer(ctx)
	return b
}

// Le dernier paquet de données envoyé par le client et capturé au relais.
func (b *banc) dernierPaquetDonnees(t *testing.T) []byte {
	var dernier []byte
	for {
		select {
		case p := <-b.capture:
			if p[0] == typeDonnees && len(p) > enteteDonnees+tailleTag {
				dernier = p
			}
		default:
			if dernier == nil {
				t.Fatal("aucun paquet de données capturé")
			}
			return dernier
		}
	}
}

func TestAllerRetour(t *testing.T) {
	b := nouveauBanc(t)
	b.clientTun.entree <- paquet("10.77.0.2", "10.77.0.1", "bonjour")
	if got := attendre(t, b.serveurTun.sortie); string(got[20:]) != "bonjour" {
		t.Fatalf("le serveur a reçu %q", got[20:])
	}
	b.serveurTun.entree <- paquet("10.77.0.1", "10.77.0.2", "salut")
	if got := attendre(t, b.clientTun.sortie); string(got[20:]) != "salut" {
		t.Fatalf("le client a reçu %q", got[20:])
	}
}

func TestRejeuRefuse(t *testing.T) {
	b := nouveauBanc(t)
	b.clientTun.entree <- paquet("10.77.0.2", "10.77.0.1", "virement")
	attendre(t, b.serveurTun.sortie)
	capture := b.dernierPaquetDonnees(t)
	// Un attaquant renvoie le paquet capturé, depuis ailleurs.
	b.clientConn.WriteToUDPAddrPort(capture, b.serveurPort)
	rienNeSort(t, b.serveurTun.sortie)
}

func TestPaquetModifieRefuse(t *testing.T) {
	b := nouveauBanc(t)
	b.clientTun.entree <- paquet("10.77.0.2", "10.77.0.1", "premier")
	attendre(t, b.serveurTun.sortie)
	capture := b.dernierPaquetDonnees(t)
	// Compteur neuf, contenu abîmé : le tag ne correspond plus.
	binary.LittleEndian.PutUint64(capture[8:16], 1000)
	capture[len(capture)-20] ^= 0xff
	b.clientConn.WriteToUDPAddrPort(capture, b.serveurPort)
	rienNeSort(t, b.serveurTun.sortie)
}

func TestSourceUsurpeeRefusee(t *testing.T) {
	b := nouveauBanc(t)
	// Le client est 10.77.0.2 : il ne peut pas parler au nom de 10.77.0.9.
	b.clientTun.entree <- paquet("10.77.0.9", "10.77.0.1", "c'est moi le 9")
	rienNeSort(t, b.serveurTun.sortie)
	b.clientTun.entree <- paquet("10.77.0.2", "10.77.0.1", "vraiment moi")
	if got := attendre(t, b.serveurTun.sortie); string(got[20:]) != "vraiment moi" {
		t.Fatalf("reçu %q", got[20:])
	}
}

func TestInitiationRejoueeIgnoree(t *testing.T) {
	b := nouveauBanc(t)
	b.clientTun.entree <- paquet("10.77.0.2", "10.77.0.1", "a")
	attendre(t, b.serveurTun.sortie)
	var initiation []byte
	for len(b.capture) > 0 {
		if p := <-b.capture; p[0] == typeInitiation {
			initiation = p
		}
	}
	if initiation == nil {
		t.Fatal("pas d'initiation capturée")
	}
	// Rejouée, l'initiation ne doit obtenir aucune réponse.
	espion, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	defer espion.Close()
	espion.WriteToUDPAddrPort(initiation, b.serveurPort)
	espion.SetReadDeadline(time.Now().Add(400 * time.Millisecond))
	if _, _, err := espion.ReadFromUDPAddrPort(make([]byte, 256)); err == nil {
		t.Fatal("le serveur a répondu à une initiation rejouée")
	}
}

func TestCleInconnueRefusee(t *testing.T) {
	b := nouveauBanc(t)
	// Un intrus qui connaît la clé publique du serveur, et même l'adresse
	// d'un appareil, mais dont la clé n'est pas dans la liste.
	intrus, _ := noise.GenererCle()
	conn, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	tunIntrus := nouveauTun()
	m := Nouveau(intrus, tunIntrus, conn, nil)
	m.DefinirPairs([]Pair{{Publique: b.clePubliqueServeur, Adresses: []netip.Prefix{netip.MustParsePrefix("10.77.0.0/24")}, Point: b.serveurPort}})
	ctx, annuler := context.WithCancel(context.Background())
	defer annuler()
	go m.Lancer(ctx)

	tunIntrus.entree <- paquet("10.77.0.2", "10.77.0.1", "laissez-moi entrer")
	rienNeSort(t, b.serveurTun.sortie)
	for _, e := range m.Etat() {
		if !e.DernierePoignee.IsZero() {
			t.Fatal("l'intrus a obtenu une session")
		}
	}
}

func TestServeurRedemarre(t *testing.T) {
	cleServeur, _ := noise.GenererCle()
	cleClient, _ := noise.GenererCle()
	cs, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	cc, _ := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	port := cs.LocalAddr().(*net.UDPAddr).AddrPort()
	pairClient := []Pair{{Publique: publique(cleClient), Adresses: []netip.Prefix{netip.MustParsePrefix("10.77.0.2/32")}}}

	ctxS, arretS := context.WithCancel(context.Background())
	tunS := nouveauTun()
	s := Nouveau(cleServeur, tunS, cs, nil)
	s.DefinirPairs(pairClient)
	go s.Lancer(ctxS)

	ctx, annuler := context.WithCancel(context.Background())
	defer annuler()
	tunC := nouveauTun()
	c := Nouveau(cleClient, tunC, cc, nil)
	c.sansReponseMax = time.Second
	c.DefinirPairs([]Pair{{Publique: publique(cleServeur), Adresses: []netip.Prefix{netip.MustParsePrefix("10.77.0.0/24")}, Point: port}})
	go c.Lancer(ctx)

	tunC.entree <- paquet("10.77.0.2", "10.77.0.1", "avant")
	attendre(t, tunS.sortie)

	// Le serveur redémarre : même clé, même port, aucune session en mémoire.
	arretS()
	time.Sleep(200 * time.Millisecond)
	cs2, err := net.ListenUDP("udp4", net.UDPAddrFromAddrPort(port))
	if err != nil {
		t.Fatal(err)
	}
	tunS2 := nouveauTun()
	s2 := Nouveau(cleServeur, tunS2, cs2, nil)
	s2.DefinirPairs(pairClient)
	go s2.Lancer(ctx)

	// Le premier paquet se perd dans une session que le serveur a oubliée.
	// Le client s'en rend compte seul et rouvre une session.
	tunC.entree <- paquet("10.77.0.2", "10.77.0.1", "perdu")
	limite := time.Now().Add(10 * time.Second)
	for time.Now().Before(limite) {
		tunC.entree <- paquet("10.77.0.2", "10.77.0.1", "après")
		select {
		case p := <-tunS2.sortie:
			if string(p[20:]) == "après" {
				return
			}
		case <-time.After(time.Second):
		}
	}
	t.Fatal("le client ne s'est pas reconnecté au serveur redémarré")
}

func TestFenetreAntiRejeu(t *testing.T) {
	var f fenetre
	for _, n := range []uint64{0, 1, 2, 5, 4} {
		if !f.accepter(n) {
			t.Fatalf("compteur %d refusé", n)
		}
	}
	for _, n := range []uint64{0, 2, 5} {
		if f.accepter(n) {
			t.Fatalf("compteur %d accepté deux fois", n)
		}
	}
	if !f.accepter(3) {
		t.Fatal("un compteur en retard mais jamais vu doit passer")
	}
	if !f.accepter(5000) || f.accepter(5000-tailleFenetre) {
		t.Fatal("un compteur sorti de la fenêtre doit être refusé")
	}
}
