#!/bin/bash
# Le moteur commun : une page HTML devient une image, capturée par Chrome
# sans affichage, deux fois plus dense que sa taille d'affichage. Repris
# de SmartBudget.
#
# La hauteur d'une figure dépend de son contenu. La page l'écrit dans son
# <title> une fois les polices chargées ; --dump-dom la lit, la capture
# suit à cette hauteur exacte. --virtual-time-budget est indispensable :
# sans lui, Chrome capture avant l'arrivée des polices de Google Fonts.
#
#   source docs/tools/rendu.sh
#   rendre <fichier.html> <sortie.png> [largeur]
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
B="$(cd "$D" && pwd -W 2>/dev/null || pwd)"
DOCS="$(cd "$D/.." && pwd -W 2>/dev/null || pwd)"
RACINE="$(cd "$D/../.." && pwd -W 2>/dev/null || pwd)"
mkdir -p "$D/html"

# Le haut commun de toutes les pages : les polices de la charte, le fond de
# GitHub en thème sombre, les couleurs du logo.
entete () {
cat <<HTML
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Syne:wght@700;800&family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:${1:-1280}px;background:#0D1117;color:#F1F5F9}
:root{--cyan:#31E7FD;--bleu:#01B9FD;--vert:#3DDC97;--rouge:#FF5C63;--carte:#0C1117;--bord:#2A333D;--texte:#94A3B0;--titre:#F1F5F9}
.mono{font-family:'JetBrains Mono',monospace}
.sans{font-family:'Space Grotesk',sans-serif}
</style>
HTML
}

pied () {
cat <<'HTML'
<script>document.fonts.ready.then(()=>{setTimeout(()=>{
  document.title='H'+Math.ceil(document.documentElement.getBoundingClientRect().height);},300);});</script>
</body></html>
HTML
}

rendre () {
  local page="$1" sortie="$2" largeur="${3:-1280}" H
  local url="file:///$B/html/$(basename "$page")"
  H="$("$CH" --headless=new --disable-gpu --virtual-time-budget=12000 --dump-dom "$url" 2>/dev/null \
      | grep -o '<title>H[0-9]*' | grep -o '[0-9]*' | head -1)"
  [ -z "$H" ] && { echo "  ÉCHEC de la mesure : $page" >&2; return 1; }
  "$CH" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=12000 \
    --force-device-scale-factor=2 --default-background-color=00000000 --screenshot="$sortie" --window-size="$largeur,$H" "$url" >/dev/null 2>&1
  echo "  $(basename "$sortie")  ${largeur}x${H}"
}
