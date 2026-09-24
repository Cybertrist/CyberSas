package serveur

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/Cybertrist/CyberSas/internal/base"
	"github.com/Cybertrist/CyberSas/internal/politique"
	"github.com/Cybertrist/CyberSas/internal/protocole"
)

func (s *Serveur) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST "+protocole.CheminConnexion, s.connexion)
	mux.HandleFunc("GET "+protocole.CheminAppareils, s.appareils)
	mux.HandleFunc("POST "+protocole.CheminDeconnexion, s.deconnexion)
	mux.HandleFunc("GET "+protocole.CheminSante, func(w http.ResponseWriter, _ *http.Request) {
		repondre(w, http.StatusOK, map[string]string{"etat": "ok"})
	})
	return mux
}

func repondre(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

// clePubliqueValide écarte les points de petit ordre de X25519, comme la
// clé nulle : avec eux, le secret partagé ne dépend plus de notre clé.
// L'essai d'un échange avec une clé jetable suffit à les reconnaître,
// crypto/ecdh refusant tout secret nul.
func clePubliqueValide(b []byte) bool {
	pub, err := ecdh.X25519().NewPublicKey(b)
	if err != nil {
		return false
	}
	jetable, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return false
	}
	_, err = jetable.ECDH(pub)
	return err == nil
}

func refuser(w http.ResponseWriter, code int, message string) {
	repondre(w, code, protocole.Erreur{Erreur: message})
}

// ip : Nginx a remplacé X-Real-IP par l'adresse qu'il a vue.
func ip(r *http.Request) string {
	if v := r.Header.Get("X-Real-IP"); v != "" {
		return v
	}
	return r.RemoteAddr
}

func (s *Serveur) connexion(w http.ResponseWriter, r *http.Request) {
	var d protocole.DemandeConnexion
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&d); err != nil {
		refuser(w, http.StatusBadRequest, "demande illisible")
		return
	}
	cle, err := base64.StdEncoding.DecodeString(d.ClePublique)
	if err != nil || len(cle) != 32 || !clePubliqueValide(cle) {
		refuser(w, http.StatusBadRequest, "clé publique invalide")
		return
	}
	journal := s.journal.With("evenement", "connexion", "ip", ip(r), "appareil", d.Nom)

	a := base.Appareil{Nom: d.Nom, ClePublique: d.ClePublique, Systeme: d.Systeme}
	switch {
	case d.JetonGoogle != "" && d.CleInscription != "":
		refuser(w, http.StatusBadRequest, "une seule preuve à la fois")
		return
	case d.JetonGoogle != "":
		email, err := s.verifierGoogle(r.Context(), d.JetonGoogle)
		if err != nil {
			journal.Warn("jeton Google refusé", "erreur", err)
			refuser(w, http.StatusUnauthorized, "connexion Google refusée")
			return
		}
		if s.chargerEquipe()[email] == "" {
			journal.Warn("adresse hors de l'équipe", "email", email)
			refuser(w, http.StatusForbidden, "ce compte Google n'a pas accès à ce réseau")
			return
		}
		a.Proprietaire = email
		a.Expire = time.Now().Add(s.cfg.DureeAppareil)
	case d.CleInscription != "":
		etiquette, utilisateur, err := s.base.UtiliserCle(d.CleInscription)
		if err != nil {
			journal.Warn("clé d'inscription refusée")
			refuser(w, http.StatusUnauthorized, "clé d'inscription inconnue, déjà utilisée ou expirée")
			return
		}
		a.Etiquette, a.Proprietaire = etiquette, utilisateur
		if utilisateur != "" {
			if s.chargerEquipe()[utilisateur] == "" {
				refuser(w, http.StatusForbidden, "cet utilisateur n'a pas accès à ce réseau")
				return
			}
			a.Expire = time.Now().Add(s.cfg.DureeAppareil)
		}
	default:
		refuser(w, http.StatusBadRequest, "il faut un jeton Google ou une clé d'inscription")
		return
	}

	jeton := jetonAleatoire()
	a, err = s.base.Enregistrer(a, jeton, s.cfg.Reseau, s.cfg.Serveur)
	if err != nil {
		journal.Error("inscription impossible", "erreur", err)
		refuser(w, http.StatusInternalServerError, "inscription impossible")
		return
	}
	if err := s.Synchroniser(); err != nil {
		journal.Error("synchronisation", "erreur", err)
	}
	journal.Info("appareil inscrit", "nom", a.Nom, "adresse", a.Adresse, "proprietaire", a.Proprietaire, "etiquette", a.Etiquette)
	repondre(w, http.StatusOK, protocole.ReponseConnexion{
		Appareil: s.vers(a, true, time.Time{}),
		Reseau:   s.cfg.Reseau.String(),
		DNS:      s.cfg.Serveur.String(),
		Domaine:  "sas.internal",
		Serveur:  protocole.Serveur{ClePublique: s.publique, Point: s.cfg.Point},
		Jeton:    jeton,
	})
}

func (s *Serveur) vers(a base.Appareil, moi bool, poignee time.Time) protocole.Appareil {
	return protocole.Appareil{Nom: a.Nom, Adresse: a.Adresse.String(), Proprietaire: a.Proprietaire,
		Etiquette: a.Etiquette, Systeme: a.Systeme, Moi: moi, Expire: a.Expire,
		EnLigne: !poignee.IsZero() && time.Since(poignee) < 3*time.Minute}
}

func (s *Serveur) authentifier(w http.ResponseWriter, r *http.Request) (base.Appareil, bool) {
	jeton, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || jeton == "" {
		refuser(w, http.StatusUnauthorized, "jeton manquant")
		return base.Appareil{}, false
	}
	a, err := s.base.ParJeton(jeton)
	if errors.Is(err, base.ErrIntrouvable) {
		refuser(w, http.StatusUnauthorized, "appareil inconnu : il faut se reconnecter")
		return a, false
	}
	if err != nil {
		refuser(w, http.StatusInternalServerError, "base indisponible")
		return a, false
	}
	return a, true
}

// appareils : ceux que l'appareil qui demande peut joindre, et lui-même.
// Les autres n'existent pas pour lui.
func (s *Serveur) appareils(w http.ResponseWriter, r *http.Request) {
	moi, ok := s.authentifier(w, r)
	if !ok {
		return
	}
	s.mu.Lock()
	joignables := politique.Joignables(s.flux, moi.Adresse)
	s.mu.Unlock()
	poignees := map[string]time.Time{}
	for _, e := range s.moteur.Etat() {
		poignees[base64.StdEncoding.EncodeToString(e.Publique[:])] = e.DernierePoignee
	}
	tous, err := s.base.Appareils()
	if err != nil {
		refuser(w, http.StatusInternalServerError, "base indisponible")
		return
	}
	liste := []protocole.Appareil{}
	for _, a := range tous {
		if a.ID == moi.ID || joignables[a.Adresse] {
			liste = append(liste, s.vers(a, a.ID == moi.ID, poignees[a.ClePublique]))
		}
	}
	repondre(w, http.StatusOK, liste)
}

func (s *Serveur) deconnexion(w http.ResponseWriter, r *http.Request) {
	moi, ok := s.authentifier(w, r)
	if !ok {
		return
	}
	s.base.Supprimer(moi.ID)
	s.Synchroniser()
	s.journal.Info("appareil déconnecté", "evenement", "deconnexion", "appareil", moi.Nom, "ip", ip(r))
	repondre(w, http.StatusOK, map[string]string{"etat": "déconnecté"})
}
