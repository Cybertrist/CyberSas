#!/bin/bash
# Rend les planches de fiches que audit.js vient d'écrire.
#
#   node docs/tools/audit.js && bash docs/tools/audit.sh
source "$(dirname "${BASH_SOURCE[0]}")/rendu.sh"
mkdir -p "$DOCS/schemas/audit"
while read -r nom; do
  [ -n "$nom" ] && rendre "$nom.html" "$DOCS/schemas/audit/$nom.png"
done < "$D/html/fiches.liste"
