# Les outils qui dessinent ce README

Aucune image de ce dépôt ne sort d'un logiciel de dessin. Les figures fixes
sont des pages HTML que Chrome capture sans affichage, deux fois plus
denses que leur taille à l'écran ; les schémas animés sont des SVG écrits
par un script. Changer un texte, c'est changer une ligne. L'outillage vient
de SmartBudget.

## Refaire les images

    bash docs/tools/figures.sh     # bannière, bandeaux, grilles, feuille de route, limites
    bash docs/tools/captures.sh    # les planches de captures, téléphone et Fold déplié
    node docs/tools/anime.js       # les quatre schémas animés

Les captures viennent des tests de l'appli, sur le réseau d'exemple :

    cd mobile && flutter test --update-goldens test/captures_test.dart

## Ce que fait chaque fichier

- `rendu.sh` : le moteur commun. La page écrit sa hauteur réelle dans son
  `<title>` une fois les polices chargées, `--dump-dom` la lit, la capture
  suit à cette hauteur. `--virtual-time-budget` est indispensable, sinon
  Chrome capture avant l'arrivée des polices.
- `figures.sh` : tout le texte des figures fixes. C'est le seul fichier à
  ouvrir pour corriger une phrase.
- `captures.sh` : les planches, à partir de `mobile/test/captures/`.
- `anime.js` : les SVG animés, le tunnel du logo, le relais chiffré,
  l'arrivée d'un appareil et le serveur piraté. Les animations sont en
  SMIL, que GitHub joue dans une balise `<img>`. Pas de police externe : un
  SVG en `<img>` n'a pas le droit d'aller la chercher. Les instants sont
  arrondis : Chrome rejette une valeur comme `0.009999999999999998`, et une
  seule animation rejetée fige tout le SVG.

## Ce dont ils dépendent

Chrome, cherché dans `C:\Program Files\Google\Chrome\Application` ; la
variable `CHROME` prend le dessus. Node pour `anime.js`. Les polices, Syne,
Space Grotesk, JetBrains Mono et Material Symbols, viennent de Google Fonts
au moment du rendu : il faut une connexion.
