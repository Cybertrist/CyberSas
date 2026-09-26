# Les outils qui dessinent le README et les docs

Aucune image de ce dépôt ne sort d'un logiciel de dessin. Les figures fixes
sont des pages HTML que Chrome capture sans affichage, deux fois plus
denses que leur taille à l'écran ; les schémas animés sont des SVG écrits
par un script. Changer un texte, c'est changer une ligne. L'outillage vient
de SmartBudget.

## Refaire les images

    bash docs/tools/figures.sh     # README : bannière, bandeaux, grilles, feuille de route, limites
    bash docs/tools/pages.sh       # docs/ : bannières, bandeaux, grilles, formats d'octets, colonnes
    bash docs/tools/captures.sh    # les planches de captures, téléphone et Fold déplié
    node docs/tools/anime.js       # les schémas animés du README
    node docs/tools/docs.js        # les schémas animés des documents

Les captures viennent des tests de l'appli, sur le réseau d'exemple :

    cd mobile && flutter test --update-goldens test/captures_test.dart

## Vérifier avant de publier

    node docs/tools/valide.js                            # chaque animation, tous les SVG
    node docs/tools/planche.js docs/schemas/relais.svg   # une animation figée à huit instants
    node docs/tools/planche.js docs/schemas/relais.svg 1.5 4   # ou aux instants choisis

- `anime.js` et `docs.js` signalent au rendu tout texte qui risque de
  déborder de sa carte (« DÉBORDEMENT »), mesuré avec la police la plus
  large qu'un visiteur puisse avoir.
- `planche.js` empile un SVG figé à plusieurs instants de son cycle, dans
  `docs/tools/controle/` (ignoré par git). On y voit d'un coup d'œil un fil
  qui n'arrive pas sur sa carte, deux textes qui se chevauchent, une bille
  qui s'arrête au mauvais endroit.
- `valide.js` contrôle les `keyTimes` de chaque animation : une seule
  animation rejetée par le navigateur fige tout le SVG sur sa première
  image, sans message d'erreur, et une planche ne le voit pas.

Une image SVG ne démarre son animation qu'une fois visible dans la page :
pour la voir tourner sur GitHub, il faut attendre quelques secondes après
l'avoir fait défiler à l'écran.

## Ce que fait chaque fichier

- `rendu.sh` : le moteur commun. La page écrit sa hauteur réelle dans son
  `<title>` une fois les polices chargées, `--dump-dom` la lit, la capture
  suit à cette hauteur. `--virtual-time-budget` est indispensable, sinon
  Chrome capture avant l'arrivée des polices.
- `gabarits.sh` : les figures qui reviennent partout. `bandeau` et
  `bandeaux` (les titres de section), `grille` (des fiches à pictogramme),
  `colonnes` (ce qui tient, ce qui ne tient pas), `banniere_doc` (l'en-tête
  d'un document), `octets` (le format d'un message, à l'échelle).
- `figures.sh` et `pages.sh` : tout le texte des figures fixes, du README
  et des documents. Ce sont les seuls fichiers à ouvrir pour corriger une
  phrase.
- `captures.sh` : les planches, à partir de `mobile/test/captures/`.
- `svg.js` : la boîte à outils des animations. Une carte connaît ses bords
  (`carte.ancre('d', 0.3)`) et les fils partent et arrivent sur eux ; une
  bille suit n'importe quel tracé ; une flèche se trace, et sa pointe
  n'arrive qu'avec elle.
- `anime.js` : le tunnel du logo, le relais en deux enveloppes,
  l'inscription en séquence, le serveur piraté, l'architecture, la
  révocation.
- `docs.js` : les deux couches, la poignée de main, la vie d'une session,
  le filtre, l'inondation, la chaîne de confiance, le coffre du téléphone,
  la surface d'attaque.

Les animations sont en SMIL, que GitHub joue dans une balise `<img>`. Pas
de police externe : un SVG en `<img>` n'a pas le droit d'aller la chercher.
Deux pièges déjà rencontrés : Chrome rejette un instant comme
`0.009999999999999998` (tous les instants sont arrondis), et un filtre de
flou posé sur une ligne parfaitement droite l'efface, sa boîte n'ayant pas
de hauteur (le halo d'un trait est donc un second trait, large et pâle).

## Ce dont ils dépendent

Chrome, cherché dans `C:\Program Files\Google\Chrome\Application` ; la
variable `CHROME` prend le dessus. Node pour les scripts `.js`. Les
polices, Syne, Space Grotesk, JetBrains Mono et Material Symbols, viennent
de Google Fonts au moment du rendu : il faut une connexion. Jamais de
chiffres dans un titre en Syne : ses numéraux sont mauvais.
