package pont

import (
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/Cybertrist/CyberSas/internal/appareil"
	"github.com/Cybertrist/CyberSas/internal/client"
	"github.com/Cybertrist/CyberSas/internal/protocole"
)

func lireVue(t *testing.T, s string) Vue {
	t.Helper()
	var v Vue
	if err := json.Unmarshal([]byte(s), &v); err != nil {
		t.Fatalf("JSON illisible : %v\n%s", err, s)
	}
	return v
}

// Sans rien : une vue vide mais valide, jamais « null ».
func TestVueVide(t *testing.T) {
	v := lireVue(t, vueJSON(appareil.Vue{}, false, "", time.Now()))
	if v.EnMarche || v.Connecte || v.Pairs == nil || len(v.Pairs) != 0 {
		t.Errorf("vue vide inattendue : %+v", v)
	}
}

// Le serveur passe en tête, cet appareil est marqué, et un pair écarté par
// le client est « non signé » avec sa raison. Sans moteur, personne n'a de
// session.
func TestVueReseau(t *testing.T) {
	cle := "zKaLpkfwgqY3dEfBoAqXd+bsVVrXxGkRCq13XRRO/EY="
	r := protocole.EtatReseau{
		Serveur: protocole.Serveur{ClePublique: cle, Adresse: "10.77.0.1"},
		Moi:     protocole.Appareil{Nom: "fold8-tristan", Adresse: "10.77.0.18"},
		Pairs: []protocole.Appareil{
			{Nom: "maison", Adresse: "10.77.0.2", Etiquette: "maison", EnLigne: true},
			{Nom: "intrus", Adresse: "10.77.0.9"},
		},
	}
	vue := appareil.Vue{Reseau: r, Ecartes: []client.Ecarte{{Nom: "intrus", Adresse: "10.77.0.9", Raison: "pas signé par le verrou"}}}
	v := lireVue(t, vueJSON(vue, true, "", time.Now()))
	if !v.EnMarche || v.Connecte {
		t.Errorf("en marche %v, connecté %v", v.EnMarche, v.Connecte)
	}
	if len(v.Pairs) != 4 || !v.Pairs[0].Serveur || !v.Pairs[1].Moi {
		t.Fatalf("ordre inattendu : %+v", v.Pairs)
	}
	for _, p := range v.Pairs {
		switch p.Nom {
		case "maison":
			if !p.Signe || !p.EnLigne {
				t.Errorf("maison : %+v", p)
			}
		case "intrus":
			if p.Signe || p.Raison == "" {
				t.Errorf("intrus accepté : %+v", p)
			}
		}
		if p.Session {
			t.Errorf("%s a une session sans moteur", p.Nom)
		}
	}
}

// Une erreur de synchronisation remonte, texte nettoyé.
func TestVueErreur(t *testing.T) {
	v := lireVue(t, vueJSON(appareil.Vue{Erreur: errors.New("serveur\x1b[31m injoignable")}, true, "", time.Now()))
	if v.Erreur != "serveur?[31m injoignable" {
		t.Errorf("erreur : %q", v.Erreur)
	}
}
