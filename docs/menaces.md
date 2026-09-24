# Modèle de menace

Ce que CyberSas protège, contre qui, et ce qu'il ne promet pas.

## Ce qu'on protège

- **Le contenu des échanges** entre appareils : personne sur le chemin ne doit
  pouvoir le lire, **pas même le serveur**.
- **Les services de la maison**, qui ne doivent être joignables que par les
  appareils autorisés, et seulement sur les ports autorisés.
- **L'adresse IP de la maison**, qui ne doit apparaître nulle part.
- **L'accès de l'équipe** : un mot de passe volé, une clé publique connue ou un
  serveur piraté ne doivent pas suffire à entrer ou à s'intercaler.

## Ce qui est exposé

Sur Internet :

- le port **UDP 51820**, celui du tunnel. Il ne répond qu'à une initiation
  portant un mac1 valide, donc calculé avec la clé publique du serveur, que
  seuls les appareils inscrits connaissent, et venant d'une clé inscrite. À
  tout le reste, il ne répond rien : un scan ne voit qu'un port muet ;
- le port **443**, pour trois noms : `vpn.` (l'API d'inscription), `auth.` (la
  connexion Google des pages web) et `maison.` (un service publié) ;
- le port 80, qui ne fait que rediriger.

Tout autre nom est coupé avant même l'échange de certificat. L'API de sasd
n'écoute que sur 127.0.0.1 : on ne l'atteint qu'à travers Nginx.

## Contre qui

**Quelqu'un qui écoute le réseau** (Wi-Fi d'un café, opérateur). Il voit des
paquets UDP chiffrés, leur taille arrondie à 16 octets, et les adresses IP
publiques. Ni le contenu, ni les adresses internes, ni l'identité de
l'appareil : sa clé statique voyage chiffrée.

**L'hébergeur du VPS, ou quiconque lit la mémoire du serveur.** Il voit qui
parle à qui, quand, et combien. Il ne voit pas ce qui se dit : entre deux
appareils, le serveur ne relaie que des messages chiffrés avec une clé qu'il
n'a pas. Le labo le vérifie par une capture réseau sur le serveur lui-même.

**Quelqu'un qui rejoue ou modifie des paquets.** Un paquet modifié échoue à la
vérification de son tag. Un paquet rejoué porte un compteur déjà vu, une
initiation rejouée un horodatage trop ancien. Tous sont rejetés en silence.

**Quelqu'un qui inonde le serveur de poignées de main.** Sans la clé publique
du serveur, ses messages sont jetés au premier hachage. Avec, et sous charge, il
doit prouver qu'il reçoit les paquets envoyés à son adresse (le cookie), puis
se limiter à dix poignées de main par seconde.

**Quelqu'un qui veut entrer sans y être invité.** Il lui faut un jeton Google
émis pour notre application, pour une adresse vérifiée et présente dans la
liste de l'équipe, ou une clé d'inscription qui expire en dix minutes et ne
sert qu'une fois. Et dans les deux cas, prouver qu'il détient la clé privée
qu'il inscrit.

**Quelqu'un qui veut s'approprier l'appareil d'un autre.** Les clés publiques
circulent, mais inscrire une clé demande de prouver qu'on détient sa moitié
privée. Et une clé inscrite ne change jamais de propriétaire.

**Un membre de l'équipe qui va trop loin**, volontairement ou parce que son
appareil est compromis. Il n'atteint que ce que la politique autorise : le
serveur ne relaie pas vers les appareils sans relation avec lui, et ceux qui en
ont filtrent eux-mêmes ce qui entre. Il ne peut pas usurper l'adresse d'un autre
appareil, ni se servir d'un appareil qui l'accepte comme routeur vers le réseau
local de celui-ci. Il ne peut pas prendre le nom d'une machine ou du serveur
dans le DNS du VPN, ni écrire lui-même les en-têtes d'identité qu'un service
publié croit : le port publié n'est ouvert qu'au serveur. Le retirer de la liste
coupe ses appareils en cinq secondes.

**Un service de la maison compromis.** Il ne peut se retourner vers aucun
appareil : aucune règle ne part de `etiquette:maison`, et les appareils
refusent ce qu'il tenterait d'ouvrir chez eux.

**Un serveur piraté.** C'est le cas le plus grave, voir plus bas.

## Si le VPS tombe aux mains d'un attaquant

Grâce au bout en bout et au verrou, bien moins qu'avant. Tout ce qui suit
suppose le verrou en place ; sans lui, le serveur est cru sur parole.

- Il **ne lit pas** le trafic entre appareils.
- Il **ne peut pas s'intercaler** entre deux appareils : pour se faire passer
  pour l'un d'eux, il lui faudrait un certificat signé par le verrou, dont la
  clé privée n'a jamais touché le serveur. Les appareils refusent aussi tout
  changement de la clé du serveur ou du verrou, même en se réinscrivant.
- Il **ne peut pas ouvrir de port** : chaque appareil calcule ses règles
  d'entrée lui-même, à partir de la politique signée par l'admin et des
  certificats. Resservir une ancienne politique plus permissive ne marche pas
  non plus : les appareils n'acceptent jamais une version plus ancienne que la
  dernière vue.
- Il **ne peut pas faire revenir un appareil banni** : la liste de révocation
  est signée, et ne recule jamais. Un certificat expire de toute façon au bout
  de 90 jours.
- Il peut **inscrire ses propres appareils**, mais sans certificat, les autres
  les refusent.
- Il peut **couper** le réseau : ne plus relayer, ou cesser de transmettre les
  mises à jour signées. Un serveur a toujours ce pouvoir-là. Un appareil qui n'a
  jamais vu une nouvelle révocation ne peut pas l'appliquer : c'est la raison
  d'être de l'expiration des certificats.
- Il **lit en clair** ce qui s'adresse au serveur lui-même : le DNS du réseau,
  et les pages publiées par Nginx sur `maison.`, puisque le TLS se termine sur
  le VPS. Pour ces pages, passer par le VPN plutôt que par la page publique
  garde le chiffrement de bout en bout.
- Il récupère la clé privée du serveur et le secret du client Google. Il faut
  alors les régénérer, et réinscrire les appareils.

## Ce que CyberSas ne promet pas

**Le protocole n'est pas audité par un expert humain.** Il reprend
l'architecture de WireGuard, ses primitives sont standard, sa poignée de main
correspond octet pour octet aux vecteurs officiels de Noise, des millions de
messages forgés n'ont rien produit, et des relecteurs indépendants l'ont passé
au crible ([`audit.md`](audit.md)). Mais un protocole maison reste du code que
peu de gens ont lu. Pour des données dont la fuite serait grave, WireGuard reste
le choix raisonnable.

**Les métadonnées restent visibles du serveur** : qui parle à qui, quand, et
combien.

**Google devient un tiers de confiance** pour les inscriptions. S'il est en
panne, personne ne peut s'inscrire, mais les appareils déjà inscrits continuent
de fonctionner : le tunnel ne se fie qu'aux clés. Un compte Google volé permet
d'inscrire un appareil ; avec le verrou, cet appareil reste inutile tant que
l'admin ne l'a pas signé.

**Le premier contact.** Un appareil à qui l'on ne donne pas la clé du verrou
d'avance retient la première qu'on lui annonce. Si ce premier contact est
détourné, il retiendra la mauvaise. Donner la clé d'avance (`--verrou`) ferme
ce risque ; l'empreinte affichée permet de vérifier après coup.
