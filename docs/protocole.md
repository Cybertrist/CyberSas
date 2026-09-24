# Le protocole du tunnel CyberSas

Tout ce qui se passe entre un appareil et le serveur, octet par octet. Le code
est dans [`internal/noise`](../internal/noise) et [`internal/tunnel`](../internal/tunnel).

## Ce qui est à nous, ce qui ne l'est pas

Les primitives cryptographiques viennent de la bibliothèque standard de Go et
de `golang.org/x/crypto` :

- **X25519** pour l'échange de clés ;
- **ChaCha20-Poly1305** pour le chiffrement authentifié ;
- **BLAKE2s** pour le hachage et la dérivation de clés.

On n'écrit jamais ses propres primitives. Tout le reste est écrit ici :
l'assemblage de la poignée de main, le format des messages, les sessions, la
protection contre le rejeu, les minuteries et l'itinérance.

L'architecture suit celle de WireGuard, qui a fait ses preuves : une poignée
de main Noise IK, des sessions courtes et des compteurs en guise de nonces.
Mais le code est le nôtre, et il n'est **pas compatible** avec WireGuard :
le prologue et le format des messages diffèrent.

## La poignée de main : Noise IK

`Noise_IK_25519_ChaChaPoly_BLAKE2s`, écrit d'après la [spécification
Noise](https://noiseprotocol.org/noise.html), révision 34.

Le client connaît d'avance la clé publique du serveur (le **K** de IK) : l'API
la lui a donnée à l'inscription. Il envoie la sienne, chiffrée, dans le premier
message (le **I**). Un seul aller-retour établit deux clés de session, une par
sens.

```
prologue = "CyberSas tunnel v1"

client -> serveur : e, es, s, ss, horodatage chiffré
serveur -> client : e, ee, se, charge vide chiffrée
```

Les tests confrontent cette implémentation à [flynn/noise](https://github.com/flynn/noise),
une implémentation indépendante : chacune lit les messages de l'autre, et les
clés de session tombent d'accord dans les deux sens. Un octet modifié n'importe
où dans le premier message le fait refuser.

## Les messages

Tous commencent par un octet de type et trois octets réservés, à zéro. Les
entiers sont en petit-boutiste.

**Initiation** (type 1, 116 octets), du client vers le serveur :

```
type (1) | réservé (3) | indice du client (4) | message Noise 1 (108)
```

**Réponse** (type 2, 60 octets), du serveur vers le client :

```
type (1) | réservé (3) | indice du serveur (4) | indice du client (4) | message Noise 2 (48)
```

**Données** (type 3), dans les deux sens :

```
type (1) | réservé (3) | indice du destinataire (4) | compteur (8) | paquet IP chiffré + tag (16)
```

Les indices sont tirés au hasard par chaque côté. Ils permettent de retrouver la
session d'un paquet sans rien révéler de l'identité de l'appareil.

## Les sessions

- Le compteur d'un paquet de données sert de nonce ChaCha20-Poly1305 : quatre
  octets nuls, puis le compteur sur huit octets.
- Le clair est complété par des zéros jusqu'à un multiple de 16 octets. La
  longueur réelle du paquet est lue dans son en-tête IP.
- Un paquet de données vide est un **maintien** : il garde la session ouverte
  et la traduction d'adresse de la box.
- Le client renouvelle sa session toutes les **deux minutes**. Une session de
  plus de **trois minutes** ne chiffre et ne déchiffre plus rien.
- Le serveur n'utilise une nouvelle session qu'après avoir reçu un premier
  paquet de données chiffré avec elle. C'est la preuve que le client détient les
  mêmes clés.

## Ce que le protocole refuse

- **Un paquet rejoué.** Chaque session garde une fenêtre des 2 048 derniers
  compteurs. Un compteur déjà vu, ou plus ancien que la fenêtre, est rejeté. Le
  compteur n'est marqué qu'après la vérification du tag : un paquet forgé ne
  peut pas faire avancer la fenêtre.
- **Une initiation rejouée.** Son horodatage TAI64N doit être plus récent que
  la dernière initiation acceptée de cet appareil. Sinon, le serveur ne répond
  pas.
- **Une clé inconnue.** Le serveur déchiffre la clé statique du client dans le
  premier message. Si elle n'est pas inscrite, il ne répond pas.
- **Une adresse usurpée.** Un paquet ne sort du tunnel que si son adresse source
  est celle de l'appareil qui l'a chiffré. Être dans le VPN ne permet pas de se
  faire passer pour un autre appareil.
- **Une clé publique faible.** L'API refuse à l'inscription les points de petit
  ordre de X25519, comme la clé nulle.

## Itinérance et reprise

- Le serveur suit un appareil qui change de réseau, par exemple du Wi-Fi à la
  4G. Seul un paquet authentifié, et jamais vu, peut déplacer son adresse.
- Si le client envoie des données et ne reçoit rien pendant **15 secondes**, il
  rouvre une session sans attendre. C'est ce qui le fait revenir seul quand le
  serveur redémarre.
- Le serveur répond à un maintien s'il n'a rien envoyé depuis **10 secondes**.
  Le client sait ainsi que la liaison vit, même quand personne ne parle.
- Le client redemande l'adresse du serveur toutes les 30 secondes : un
  changement d'IP ne le perd pas.

## Ce qui manque encore

- **Pas de protection contre l'inondation de poignées de main.** WireGuard
  répond par un cookie quand il est sous charge, pour forcer l'attaquant à
  prouver son adresse avant tout calcul coûteux. Ici, chaque initiation coûte
  deux échanges X25519 au serveur.
- **IPv4 seulement** dans le tunnel.
- **Aucun audit externe.** Les tests prouvent que la poignée de main suit la
  spécification et que les attaques connues sont refusées. Ils ne remplacent
  pas le regard d'un cryptographe.
