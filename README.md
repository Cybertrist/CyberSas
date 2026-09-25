<div align="center">

<img src="docs/banniere.png" alt="CyberSas : mon propre réseau privé, écrit de bout en bout. Un serveur qui relaie sans lire, une clé qui ne quitte jamais le téléphone. Go, Noise IK, ChaCha20-Poly1305, Ed25519, nftables, Flutter." width="100%">

</div>

<br>

Mon propre VPN, de bout en bout : le protocole du tunnel, le serveur, les applis. On le rejoint avec son compte Google, il n'ouvre aucun port à la maison, et son serveur relaie des paquets qu'il ne peut pas lire.

> **En cours.** Le serveur, le tunnel et le client Linux tournent dans le labo et passent leurs vérifications. L'appli Android a toute son interface, mais elle tourne encore sur un réseau d'exemple : le vrai tunnel arrive. Voir [la feuille de route](#la-feuille-de-route).

<img src="docs/schemas/tunnel.svg" alt="Le tunnel du logo de CyberSas, animé comme dans l'appli : il s'allume couche par couche, les paquets entrent, puis il s'éteint. À gauche : Noise IK, puis ChaCha20-Poly1305, clés renouvelées toutes les deux minutes. À droite, l'état : coupé, connexion, connecté." width="100%">

<img src="docs/sections/s01.png" alt="01 Ce que c'est" width="100%">

Héberger un service chez soi, c'est d'habitude ouvrir des ports sur sa box et laisser son adresse IP à la vue de tous. Partager un serveur avec quelques personnes, c'est souvent un mot de passe commun qui circule par message.

Tailscale règle ça très bien, mais c'est leur serveur, leur appli et leur protocole. CyberSas est l'exercice inverse : tout écrire soi-même, sauf les primitives cryptographiques, que personne de sérieux n'écrit.

<img src="docs/schemas/promesses.png" alt="Six promesses. Un seul point d'entrée : un petit serveur public, aucun port ouvert à la maison. Chiffré de bout en bout : le serveur relaie des paquets qu'il ne peut pas ouvrir. Un serveur qu'on n'a pas à croire : chaque appareil porte un certificat signé par la clé du verrou. La clé dans la puce du téléphone de l'admin, qui ne signe qu'après son empreinte. Un compte Google, aucun mot de passe. Tout écrit à la main, sauf les primitives cryptographiques." width="100%">

Ce n'est pas un VPN pour naviguer caché : il relie tes appareils entre eux. Ta navigation sur Internet ne passe pas par lui.

<img src="docs/sections/s02.png" alt="02 L'appli" width="100%">

Sur le téléphone, une barre flottante en bas, et le tunnel du logo qui s'allume et s'éteint avec l'interrupteur.

<img src="docs/schemas/captures-telephone.png" alt="Huit écrans sur téléphone. Rejoindre : l'adresse du serveur, la clé du verrou, puis le compte Google. L'accueil : le tunnel animé et l'interrupteur. Tunnel coupé : le logo n'est plus qu'un fantôme bleu nuit. Les appareils : la carte du réseau et les demandes à signer. Vu d'ici, tout se grise quand le tunnel est coupé. Un appareil : son nom sur le réseau, ses ports, son certificat, l'empreinte de sa clé. Les demandes : comparer l'empreinte, puis signer avec le doigt. Les réglages : renommer, verrouiller l'appli, masquer l'écran." width="100%">

Sur le Fold déplié, un rail à gauche. Toucher un appareil fait glisser la liste à gauche et ouvre son détail à droite.

<img src="docs/schemas/captures-deplie.png" alt="Quatre écrans sur le Fold déplié. L'accueil : le tunnel à gauche, l'appareil et le réseau à droite. La carte du réseau en grand à gauche avec les demandes, les machines à droite. Toucher un appareil fait glisser la liste à gauche et ouvre son détail à droite. Les réglages en deux colonnes." width="100%">

L'appli se construit dans [`mobile/`](mobile). Pour l'instant, elle démarre sur un réseau d'exemple : aucun vrai serveur, aucune vraie clé.

<img src="docs/sections/s03.png" alt="03 Comment ça marche" width="100%">

<img src="docs/schemas/relais.svg" alt="Un paquet part du téléphone fold8-tristan, en clair : GET / HTTP/1.1. Il traverse le serveur sasd, qui ne voit que des octets chiffrés, puis arrive déchiffré à la maison. Le serveur relaie ce qu'il ne peut pas lire." width="100%">

1. Dans l'appli, on se connecte avec Google.
2. L'appli génère sa paire de clés. La clé privée ne quitte jamais l'appareil.
3. Elle envoie à sasd le jeton Google, la clé publique, et la preuve qu'elle détient la clé privée. sasd vérifie le jeton auprès de Google, puis que l'adresse figure dans la liste de l'équipe.
4. sasd attribue une adresse, `10.77.0.x`. L'admin signe le certificat de l'appareil avec la clé du verrou, qu'il garde chez lui.
5. L'appareil ouvre une session avec le serveur, puis une session de bout en bout avec chaque appareil qu'il a le droit de joindre, à la demande. À partir de là, Google et l'API ne servent plus à rien : le tunnel ne se fie qu'aux clés.

Tout le protocole est décrit dans [`docs/protocole.md`](docs/protocole.md).

<img src="docs/sections/s04.png" alt="04 Rejoindre le réseau" width="100%">

<img src="docs/schemas/inscription.svg" alt="Un nouvel appareil rejoint le réseau en cinq étapes : 01 l'invitation, un QR à usage unique ; 02 l'appareil crée sa propre clé ; 03 l'admin compare l'empreinte, Qm7X-tR2k-9vLp ; 04 l'admin signe avec son doigt ; 05 l'appareil est dans le réseau, en 10.77.0.3, pour 120 jours." width="100%">

L'empreinte, ce sont les douze premiers caractères de la clé publique du nouvel appareil. Elle s'affiche des deux côtés : si elles sont identiques, personne ne s'est glissé entre les deux. Une machine sans écran, comme le serveur de la maison, s'inscrit avec une clé à usage unique donnée par l'admin, au lieu d'un compte Google.

<img src="docs/schemas/verrou.svg" alt="Un serveur piraté glisse un intrus dans le réseau : le téléphone fold8-tristan vérifie le certificat, ne trouve pas de signature du verrou, et le refuse. L'ordinateur laptop-lea, signé par le verrou, est accepté." width="100%">

Le mode d'emploi du verrou est dans [`docs/verrou.md`](docs/verrou.md).

<img src="docs/sections/s05.png" alt="05 Qui peut aller où" width="100%">

La politique est dans [`politique/politique.json`](politique/politique.json), signée par l'admin. Tout est fermé par défaut.

<img src="docs/schemas/regles.png" alt="Six règles. Les admins atteignent tout le réseau. Chacun atteint ses propres appareils, jamais ceux des autres. L'équipe atteint les services web de la maison, pas son SSH. Seul le serveur atteint le port publié de la maison. La maison ne peut ouvrir de connexion vers personne. La politique est signée par la clé du verrou : le serveur ne peut pas la changer sans que ça se voie." width="100%">

Chaque appareil applique lui-même ce qui le concerne : le serveur ne voit pas le trafic entre appareils, et ne peut pas changer les règles sans que ça se voie.

<img src="docs/sections/s06.png" alt="06 L'équipe" width="100%">

L'équipe, c'est la liste des comptes Google qui ont le droit de rejoindre le réseau, chacun dans un groupe : `admins` ou `equipe`. Elle vit sur le serveur, dans `etat/equipe.txt`, et se règle en ligne de commande :

```bash
bash scripts/sas.sh membre alice@gmail.com equipe
bash scripts/sas.sh retirer alice@gmail.com
```

Retirer quelqu'un coupe ses appareils en cinq secondes au plus. Pour un appareil volé, le révoquer aussi avec la clé du verrou : [`docs/verrou.md`](docs/verrou.md).

Gérer l'équipe et révoquer un appareil depuis l'appli, c'est l'une des prochaines étapes.

<img src="docs/sections/s07.png" alt="07 Essayer le labo" width="100%">

Il faut Docker et Bash (Git Bash suffit sous Windows).

```bash
cp .env.exemple .env            # y mettre son adresse Google dans ADMIN_EMAIL
bash scripts/sas.sh init        # secrets, autorité du labo, verrou, liste d'accès
bash scripts/sas.sh demarrer    # construit, signe la politique, lance le serveur
bash scripts/sas.sh labo        # une fausse maison, un poste d'essai, signés
bash scripts/sas.sh essai       # dix-huit vérifications, de bout en bout
```

L'essai vérifie entre autres que :

- une inscription sans preuve de possession est refusée ;
- le poste atteint le service de la maison, mais ni son port publié ni son port d'admin ;
- la maison ne peut pas se retourner vers le poste ;
- une capture réseau sur le serveur voit en clair ce que le serveur fait lui-même, mais jamais ce que le poste envoie à la maison ;
- un appareil que le serveur inscrit sans certificat est refusé par le poste ;
- une personne retirée de l'équipe perd ses appareils en quelques secondes ;
- après un redémarrage du serveur, les appareils reviennent seuls.

Les tests du code se lancent à part : `go test -race ./...` (71 tests).

Pour brancher la connexion Google, créer dans la [console Google Cloud](https://console.cloud.google.com/apis/credentials) un ID client OAuth de type **Application Web**, avec comme URI de redirection `https://auth.<domaine>/oauth2/callback`, puis :

```bash
bash scripts/sas.sh google <id>.apps.googleusercontent.com   # le secret est demandé
```

<img src="docs/sections/s08.png" alt="08 Ce qu'il y a dedans" width="100%">

```mermaid
flowchart LR
  subgraph VPS
    SD[sasd<br/>tunnel, relais, API, pare-feu, DNS]
    NG[Nginx] --- SD
    OP[oauth2-proxy] --- NG
  end
  G[(Google)]
  A[appli CyberSas<br/>Android, Windows] ==>|tunnel| SD
  M[sas, à la maison<br/>aucun port ouvert] ==>|tunnel| SD
  A -.->|chiffré de bout en bout, relayé| M
  A -.->|connexion| G
  SD -.->|vérifie le jeton| G
```

<img src="docs/schemas/dedans.png" alt="Six briques. Le protocole, internal/noise et internal/tunnel : Noise IK identique au vecteur officiel, puis ChaCha20-Poly1305 renouvelé toutes les deux minutes. sasd, le serveur : tunnel, relais chiffré, API d'inscription, pare-feu nftables, DNS du réseau. sas, le client Linux, pour les machines sans écran et l'outil de l'admin pour le verrou. Le verrou, internal/verrou : certificats avec expiration, politique signée, révocations signées. L'appli Android, mobile/, en Flutter, pour le téléphone et le Fold. Nginx et oauth2-proxy, pour publier un service de la maison derrière la connexion Google." width="100%">

<img src="docs/sections/s09.png" alt="09 La sécurité, et ses limites" width="100%">

CyberSas a été passé au crible par trois relecteurs indépendants puis par une revue de sécurité : 46 constats, dont 3 hauts, tous traités, chacun avec son test quand c'est possible. Un deuxième audit l'a ensuite passé aux outils du métier (govulncheck, staticcheck, gosec, Semgrep, Trivy, Hadolint, ShellCheck, Gixy, fuzzing différentiel contre flynn/noise) : 10 constats de plus, corrigés. Le détail est dans [`docs/audit.md`](docs/audit.md), le modèle de menace dans [`docs/menaces.md`](docs/menaces.md).

<img src="docs/schemas/limites.png" alt="Ce qui est vrai : le serveur ne lit pas ce que deux appareils s'envoient ; un serveur piraté ne fait entrer personne ; retirer quelqu'un coupe ses appareils en cinq secondes ; deux audits, 56 constats, tous traités. Ce qui ne l'est pas : pas d'audit humain, WireGuard reste le choix raisonnable pour des données sensibles ; le serveur voit les métadonnées ; ce n'est pas un VPN pour naviguer ; la clé du verrou n'a pas encore de secours." width="100%">

<a name="la-feuille-de-route"></a>
<img src="docs/sections/s10.png" alt="10 La feuille de route" width="100%">

<img src="docs/schemas/feuille.png" alt="La feuille de route. Fait : le tunnel, le serveur et le verrou ; deux audits ; l'interface de l'appli Android. En cours : la connexion Google dans l'appli. À venir : le vrai tunnel dans l'appli ; inviter pour de vrai, avec le scan du QR, l'écran d'attente, l'équipe et la révocation ; le serveur en ligne, d'abord à la maison puis sur un VPS. À discuter : l'appli Windows ; un site vitrine et une console web qui ne peut pas signer." width="100%">

Les figures de ce README sont dessinées par les scripts de [`docs/tools`](docs/tools) : aucune ne sort d'un logiciel de dessin.

<br>

<div align="center">
<sub>Tristan Joncour · élève ingénieur en cyberdéfense à l'ENSIBS</sub>
</div>
