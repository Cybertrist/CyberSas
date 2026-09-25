package serveur

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/Cybertrist/CyberSas/internal/base"
	"github.com/Cybertrist/CyberSas/internal/protocole"
)

// Les routes qui servent l'appli au-delà du tunnel : le nom affiché de son
// appareil, et, pour les admins, la gestion des demandes.
//
// Rien ici ne donne au serveur un pouvoir de plus : il ne signe jamais. Les
// certificats viennent du téléphone de l'admin, et sont vérifiés avec la
// clé publique du verrou comme ceux qu'importe « sasd signatures ». Un
// serveur piraté peut refuser ou retirer un appareil (il le pouvait déjà),
// pas en faire entrer un.

// longueurLibelle : un nom affiché, pas un roman.
const longueurLibelle = 40

// estAdmin : la personne est dans le groupe « admins » de l'équipe.
func (s *Serveur) estAdmin(a base.Appareil) bool {
	return a.Proprietaire != "" && s.chargerEquipe()[a.Proprietaire] == "admins"
}

// libelle change le nom affiché de son appareil ; un admin, de n'importe
// lequel.
func (s *Serveur) libelle(w http.ResponseWriter, r *http.Request) {
	moi, ok := s.authentifier(w, r)
	if !ok {
		return
	}
	var d protocole.DemandeLibelle
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&d); err != nil {
		refuser(w, http.StatusBadRequest, "demande illisible")
		return
	}
	libelle := texteCourt(d.Libelle, longueurLibelle)
	if libelle == "" {
		refuser(w, http.StatusBadRequest, "le nom est vide")
		return
	}
	cible := moi
	if d.ClePublique != "" && d.ClePublique != moi.ClePublique {
		if !s.estAdmin(moi) {
			refuser(w, http.StatusForbidden, "seul un admin renomme les appareils des autres")
			return
		}
		var err error
		if cible, err = s.base.ParCle(d.ClePublique); err != nil {
			refuser(w, http.StatusNotFound, "appareil inconnu")
			return
		}
	}
	if err := s.base.DefinirLibelle(cible.ID, libelle); err != nil {
		s.journal.Error("renommage impossible", "evenement", "libelle", "appareil", cible.Nom, "erreur", err)
		refuser(w, http.StatusInternalServerError, "renommage impossible")
		return
	}
	s.journal.Info("appareil renommé", "evenement", "libelle", "appareil", cible.Nom, "libelle", libelle, "par", moi.Nom)
	repondre(w, http.StatusOK, map[string]string{"libelle": libelle})
}

// admin : l'appareil qui appelle, s'il appartient à un admin.
func (s *Serveur) admin(w http.ResponseWriter, r *http.Request) (base.Appareil, bool) {
	moi, ok := s.authentifier(w, r)
	if !ok {
		return moi, false
	}
	if !s.estAdmin(moi) {
		refuser(w, http.StatusForbidden, "réservé aux admins")
		return moi, false
	}
	return moi, true
}

// appareils : tous les appareils, signés ou non, comme « sasd appareils
// --json ». Le groupe est celui de l'équipe aujourd'hui : c'est lui que
// l'admin signera, et qu'il voit avant de signer.
func (s *Serveur) appareils(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.admin(w, r); !ok {
		return
	}
	liste, err := s.base.Appareils()
	if err != nil {
		refuser(w, http.StatusInternalServerError, "base indisponible")
		return
	}
	equipe := s.chargerEquipe()
	r2 := []protocole.Appareil{}
	for _, a := range liste {
		// #nosec G115 -- a.ID est borné par base.Enregistrer.
		p := protocole.Appareil{Numero: uint32(a.ID), Nom: a.Nom, Libelle: a.Libelle, Adresse: a.Adresse.String(),
			ClePublique: a.ClePublique, Proprietaire: a.Proprietaire, Etiquette: a.Etiquette, Systeme: a.Systeme,
			Groupe: equipe[a.Proprietaire], SignatureExpire: a.SignatureExpire}
		if len(a.Signature) > 0 {
			p.Signature = base64.StdEncoding.EncodeToString(a.Signature)
		}
		r2 = append(r2, p)
	}
	repondre(w, http.StatusOK, r2)
}

// signatures : les certificats signés sur le téléphone de l'admin. Chacun
// est vérifié avec la clé publique du verrou ; un seul faux, et on le dit.
func (s *Serveur) signatures(w http.ResponseWriter, r *http.Request) {
	moi, ok := s.admin(w, r)
	if !ok {
		return
	}
	cle, _ := s.verrou()
	if cle == nil {
		refuser(w, http.StatusConflict, "ce réseau n'a pas de verrou")
		return
	}
	var liste []protocole.Appareil
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 256<<10)).Decode(&liste); err != nil {
		refuser(w, http.StatusBadRequest, "demande illisible")
		return
	}
	acceptes, refuses := ImporterCertificats(s.base, cle, liste)
	s.journal.Info("certificats importés", "evenement", "signature", "par", moi.Nom, "acceptes", acceptes, "refuses", len(refuses))
	if err := s.Synchroniser(); err != nil {
		s.journal.Error("synchronisation après signature", "evenement", "synchronisation", "erreur", err)
	}
	if len(refuses) > 0 {
		refuser(w, http.StatusBadRequest, "certificat refusé (signature fausse ou fiche changée)")
		return
	}
	repondre(w, http.StatusOK, map[string]int{"acceptes": acceptes})
}

// retrait : un admin retire un appareil (une demande refusée, un appareil
// dont on ne veut plus). Pour un appareil volé, il faut aussi le révoquer
// avec le verrou : retiré seulement, il pourrait se réinscrire.
func (s *Serveur) retrait(w http.ResponseWriter, r *http.Request) {
	moi, ok := s.admin(w, r)
	if !ok {
		return
	}
	var d protocole.DemandeRetrait
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4<<10)).Decode(&d); err != nil {
		refuser(w, http.StatusBadRequest, "demande illisible")
		return
	}
	cible, err := s.base.ParCle(d.ClePublique)
	if errors.Is(err, base.ErrIntrouvable) {
		refuser(w, http.StatusNotFound, "appareil inconnu")
		return
	}
	if err != nil || cible.ID == moi.ID {
		refuser(w, http.StatusBadRequest, "retrait impossible")
		return
	}
	if err := s.base.Supprimer(cible.ID); err != nil {
		refuser(w, http.StatusInternalServerError, "retrait impossible")
		return
	}
	s.journal.Warn("appareil retiré", "evenement", "retrait", "appareil", cible.Nom, "par", moi.Nom)
	if err := s.Synchroniser(); err != nil {
		s.journal.Error("synchronisation après retrait", "evenement", "synchronisation", "erreur", err)
	}
	repondre(w, http.StatusOK, map[string]string{"etat": "retiré"})
}
