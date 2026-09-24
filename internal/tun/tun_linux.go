//go:build linux

// Package tun ouvre l'interface réseau virtuelle sous Linux : le noyau y
// dépose les paquets IP destinés au VPN, et le moteur y écrit ceux qui en
// sortent.
package tun

import (
	"fmt"
	"net/netip"
	"os"
	"os/exec"
	"strconv"

	"golang.org/x/sys/unix"
)

type Tun struct {
	*os.File
	Nom string
}

// Ouvrir crée l'interface, sans en-tête de paquet (IFF_NO_PI) : le moteur
// lit et écrit des paquets IP bruts.
func Ouvrir(nom string) (*Tun, error) {
	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("ouverture de /dev/net/tun : %w", err)
	}
	ifr, err := unix.NewIfreq(nom)
	if err != nil {
		unix.Close(fd)
		return nil, err
	}
	ifr.SetUint16(unix.IFF_TUN | unix.IFF_NO_PI)
	if err := unix.IoctlIfreq(fd, unix.TUNSETIFF, ifr); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("création de %s : %w", nom, err)
	}
	// Non bloquant : Go passe par son ordonnanceur réseau, et fermer le
	// fichier débloque une lecture en cours.
	if err := unix.SetNonblock(fd, true); err != nil {
		unix.Close(fd)
		return nil, err
	}
	return &Tun{File: os.NewFile(uintptr(fd), "/dev/net/tun"), Nom: nom}, nil
}

// Configurer donne son adresse à l'interface et la monte.
func (t *Tun) Configurer(adresse netip.Prefix, mtu int) error {
	for _, args := range [][]string{
		{"addr", "replace", adresse.String(), "dev", t.Nom},
		{"link", "set", "dev", t.Nom, "mtu", strconv.Itoa(mtu), "up"},
	} {
		if sortie, err := exec.Command("ip", args...).CombinedOutput(); err != nil {
			return fmt.Errorf("ip %v : %v : %s", args, err, sortie)
		}
	}
	return nil
}
