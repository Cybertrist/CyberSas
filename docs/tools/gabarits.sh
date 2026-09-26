#!/bin/bash
# Les figures qui reviennent d'un document à l'autre : bandeaux de
# section, grilles de fiches, deux colonnes, bannière de document, format
# d'un message. Chacune écrit sa page dans html/ puis la rend à l'endroit
# demandé. Chargé par rendu.sh.
ICONES='<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,500,1,0" rel="stylesheet">'

# page <nom> <sortie.png> : rend html/<nom>.html (déjà écrite) vers sortie.
page () {
  mkdir -p "$(dirname "$2")"
  rendre "$1.html" "$2"
}

# bandeau <numéro> <titre> <sortie.png>
bandeau () {
local nom="s-$(basename "$(dirname "$3")")-$(basename "$3" .png)"
{ entete 1280; cat <<HTML
<style>
.w{height:118px;display:flex;flex-direction:column;justify-content:center;gap:18px;padding:0 60px}
.l{display:flex;align-items:center;gap:20px;height:40px}
.ix{width:52px;height:40px;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-family:'JetBrains Mono',monospace;
  font-size:15px;color:#31E7FD;border:1.5px solid #31E7FD4D;background:#31E7FD1C;border-radius:6px}
h2{font-family:Syne,sans-serif;font-weight:800;font-size:29px;letter-spacing:5px;text-transform:uppercase;white-space:nowrap}
.r{height:2px;display:flex}.r .a{width:52px;background:#31E7FD}.r .b{flex:1;background:linear-gradient(90deg,#3A4450,#222A34 42%,transparent)}
</style></head><body>
<div class="w"><div class="l"><div class="ix">$1</div><h2>$2</h2></div><div class="r"><i class="a"></i><i class="b"></i></div></div>
<script>
// Un titre trop long se resserre jusqu'à tenir dans la marge de droite.
document.fonts.ready.then(()=>{const h=document.querySelector('h2');let s=29;
  while(h.getBoundingClientRect().right>1220&&s>16){s--;h.style.fontSize=s+'px';h.style.letterSpacing=(s/29*5).toFixed(2)+'px';}});
</script>
HTML
pied; } > "$D/html/$nom.html"
page "$nom" "$3"
}

# bandeaux <dossier> "titre" ... : les bandeaux 01, 02… dans <dossier>/sNN.png
bandeaux () {
local dossier="$1" n=1; shift
for titre in "$@"; do bandeau "$(printf '%02d' $n)" "$titre" "$dossier/s$(printf '%02d' $n).png"; n=$((n+1)); done
}

# grille <sortie.png> <colonnes> "icone|titre|texte" ...
grille () {
local sortie="$1" cols="$2"; shift 2
local nom="g-$(basename "$(dirname "$sortie")")-$(basename "$sortie" .png)" cartes=""
for e in "$@"; do
  IFS='|' read -r ic ti tx <<< "$e"
  cartes+="<div class=\"c\"><span class=\"ic\">$ic</span><div><h3>$ti</h3><p>$tx</p></div></div>"
done
{ entete 1280; echo "$ICONES"; cat <<HTML
<style>
.w{padding:22px 56px;display:grid;grid-template-columns:repeat($cols,1fr);gap:14px}
.c{background:var(--carte);border:1px solid var(--bord);border-radius:14px;padding:18px;display:flex;gap:15px;align-items:flex-start}
.ic{font-family:'Material Symbols Rounded';font-size:24px;width:46px;height:46px;flex-shrink:0;border-radius:13px;
  display:flex;align-items:center;justify-content:center;color:#31E7FD;background:#31E7FD14;border:1px solid #31E7FD38;
  box-shadow:0 0 18px #31E7FD22}
h3{font-family:'Space Grotesk',sans-serif;font-size:16px;font-weight:700;margin:2px 0 5px}
p{font-family:'Space Grotesk',sans-serif;font-size:13.5px;line-height:1.5;color:var(--texte)}
code{font-family:'JetBrains Mono',monospace;font-size:12.5px;color:#C3CCD7}
</style></head><body><div class="w">$cartes</div>
HTML
pied; } > "$D/html/$nom.html"
page "$nom" "$sortie"
}

# colonnes <sortie.png> "icone|Titre vert" "point|point…" "icone|Titre rouge" "point|point…"
# Deux colonnes, l'une verte (ce qui tient), l'autre rouge (ce qui ne tient
# pas). Un point commence par sa partie en gras, suivie de « ¦ ».
_colonne () {
  local couleur="$1" tete="$2" points="$3" li="" ic ti p
  IFS='|' read -r ic ti <<< "$tete"
  IFS='|' read -ra pts <<< "$points"
  for p in "${pts[@]}"; do li+="<li><span><b>${p%%¦*}</b>${p#*¦}</span></li>"; done
  echo "<div class=\"col\" style=\"--a:$couleur\"><h3><span>$ic</span>$ti</h3><ul>$li</ul></div>"
}
colonnes () {
local sortie="$1" nom="c-$(basename "$(dirname "$1")")-$(basename "$1" .png)"
{ entete 1280; echo "$ICONES"; cat <<HTML
<style>
.w{padding:24px 56px;display:grid;grid-template-columns:1fr 1fr;gap:16px}
.col{background:var(--carte);border:1px solid var(--bord);border-radius:14px;padding:18px 20px}
h3{display:flex;align-items:center;gap:10px;font-family:Syne,sans-serif;font-size:19px;margin-bottom:10px;color:var(--a)}
h3 span{font-family:'Material Symbols Rounded';font-size:24px}
li{list-style:none;display:flex;gap:10px;padding:9px 0;border-top:1px solid #1A222C;font-family:'Space Grotesk',sans-serif;font-size:14px;line-height:1.5;color:var(--texte)}
li:first-child{border-top:0}
li:before{content:'';flex-shrink:0;width:6px;height:6px;border-radius:50%;margin-top:8px;background:var(--a)}
b{color:#DDE4EC;font-weight:600}
code{font-family:'JetBrains Mono',monospace;font-size:12.5px;color:#C3CCD7}
</style></head><body><div class="w">
$(_colonne '#3DDC97' "$2" "$3")
$(_colonne '#FF5C63' "$4" "$5")
</div>
HTML
pied; } > "$D/html/$nom.html"
page "$nom" "$sortie"
}

# banniere_doc <sortie.png> <ÉTIQUETTE> <Titre> <phrase> [pastille…]
# L'en-tête d'un document de docs/ : plus basse que la bannière du README,
# même logo, même lumière.
banniere_doc () {
local sortie="$1" etiq="$2" titre="$3" phrase="$4"; shift 4
local nom="b-$(basename "$sortie" .png)" pl="" p
for p in "$@"; do pl+="<span>$p</span>"; done
[ -n "$pl" ] && pl="<div class=\"pl\">$pl</div>"
{ entete 1280; cat <<HTML
<style>
.w{width:1280px;height:250px;position:relative;overflow:hidden;
   background:radial-gradient(55% 140% at 10% 0%,#31E7FD20 0%,transparent 60%),linear-gradient(135deg,#0D1117 0%,#0D1117 55%,#04060A 100%)}
.grille{position:absolute;inset:0;opacity:.4;
  background-image:linear-gradient(#31E7FD12 1px,transparent 1px),linear-gradient(90deg,#31E7FD12 1px,transparent 1px);
  background-size:46px 46px;-webkit-mask-image:radial-gradient(70% 100% at 8% 50%,#000 0%,transparent 72%)}
.cat{position:absolute;top:24px;right:30px;display:flex;gap:8px}
.cat b{font-family:'JetBrains Mono',monospace;font-weight:500;font-size:12px;letter-spacing:2.2px;
  color:#31E7FDE0;border:1px solid #31E7FD46;background:#31E7FD12;border-radius:5px;padding:7px 13px}
.in{position:absolute;inset:0;display:flex;align-items:center;gap:40px;padding:0 66px}
.logo{width:112px;height:112px;flex-shrink:0;border-radius:28px;border:1.5px solid #31E7FD55;box-shadow:0 0 28px #31E7FD40,0 12px 26px #000A}
.et{font-family:'JetBrains Mono',monospace;font-size:13px;letter-spacing:3px;color:#31E7FD;margin-bottom:10px}
h1{font-family:Syne,sans-serif;font-weight:800;font-size:46px;line-height:1.05;letter-spacing:-1px}
.sl{font-family:'Space Grotesk',sans-serif;font-size:19px;line-height:1.5;margin-top:12px;color:#94A3B0;max-width:900px}
.pl{display:flex;gap:8px;margin-top:14px}
.pl span{font-family:'Space Grotesk',sans-serif;font-size:12.5px;font-weight:500;letter-spacing:.6px;
  color:#31E7FDD0;border:1px solid #31E7FD3A;background:#31E7FD0E;border-radius:6px;padding:5px 10px}
.ln{position:absolute;left:0;right:0;bottom:0;height:3px;background:linear-gradient(90deg,#31E7FD 0%,#01B9FD 40%,transparent 90%)}
</style></head><body>
<div class="w"><div class="grille"></div>
<div class="cat"><b>CYBERSAS</b><b>DOC</b></div>
<div class="in"><img class="logo" src="file:///$DOCS/logo.png">
<div><div class="et">$etiq</div><h1>$titre</h1><p class="sl">$phrase</p>$pl</div></div>
<div class="ln"></div></div>
HTML
pied; } > "$D/html/$nom.html"
page "$nom" "$sortie"
}

# octets <sortie.png> "Titre|taille|champ:octets:couleur,champ:octets:couleur…" ...
# Le format d'un message, à l'échelle : chaque champ est une case aussi
# large que ses octets (avec un minimum pour rester lisible). Une taille
# « n » marque un champ de longueur variable. Couleurs : c (cyan), b
# (bleu), v (vert), g (gris).
octets () {
local sortie="$1" nom="o-$(basename "$1" .png)" lignes="" m ti taille champs c ch n co poids; shift
for m in "$@"; do
  IFS='|' read -r ti taille champs <<< "$m"
  local cases=""
  IFS=',' read -ra cs <<< "$champs"
  for c in "${cs[@]}"; do
    IFS=':' read -r ch n co <<< "$c"
    poids="$n"; [ "$n" = "n" ] && poids=60
    # Une case n'est jamais plus étroite que son nom.
    cases+="<div class=\"f $co\" style=\"flex:$poids 1 0;min-width:$(( ${#ch} * 8 + 22 ))px\"><b>$ch</b><i>$n</i></div>"
  done
  lignes+="<div class=\"m\"><div class=\"t\"><h3>$ti</h3><span>$taille</span></div><div class=\"r\">$cases</div></div>"
done
{ entete 1280; cat <<HTML
<style>
.w{padding:22px 56px;display:flex;flex-direction:column;gap:12px}
.m{background:var(--carte);border:1px solid var(--bord);border-radius:14px;padding:14px 16px;display:flex;gap:16px;align-items:center}
.t{width:150px;flex-shrink:0}
h3{font-family:'Space Grotesk',sans-serif;font-size:15.5px;font-weight:700}
.t span{font-family:'JetBrains Mono',monospace;font-size:12px;color:var(--texte)}
.r{flex:1;display:flex;gap:4px;min-width:0}
.f{min-width:70px;height:54px;border-radius:8px;border:1px solid;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;overflow:hidden;padding:0 6px}
.f b{font-family:'JetBrains Mono',monospace;font-size:12px;font-weight:500;white-space:nowrap}
.f i{font-style:normal;font-family:'JetBrains Mono',monospace;font-size:11px;opacity:.7}
.c{color:#31E7FD;border-color:#31E7FD66;background:#31E7FD14}
.b{color:#4CC9FF;border-color:#01B9FD66;background:#01B9FD14}
.v{color:#3DDC97;border-color:#3DDC9766;background:#3DDC9714}
.g{color:#94A3B0;border-color:#2A333D;background:#11171E}
</style></head><body><div class="w">$lignes</div>
HTML
pied; } > "$D/html/$nom.html"
page "$nom" "$sortie"
}
