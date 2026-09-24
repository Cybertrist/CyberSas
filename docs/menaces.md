# Modèle de menace

Ce que CyberSas protège, contre qui, et ce qu'il ne promet pas.

## Ce qu'on protège

- **Les services de la maison**, qui ne doivent être joignables que par les
  personnes autorisées.
- **L'adresse IP de la maison**, qui ne doit apparaître nulle part.
- **L'accès de l'équipe.** Un mot de passe volé ne doit pas suffire.
- **Le trafic des appareils**, qui ne doit être lisible par personne sur le
  chemin : le Wi-Fi d'un café, un opérateur, l'hébergeur du VPS.

## Ce qui est exposé

Sur Internet :

- le port **UDP 51820**, celui du tunnel. Il ne répond qu'à une initiation
  valide, venant d'une clé inscrite. À tout le reste, il ne répond rien : un
  scan ne voit qu'un port muet ;
- le port **443**, pour trois noms : `vpn.` (l'API d'inscription), `auth.` (la
  connexion Google des pages web) et `maison.` (un service publié) ;
- le port 80, qui ne fait que rediriger.

Tout autre nom est coupé avant même l'échange de certificat. L'API de sasd
n'écoute que sur 127.0.0.1 : on ne l'atteint qu'à travers Nginx.

## Contre qui

**Quelqu'un qui écoute le réseau.** Il voit des paquets UDP chiffrés et leur
taille, arrondie à 16 octets. Ni le contenu, ni les adresses internes, ni
l'identité de l'appareil : la clé statique du client voyage chiffrée.

**Quelqu'un qui rejoue ou modifie des paquets.** Un paquet modifié échoue à la
vérification de son tag. Un paquet rejoué porte un compteur déjà vu. Une
initiation rejouée porte un horodatage trop ancien. Les trois sont rejetés en
silence. Voir [`protocole.md`](protocole.md).

**Quelqu'un qui veut entrer sans y être invité.** Il lui faut un jeton Google
émis pour notre application, pour une adresse vérifiée par Google et présente
dans la liste de l'équipe. Ou une clé d'inscription, qui expire en dix minutes
et ne sert qu'une fois. L'API d'inscription est limitée à dix tentatives par
minute et par adresse.

**Un membre de l'équipe qui va trop loin**, volontairement ou parce que son
appareil est compromis. Le pare-feu du serveur ferme tout par défaut : il
n'atteint que ce que son groupe autorise. Il ne peut pas usurper l'adresse d'un
autre appareil, le tunnel vérifie la source de chaque paquet. Le retirer de la
liste coupe ses appareils en cinq secondes.

**Un service de la maison compromis.** Il ne peut se retourner vers aucun
appareil : aucune règle ne part de `etiquette:maison`.

## Ce que CyberSas ne promet pas

**Le protocole n'est pas audité.** Il reprend l'architecture de WireGuard et
ses primitives sont standard. Ses tests prouvent qu'il suit la spécification
Noise et refuse les attaques connues. Mais un protocole maison, c'est du code
que personne d'autre n'a relu. Pour des données vraiment sensibles, WireGuard
reste le choix raisonnable.

**Le serveur voit le trafic entre appareils.** Chaque appareil n'a de session
qu'avec le serveur. Un paquet du poste vers la maison est déchiffré sur le VPS,
passe le pare-feu, puis est rechiffré pour la maison. L'hébergeur du VPS, ou
quiconque le compromet, peut donc lire ce trafic. C'est le prix d'une
architecture en étoile, et aussi ce qui permet d'appliquer les règles d'accès
au centre, là où un appareil ne peut pas les contourner. Chiffrer de bout en
bout sur ce trafic, avec TLS ou SSH dans le tunnel, reste une bonne habitude.

**Pas de protection contre l'inondation de poignées de main.** Chaque
initiation, même fausse, coûte un calcul au serveur avant d'être rejetée.

**Google devient un tiers de confiance.** S'il est en panne, personne ne peut
s'inscrire. Les appareils déjà inscrits continuent de fonctionner : le tunnel
ne se fie qu'aux clés. Un compte Google volé permet d'inscrire un appareil : le
second facteur du compte limite ce risque, mais CyberSas ne peut pas l'imposer.

## Si le VPS tombe aux mains d'un attaquant

- Il lit le trafic qui traverse le serveur, comme expliqué plus haut.
- Il peut inscrire ses propres appareils et modifier la politique.
- Il récupère la clé privée du serveur et peut se faire passer pour lui. Il
  faut alors en générer une nouvelle, ce qui oblige tous les appareils à se
  réinscrire.
- Il récupère le secret du client Google, qui ne donne accès à aucun compte
  mais doit être régénéré dans la console Google Cloud.
- Il ne récupère aucune clé privée d'appareil : elles n'ont jamais quitté les
  appareils.
