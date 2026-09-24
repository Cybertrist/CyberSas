# Le protocole CyberSas

Tout ce qui se passe entre un appareil, le serveur et les autres appareils,
octet par octet. Le code est dans [`internal/noise`](../internal/noise),
[`internal/tunnel`](../internal/tunnel), [`internal/protocole`](../internal/protocole),
[`internal/verrou`](../internal/verrou) et [`internal/client`](../internal/client).

## Ce qui est à nous, ce qui ne l'est pas

Les primitives cryptographiques viennent de la bibliothèque standard de Go et
de `golang.org/x/crypto` :

- **X25519** pour les échanges de clés ;
- **ChaCha20-Poly1305** et **XChaCha20-Poly1305** pour le chiffrement authentifié ;
- **BLAKE2s** pour le hachage, les MAC et la dérivation de clés ;
- **Ed25519** pour les signatures du verrou.

On n'écrit jamais ses propres primitives. Tout le reste est écrit ici :
l'assemblage de la poignée de main, le format des messages, les sessions, le
relais, la protection contre le rejeu et l'inondation, le filtre, le verrou.

L'architecture reprend celle de WireGuard, qui a fait ses preuves, et celle de
Tailscale pour le relais et le verrou. Mais le code est le nôtre, et il n'est
**pas compatible** avec WireGuard : le prologue et le format diffèrent.

## Vue d'ensemble

```
           session A-serveur                  session B-serveur
   A  ============================  serveur  ============================  B
      [ trame de relais vers B  ]            [ trame de relais de A    ]
      [   session A-B : chiffré ]  (relaie)  [   session A-B : chiffré ]
```

Deux couches, toutes deux des poignées de main Noise IK :

- **La couche transport** : chaque appareil a une session avec le serveur, en
  UDP direct. Elle transporte ce qui s'adresse au serveur lui-même (le DNS du
  réseau) et les trames de relais.
- **La couche de bout en bout** : chaque paire d'appareils qui a le droit de se
  parler a sa propre session. Un paquet de A vers B est chiffré avec la
  session A-B, glissé dans une trame de relais, chiffrée à son tour pour le
  serveur. Le serveur ouvre la trame, lit le numéro du destinataire, et la
  remet à B dans sa propre session. Le paquet lui-même lui reste illisible :
  il n'a pas les clés de la session A-B.

Une session de bout en bout ne s'ouvre qu'à la demande, au premier paquet.
Celle avec le serveur reste toujours ouverte : c'est par elle que les autres
appareils nous joignent.

## La poignée de main : Noise IK

`Noise_IK_25519_ChaChaPoly_BLAKE2s`, écrit d'après la [spécification
Noise](https://noiseprotocol.org/noise.html), révision 34.

L'initiateur connaît d'avance la clé publique statique de l'autre (le **K** de
IK) : le serveur la donne à l'inscription, puis dans l'état du réseau pour les
autres appareils. Il envoie la sienne, chiffrée, dans le premier message (le
**I**). Un seul aller-retour établit deux clés de session, une par sens.

```
prologue = "CyberSas tunnel v2"

initiateur -> répondeur : e, es, s, ss, horodatage TAI64N chiffré
répondeur -> initiateur : e, ee, se, charge vide chiffrée
```

**Vérifications** :

- les vecteurs de test officiels du projet Noise (cacophony), pour cette
  variante exacte : les deux messages, le hachage final et quatre messages de
  transport correspondent octet pour octet ;
- l'échange dans les deux sens avec [flynn/noise](https://github.com/flynn/noise),
  une implémentation indépendante ;
- un octet modifié n'importe où dans le premier message le fait refuser.

## Les messages

Tous commencent par un octet de type et trois octets réservés, à zéro. Les
entiers sont en petit-boutiste, sauf mention contraire.

**Initiation** (type 1, 148 octets) :

```
type (1) | réservé (3) | indice de l'émetteur (4) | Noise message 1 (108) | mac1 (16) | mac2 (16)
```

**Réponse** (type 2, 92 octets) :

```
type (1) | réservé (3) | indice de l'émetteur (4) | indice du destinataire (4) | Noise message 2 (48) | mac1 (16) | mac2 (16)
```

**Cookie** (type 4, 64 octets), du serveur, sous charge seulement :

```
type (1) | réservé (3) | indice du destinataire (4) | nonce (24) | cookie chiffré (16) + tag (16)
```

**Données** (type 3) :

```
type (1) | réservé (3) | indice du destinataire (4) | compteur (8) | clair chiffré + tag (16)
```

Le clair d'un message de données est soit un paquet IPv4 (premier octet
`0x4X`), soit une trame de relais (premier octet `0x00`), soit vide (un
maintien).

**Trame de relais**, à l'intérieur d'un message de données :

```
0x00 | réservé (1) | longueur du message (2, grand-boutiste) | numéro d'appareil (4) | message
```

Le message est une initiation, une réponse ou des données de la couche de bout
en bout. Le numéro désigne le destinataire quand la trame va au serveur, et
l'expéditeur quand elle en revient. La longueur permet d'écarter le
remplissage ajouté par la couche transport. Le serveur ne relaie que des
initiations, réponses et données : jamais un cookie, jamais une trame dans une
trame.

Les indices sont tirés au hasard par chaque côté. Ils permettent de retrouver
une session sans rien révéler de l'identité de l'appareil.

## Les sessions

- Le compteur d'un paquet de données sert de nonce ChaCha20-Poly1305 : quatre
  octets nuls, puis le compteur sur huit octets.
- Le clair est complété par des zéros jusqu'à un multiple de 16 octets. La
  longueur réelle se lit dans l'en-tête IP, ou dans celui de la trame.
- L'initiateur renouvelle sa session toutes les **deux minutes**. Une session
  de plus de **trois minutes** ne chiffre et ne déchiffre plus rien.
- Le répondeur n'utilise une nouvelle session qu'après avoir reçu un premier
  paquet de données chiffré avec elle : c'est la preuve que l'initiateur
  détient les mêmes clés.
- **MTU** de l'interface : 1 360 octets. Le pire cas, un paquet relayé, tient
  ainsi dans 1 500 octets même sur IPv6.

## Ce que le tunnel refuse

- **Un paquet rejoué.** Chaque session garde une fenêtre des 2 048 derniers
  compteurs. Un compteur déjà vu, ou plus ancien que la fenêtre, est rejeté. Le
  compteur n'est marqué qu'après vérification du tag : un paquet forgé ne peut
  pas faire avancer la fenêtre.
- **Une initiation rejouée.** Son horodatage doit être plus récent que la
  dernière initiation acceptée de ce pair.
- **Une clé inconnue.** Le répondeur déchiffre la clé statique de l'initiateur
  dans le premier message. Si elle n'est pas dans sa liste de pairs, il ne
  répond pas.
- **Un message venu par le mauvais chemin.** Un message relayé doit venir d'un
  pair joint par relais, sous le numéro que le serveur annonce pour lui ; un
  message direct, d'un pair qui n'est pas joint par relais. Le serveur ne peut
  donc pas faire passer un appareil pour un autre : la clé de la session ne
  correspondrait pas.
- **Une adresse usurpée.** Un paquet ne sort du tunnel que si son adresse
  source est celle du pair qui l'a chiffré.
- **Ce que le filtre n'autorise pas.** Voir plus bas.

## Protection contre l'inondation : mac1, mac2, cookie

Repris de WireGuard. Une poignée de main coûte deux échanges X25519.

- **mac1** : un MAC BLAKE2s de 16 octets sur le message, avec une clé tirée de
  la clé publique du destinataire. Un message sans mac1 valide est jeté pour
  le prix d'un hachage. Or la clé publique du serveur n'est donnée qu'aux
  appareils inscrits.
- **Sous charge** (plus de 200 poignées de main par seconde), le serveur exige
  aussi un **mac2** valide, calculé avec un cookie. Sinon, il répond par un
  message cookie : un MAC de l'adresse IP et du port de l'expéditeur, sous un
  secret renouvelé toutes les deux minutes, chiffré en XChaCha20-Poly1305 avec
  le mac1 reçu en données associées. Seul celui qui reçoit vraiment les paquets
  envoyés à son adresse peut s'en servir.
- Une adresse qui a prouvé la possession de son IP garde droit à dix poignées
  de main par seconde, pas plus.

## Le filtre, chez celui qui reçoit

Le serveur ne voit plus les paquets entre appareils : il ne peut plus appliquer
les règles d'accès. C'est donc l'appareil qui reçoit qui filtre, avec les
règles que le serveur lui transmet dans l'état du réseau.

- Ce qu'un appareil envoie n'est jamais filtré.
- Ce qui entre doit correspondre à une règle pour ce pair (protocole et port de
  destination), ou répondre à un flux que l'appareil a lui-même ouvert : le
  suivi des connexions retient chaque flux sortant, cinq minutes en TCP, une en
  UDP, trente secondes en ICMP.
- Un fragment qui n'est pas le premier n'a pas d'en-tête de transport : il ne
  passe qu'avec une règle « tout ».

Un appareil malveillant ne peut rien y changer : il ne contrôle que ce qu'il
envoie, pas ce que les autres acceptent.

En plus du filtre, le serveur ne relaie qu'entre deux appareils que la
politique relie, dans un sens au moins. Deux appareils sans relation ne peuvent
même pas se faire une poignée de main.

## L'inscription et sa preuve de possession

1. L'appareil tire sa paire de clés X25519. La clé privée ne le quitte jamais.
2. Il demande la clé publique du serveur (`GET /api/v1/serveur`).
3. Il calcule une **preuve de possession** : un HMAC-BLAKE2s, avec pour clé le
   secret X25519 entre sa clé et celle du serveur, sur un contexte, les deux
   clés publiques et l'horodatage de la demande. Seul le détenteur de la clé
   privée peut le produire. Le serveur refuse une preuve fausse, ou vieille de
   plus de cinq minutes.
4. Il envoie la preuve avec un justificatif : un jeton d'identité Google, ou
   une clé d'inscription à usage unique donnée par l'admin.
5. Le serveur vérifie le jeton auprès de Google (signature, émetteur,
   expiration, destinataire, adresse vérifiée), puis que l'adresse figure dans
   la liste de l'équipe. Il attribue une adresse `10.77.0.x` et un numéro.

Une clé déjà inscrite ne change jamais de propriétaire ni d'étiquette : même
avec la clé privée, on ne fait pas passer l'appareil d'Alice à Bob.

## Le verrou du réseau

Le chiffrement de bout en bout empêche le serveur de lire. Mais c'est lui qui
distribue les clés publiques : un serveur piraté pourrait annoncer sa propre clé
sous le nom d'un appareil, et s'intercaler. Le verrou ferme cette porte.

- L'admin a une clé de signature **Ed25519**, gardée hors du serveur.
- Il signe, pour chaque appareil accepté, `"CyberSas verrou v1\0" || clé publique (32) || adresse IPv4 (4)`.
  La clé et l'adresse vont ensemble : une signature ne peut pas resservir pour
  une autre adresse.
- Chaque appareil retient la clé publique du verrou à l'inscription (l'admin
  peut la lui donner d'avance, sinon il retient la première annoncée). Ensuite,
  il refuse tout pair dont la signature ne vérifie pas, même présenté par le
  serveur, et refuse tout changement ou toute disparition du verrou.
- La clé publique du serveur est retenue de la même façon : un serveur qui en
  annoncerait une autre serait refusé.

## Itinérance et reprise

- Le serveur suit un appareil qui change de réseau, du Wi-Fi à la 4G par
  exemple. Seul un paquet authentifié, et jamais vu, peut déplacer son adresse.
- Si un initiateur envoie des données et ne reçoit rien pendant **15 secondes**,
  il rouvre une session sans attendre. C'est ce qui fait revenir les appareils
  seuls quand le serveur redémarre (22 secondes mesurées dans le labo).
- Un pair qui a reçu des données et n'a rien renvoyé depuis **10 secondes**
  envoie un paquet vide : l'autre sait que la liaison vit. Le serveur répond de
  même aux maintiens des clients.
- Le client redemande l'état du réseau toutes les dix secondes, et l'adresse du
  serveur avec : un changement d'IP ne le perd pas.

## Ce qui manque encore

- **IPv4 seulement** dans le tunnel.
- **Pas de liaison directe** entre appareils : tout passe par le relais du
  serveur, chiffré de bout en bout. Plus simple et plus fiable derrière
  n'importe quelle box, au prix d'un détour.
- **Aucun audit externe.** Les tests prouvent que la poignée de main suit la
  spécification et que les attaques connues sont refusées, et des relecteurs
  indépendants ont passé le code au crible (voir [`audit.md`](audit.md)). Cela
  ne remplace pas le regard d'un cryptographe.
