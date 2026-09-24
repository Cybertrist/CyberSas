// Package protocole décrit ce que l'appli et le serveur s'échangent sur
// l'API HTTPS : se connecter, lister les appareils, se déconnecter.
//
// L'API ne transporte jamais de clé privée. L'appareil génère sa paire de
// clés lui-même et n'envoie que la moitié publique.
package protocole

import "time"

const (
	CheminConnexion   = "/api/v1/connexion"
	CheminAppareils   = "/api/v1/appareils"
	CheminDeconnexion = "/api/v1/deconnexion"
	CheminSante       = "/api/v1/sante"
)

// DemandeConnexion : l'une des deux preuves, jamais les deux. Un jeton
// Google pour une personne, une clé d'inscription pour une machine.
type DemandeConnexion struct {
	JetonGoogle    string `json:"jeton_google,omitempty"`
	CleInscription string `json:"cle_inscription,omitempty"`
	ClePublique    string `json:"cle_publique"`
	Nom            string `json:"nom"`
	Systeme        string `json:"systeme"`
}

type Serveur struct {
	ClePublique string `json:"cle_publique"`
	Point       string `json:"point"` // hôte:port UDP du tunnel
}

type ReponseConnexion struct {
	Appareil Appareil `json:"appareil"`
	Reseau   string   `json:"reseau"`  // 10.77.0.0/24
	DNS      string   `json:"dns"`     // le résolveur du VPN
	Domaine  string   `json:"domaine"` // sas.internal
	Serveur  Serveur  `json:"serveur"`
	// Jeton : à présenter ensuite à l'API. Il n'ouvre pas le tunnel, qui ne
	// se fie qu'aux clés.
	Jeton string `json:"jeton"`
}

type Appareil struct {
	Nom          string    `json:"nom"`
	Adresse      string    `json:"adresse"`
	Proprietaire string    `json:"proprietaire,omitempty"`
	Etiquette    string    `json:"etiquette,omitempty"`
	Systeme      string    `json:"systeme,omitempty"`
	EnLigne      bool      `json:"en_ligne"`
	Moi          bool      `json:"moi,omitempty"`
	Expire       time.Time `json:"expire,omitzero"`
}

type Erreur struct {
	Erreur string `json:"erreur"`
}
