// Package base garde les appareils inscrits et les clés d'inscription des
// machines, dans un fichier SQLite.
//
// Rien de secret n'y est stocké en clair : les jetons de l'API et les clés
// d'inscription n'y figurent que par leur empreinte SHA-256, et les clés
// privées des appareils n'arrivent jamais jusqu'au serveur.
package base

import (
	"crypto/sha256"
	"database/sql"
	"errors"
	"fmt"
	"net/netip"
	"regexp"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

var ErrIntrouvable = errors.New("introuvable")

type Base struct {
	db *sql.DB
}

type Appareil struct {
	ID           int64
	Nom          string
	ClePublique  string
	Adresse      netip.Addr
	Proprietaire string // adresse Google, vide pour une machine
	Etiquette    string // vide pour un appareil personnel
	Systeme      string
	Cree, Vu     time.Time
	Expire       time.Time // zéro : n'expire pas
}

const schema = `
CREATE TABLE IF NOT EXISTS appareils (
	id           INTEGER PRIMARY KEY,
	nom          TEXT NOT NULL UNIQUE,
	cle_publique TEXT NOT NULL UNIQUE,
	adresse      TEXT NOT NULL UNIQUE,
	proprietaire TEXT NOT NULL DEFAULT '',
	etiquette    TEXT NOT NULL DEFAULT '',
	systeme      TEXT NOT NULL DEFAULT '',
	cree         INTEGER NOT NULL,
	vu           INTEGER NOT NULL,
	expire       INTEGER NOT NULL DEFAULT 0,
	jeton        BLOB
);
CREATE TABLE IF NOT EXISTS cles (
	empreinte   BLOB PRIMARY KEY,
	etiquette   TEXT NOT NULL DEFAULT '',
	utilisateur TEXT NOT NULL DEFAULT '',
	expire      INTEGER NOT NULL
);`

func Ouvrir(chemin string) (*Base, error) {
	db, err := sql.Open("sqlite", "file:"+chemin+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		return nil, fmt.Errorf("schéma : %w", err)
	}
	return &Base{db: db}, nil
}

func Empreinte(s string) []byte {
	h := sha256.Sum256([]byte(s))
	return h[:]
}

const colonnes = `id, nom, cle_publique, adresse, proprietaire, etiquette, systeme, cree, vu, expire`

func lire(r interface{ Scan(...any) error }) (Appareil, error) {
	var a Appareil
	var adresse string
	var cree, vu, expire int64
	if err := r.Scan(&a.ID, &a.Nom, &a.ClePublique, &adresse, &a.Proprietaire, &a.Etiquette, &a.Systeme, &cree, &vu, &expire); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return a, ErrIntrouvable
		}
		return a, err
	}
	a.Adresse, _ = netip.ParseAddr(adresse)
	a.Cree, a.Vu = time.Unix(cree, 0), time.Unix(vu, 0)
	if expire != 0 {
		a.Expire = time.Unix(expire, 0)
	}
	return a, nil
}

func (b *Base) Appareils() ([]Appareil, error) {
	rows, err := b.db.Query(`SELECT ` + colonnes + ` FROM appareils ORDER BY nom`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var r []Appareil
	for rows.Next() {
		a, err := lire(rows)
		if err != nil {
			return nil, err
		}
		r = append(r, a)
	}
	return r, rows.Err()
}

func (b *Base) ParJeton(jeton string) (Appareil, error) {
	return lire(b.db.QueryRow(`SELECT `+colonnes+` FROM appareils WHERE jeton = ?`, Empreinte(jeton)))
}

func (b *Base) Supprimer(id int64) error {
	_, err := b.db.Exec(`DELETE FROM appareils WHERE id = ?`, id)
	return err
}

func (b *Base) SupprimerParNom(nom string) error {
	r, err := b.db.Exec(`DELETE FROM appareils WHERE nom = ?`, nom)
	if err != nil {
		return err
	}
	if n, _ := r.RowsAffected(); n == 0 {
		return ErrIntrouvable
	}
	return nil
}

var horsNom = regexp.MustCompile(`[^a-z0-9-]+`)

// NomPropre : minuscules, chiffres et tirets, pour servir de nom DNS.
func NomPropre(s string) string {
	s = horsNom.ReplaceAllString(strings.ToLower(strings.TrimSpace(s)), "-")
	s = strings.Trim(s, "-")
	if len(s) > 40 {
		s = strings.Trim(s[:40], "-")
	}
	if s == "" {
		s = "appareil"
	}
	return s
}

// Enregistrer inscrit un appareil, ou met à jour celui qui a déjà cette clé
// publique : il garde son adresse. Un nouvel appareil reçoit la première
// adresse libre du réseau, et un nom unique.
func (b *Base) Enregistrer(a Appareil, jeton string, reseau netip.Prefix, serveur netip.Addr) (Appareil, error) {
	tx, err := b.db.Begin()
	if err != nil {
		return a, err
	}
	defer tx.Rollback()
	now := time.Now().Unix()
	var expire int64
	if !a.Expire.IsZero() {
		expire = a.Expire.Unix()
	}

	existant, err := lire(tx.QueryRow(`SELECT `+colonnes+` FROM appareils WHERE cle_publique = ?`, a.ClePublique))
	switch {
	case err == nil:
		a.ID, a.Adresse, a.Cree, a.Nom = existant.ID, existant.Adresse, existant.Cree, existant.Nom
		_, err = tx.Exec(`UPDATE appareils SET proprietaire=?, etiquette=?, systeme=?, vu=?, expire=?, jeton=? WHERE id=?`,
			a.Proprietaire, a.Etiquette, a.Systeme, now, expire, Empreinte(jeton), a.ID)
		if err != nil {
			return a, err
		}
	case errors.Is(err, ErrIntrouvable):
		if a.Adresse, err = adresseLibre(tx, reseau, serveur); err != nil {
			return a, err
		}
		if a.Nom, err = nomLibre(tx, NomPropre(a.Nom)); err != nil {
			return a, err
		}
		r, err := tx.Exec(`INSERT INTO appareils (nom, cle_publique, adresse, proprietaire, etiquette, systeme, cree, vu, expire, jeton)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			a.Nom, a.ClePublique, a.Adresse.String(), a.Proprietaire, a.Etiquette, a.Systeme, now, now, expire, Empreinte(jeton))
		if err != nil {
			return a, err
		}
		a.ID, _ = r.LastInsertId()
		a.Cree = time.Unix(now, 0)
	default:
		return a, err
	}
	a.Vu = time.Unix(now, 0)
	return a, tx.Commit()
}

func adresseLibre(tx *sql.Tx, reseau netip.Prefix, serveur netip.Addr) (netip.Addr, error) {
	prises := map[string]bool{serveur.String(): true}
	rows, err := tx.Query(`SELECT adresse FROM appareils`)
	if err != nil {
		return netip.Addr{}, err
	}
	for rows.Next() {
		var s string
		rows.Scan(&s)
		prises[s] = true
	}
	rows.Close()
	// On saute l'adresse du réseau lui-même, et on s'arrête avant la
	// diffusion.
	for a := reseau.Masked().Addr().Next(); reseau.Contains(a.Next()); a = a.Next() {
		if !prises[a.String()] {
			return a, nil
		}
	}
	return netip.Addr{}, errors.New("plus aucune adresse libre dans le réseau")
}

func nomLibre(tx *sql.Tx, nom string) (string, error) {
	candidat := nom
	for i := 2; ; i++ {
		var n int
		if err := tx.QueryRow(`SELECT COUNT(*) FROM appareils WHERE nom = ?`, candidat).Scan(&n); err != nil {
			return "", err
		}
		if n == 0 {
			return candidat, nil
		}
		candidat = fmt.Sprintf("%s-%d", nom, i)
	}
}

// CreerCle enregistre une clé d'inscription à usage unique.
func (b *Base) CreerCle(cle, etiquette, utilisateur string, expire time.Time) error {
	_, err := b.db.Exec(`INSERT INTO cles (empreinte, etiquette, utilisateur, expire) VALUES (?, ?, ?, ?)`,
		Empreinte(cle), etiquette, strings.ToLower(utilisateur), expire.Unix())
	return err
}

// UtiliserCle consomme une clé : elle ne servira qu'une fois, même si deux
// appareils la présentent au même instant.
func (b *Base) UtiliserCle(cle string) (etiquette, utilisateur string, err error) {
	var expire int64
	err = b.db.QueryRow(`DELETE FROM cles WHERE empreinte = ? RETURNING etiquette, utilisateur, expire`, Empreinte(cle)).
		Scan(&etiquette, &utilisateur, &expire)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", ErrIntrouvable
	}
	if err == nil && time.Now().Unix() > expire {
		return "", "", ErrIntrouvable
	}
	return
}
