package serveur

import (
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/netip"
	"strings"
	"time"

	"github.com/Cybertrist/CyberSas/internal/base"
	"github.com/Cybertrist/CyberSas/internal/politique"
	"github.com/Cybertrist/CyberSas/internal/protocole"
	"github.com/Cybertrist/CyberSas/internal/verrou"
)

func (s *Serveur) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST "+protocole.CheminConnexion, s.connexion)
	mux.HandleFunc("GET "+protocole.CheminReseau, s.reseau)
	mux.HandleFunc("POST "+protocole.CheminDeconnexion, s.deconnexion)
	mux.HandleFunc("GET "+protocole.CheminServeur, func(w http.ResponseWriter, _ *http.Request) {
		repondre(w, http.StatusOK, s.infoServeur())
	})
	mux.HandleFunc("GET "+protocole.CheminSante, func(w http.ResponseWriter, _ *http.Request) {
		repondre(w, http.StatusOK, map[string]string{"etat": "ok"})
	})
	return mux
}

func (s *Serveur) infoServeur() protocole.Serveur {
	return protocole.Serveur{ClePublique: s.publique, Point: s.cfg.Point, Adresse: s.cfg.Serveur.String()}
}

func repondre(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func refuser(w http.ResponseWriter, code int, message string) {
	repondre(w, code, protocole.Erreur{Erreur: message})
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
	// D'abord la preuve de possession : elle ne coûte rien, et sans elle on
	// ne consomme ni jeton Google ni clé d'inscription.
	if !protocole.VerifierPreuve(s.prive, cle, d.Horodatage, d.Preuve, time.Now()) {
		journal.Warn("preuve de possession invalide")
		refuser(w, http.StatusUnauthorized, "preuve de possession de la clé invalide (horloge décalée ?)")
		return
	}

	a := base.Appareil{Nom: d.Nom, ClePublique: d.ClePublique, Systeme: d.Systeme}
	switch {
	case d.JetonGoogle != "" && d.CleInscription != "":
		refuser(w, http.StatusBadRequest, "un seul justificatif à la fois")
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
	if errors.Is(err, base.ErrAutreProprietaire) {
		journal.Warn("tentative de reprise d'une clé inscrite", "proprietaire", a.Proprietaire, "etiquette", a.Etiquette)
		refuser(w, http.StatusConflict, err.Error())
		return
	}
	if err != nil {
		journal.Error("inscription impossible", "erreur", err)
		refuser(w, http.StatusInternalServerError, "inscription impossible")
		return
	}
	if err := s.Synchroniser(); err != nil {
		journal.Error("synchronisation", "erreur", err)
	}
	journal.Info("appareil inscrit", "nom", a.Nom, "adresse", a.Adresse, "proprietaire", a.Proprietaire, "etiquette", a.Etiquette)
	_, texteVerrou := s.verrou()
	repondre(w, http.StatusOK, protocole.ReponseConnexion{
		Appareil: s.vers(a, true, time.Time{}),
		Reseau:   s.cfg.Reseau.String(),
		DNS:      s.cfg.Serveur.String(),
		Domaine:  "sas.internal",
		Serveur:  s.infoServeur(),
		Verrou:   texteVerrou,
		Jeton:    jeton,
	})
}

func (s *Serveur) vers(a base.Appareil, moi bool, poignee time.Time) protocole.Appareil {
	r := protocole.Appareil{Numero: uint32(a.ID), Nom: a.Nom, Adresse: a.Adresse.String(), ClePublique: a.ClePublique,
		Proprietaire: a.Proprietaire, Etiquette: a.Etiquette, Systeme: a.Systeme, Moi: moi, Expire: a.Expire,
		EnLigne: !poignee.IsZero() && time.Since(poignee) < 3*time.Minute}
	if len(a.Signature) > 0 {
		r.Signature = base64.StdEncoding.EncodeToString(a.Signature)
	}
	return r
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

// reseau : ce qu'un appareil doit savoir pour configurer son tunnel. Ses
// pairs sont les seuls appareils avec qui la politique le relie ; les
// autres n'existent pas pour lui.
func (s *Serveur) reseau(w http.ResponseWriter, r *http.Request) {
	moi, ok := s.authentifier(w, r)
	if !ok {
		return
	}
	s.mu.Lock()
	flux := s.flux
	s.mu.Unlock()
	relies := map[netip.Addr]bool{}
	for paire := range politique.Relations(flux, s.cfg.Serveur) {
		if paire[0] == moi.Adresse {
			relies[paire[1]] = true
		}
	}
	poignees := map[string]time.Time{}
	for _, e := range s.moteur.Etat() {
		poignees[base64.StdEncoding.EncodeToString(e.Publique[:])] = e.DernierePoignee
	}
	tous, err := s.base.Appareils()
	if err != nil {
		refuser(w, http.StatusInternalServerError, "base indisponible")
		return
	}
	_, texteVerrou := s.verrou()
	etat := protocole.EtatReseau{Serveur: s.infoServeur(), Verrou: texteVerrou, Pairs: []protocole.Appareil{}, Entrant: []protocole.RegleEntrante{}}
	for _, a := range tous {
		switch {
		case a.ID == moi.ID:
			etat.Moi = s.vers(a, true, poignees[a.ClePublique])
		case relies[a.Adresse]:
			etat.Pairs = append(etat.Pairs, s.vers(a, false, poignees[a.ClePublique]))
		}
	}
	for _, e := range politique.Entrant(flux, moi.Adresse) {
		var ports []string
		for _, p := range e.Ports {
			ports = append(ports, p.String())
		}
		etat.Entrant = append(etat.Entrant, protocole.RegleEntrante{Sources: []string{e.Source.String()}, Ports: ports})
	}
	repondre(w, http.StatusOK, etat)
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

// ImporterSignatures enregistre des signatures du verrou, après avoir
// vérifié chacune avec la clé publique du verrou. Une signature fausse est
// refusée : la clé privée du verrou n'est jamais passée par le serveur, il
// ne peut que transmettre ce que l'admin a signé.
func ImporterSignatures(b *base.Base, cleVerrou ed25519.PublicKey, liste []protocole.Appareil) (acceptees int, refusees []string) {
	for _, a := range liste {
		cle, err1 := base64.StdEncoding.DecodeString(a.ClePublique)
		sig, err2 := base64.StdEncoding.DecodeString(a.Signature)
		adresse, err3 := netip.ParseAddr(a.Adresse)
		if err1 != nil || err2 != nil || err3 != nil || len(cle) != 32 {
			refusees = append(refusees, a.Nom)
			continue
		}
		var pub [32]byte
		copy(pub[:], cle)
		if !verrou.Verifier(cleVerrou, pub, adresse, sig) || b.DefinirSignature(a.ClePublique, adresse, sig) != nil {
			refusees = append(refusees, a.Nom)
			continue
		}
		acceptees++
	}
	return
}
