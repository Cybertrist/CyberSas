package noise

import (
	"bytes"
	"crypto/ecdh"
	"encoding/hex"
	"testing"

	"golang.org/x/crypto/chacha20poly1305"
)

// Vecteur officiel du projet cacophony, repris par la communauté Noise
// comme référence d'interopérabilité :
// https://github.com/haskell-cryptography/cacophony/blob/master/vectors/cacophony.txt
//
// Toutes les clés sont imposées, éphémères comprises : chaque octet produit
// doit être identique à celui attendu. C'est une preuve plus forte que
// l'échange avec flynn/noise, qui pourrait partager une erreur avec nous.
var vecteurIK = struct {
	prologue, initStatique, initEphemere, respStatique, respEphemere, hachage string
	messages                                                                  [][2]string // charge, chiffré
}{
	prologue:     "4a6f686e2047616c74",
	initStatique: "e61ef9919cde45dd5f82166404bd08e38bceb5dfdfded0a34c8df7ed542214d1",
	initEphemere: "893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a",
	respStatique: "4a3acbfdb163dec651dfa3194dece676d437029c62a408b4c5ea9114246e4893",
	respEphemere: "bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b",
	hachage:      "48f3cb8bc9319da4ba1e9933991b1c4ed4034f1f126a76d3a1fbcfd7f94248d4",
	messages: [][2]string{
		{"4c756477696720766f6e204d69736573", "ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c79440b03ddc7aac5123d06a1b23b71670e32e76c28239a7ca4ac8f784de7e44c1adbfc6e83fef7352a58d9d56157400c0a737b1d171ce368229c7b752ac25b8faf4eca690f6d896f543be02c996ab2b86b76"},
		{"4d757272617920526f746862617264", "95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f144808843d9b5a8927f0ac9655ef76833bc7e5561f42e691ac8404efd6fbd6308b6a27c"},
		{"462e20412e20486179656b", "2c256ed08fcd08c2980f954ee4beaccb61c9581340f5dd2fd1cf3b"},
		{"4361726c204d656e676572", "d6033f70eee20945c7c9dba304e397ee3b284ff5e00fd9efb095d3"},
		{"4a65616e2d426170746973746520536179", "a9c068ca5d8babf72560652d8e851adbfac35c8a66e810d560863173e96adf4cfe"},
		{"457567656e2042f6686d20766f6e2042617765726b", "2a09d8f459e5927e40fdd2eddc99bdafb04e13a26f145cb5cfe9e6ba34c94331ebc17d5156"},
	},
}

func hx(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func cle(t *testing.T, s string) *ecdh.PrivateKey {
	k, err := ClePrivee(hx(t, s))
	if err != nil {
		t.Fatal(err)
	}
	return k
}

func TestVecteurOfficielIK(t *testing.T) {
	v := vecteurIK
	prologue := hx(t, v.prologue)
	respStatique := cle(t, v.respStatique)

	ini := NouvelInitiateur(cle(t, v.initStatique), respStatique.PublicKey().Bytes(), prologue)
	ini.e = cle(t, v.initEphemere)
	rep := NouveauRepondeur(respStatique, prologue)
	rep.e = cle(t, v.respEphemere)

	// Message 1, de l'initiateur.
	m1, err := ini.Message1(hx(t, v.messages[0][0]))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(m1, hx(t, v.messages[0][1])) {
		t.Fatalf("message 1 différent du vecteur officiel\nobtenu  %x\nattendu %s", m1, v.messages[0][1])
	}
	_, charge, err := rep.LireMessage1(m1)
	if err != nil || !bytes.Equal(charge, hx(t, v.messages[0][0])) {
		t.Fatalf("le répondeur lit mal le message 1 officiel : %v", err)
	}

	// Message 2, du répondeur.
	m2, clesRep, err := rep.Message2(hx(t, v.messages[1][0]))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(m2, hx(t, v.messages[1][1])) {
		t.Fatalf("message 2 différent du vecteur officiel\nobtenu  %x\nattendu %s", m2, v.messages[1][1])
	}
	charge, clesIni, err := ini.LireMessage2(m2)
	if err != nil || !bytes.Equal(charge, hx(t, v.messages[1][0])) {
		t.Fatalf("l'initiateur lit mal le message 2 officiel : %v", err)
	}

	for _, h := range [][32]byte{ini.HachagePoignee(), rep.HachagePoignee()} {
		if hex.EncodeToString(h[:]) != v.hachage {
			t.Fatalf("hachage de fin de poignée de main : %x, attendu %s", h, v.hachage)
		}
	}

	// Messages de transport : les pairs impairs vont de l'initiateur au
	// répondeur, les autres en sens inverse, chaque sens avec son compteur.
	versRep, _ := chacha20poly1305.New(clesIni.Envoi[:])
	versIni, _ := chacha20poly1305.New(clesRep.Envoi[:])
	for i, m := range v.messages[2:] {
		aead := versRep
		if i%2 == 1 {
			aead = versIni
		}
		c := aead.Seal(nil, Nonce(uint64(i/2)), hx(t, m[0]), nil)
		if !bytes.Equal(c, hx(t, m[1])) {
			t.Fatalf("message de transport %d différent du vecteur officiel", i+3)
		}
	}
	if clesIni.Reception != clesRep.Envoi || clesRep.Reception != clesIni.Envoi {
		t.Fatal("les clés des deux côtés ne se correspondent pas")
	}
}
