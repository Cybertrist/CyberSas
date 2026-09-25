#!/bin/bash
# Toutes les figures fixes du README : la bannière, les bandeaux de
# section, les grilles, la feuille de route et les limites. C'est le seul
# fichier à ouvrir pour changer un texte.
#
#   bash docs/tools/figures.sh
source "$(dirname "${BASH_SOURCE[0]}")/rendu.sh"
mkdir -p "$DOCS/sections" "$DOCS/schemas"
LOGO="file:///$DOCS/logo.png"
ICONES='<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,500,1,0" rel="stylesheet">'

# ------------------------------------------------------------- bannière
# Le logo est plein cadre, sans badge : la plaque arrondie et son contour
# sont tracés ici, comme sur la carte du profil.
{ entete 1280; cat <<HTML
<style>
.w{width:1280px;height:340px;position:relative;overflow:hidden;
   background:radial-gradient(55% 140% at 10% 0%,#31E7FD24 0%,transparent 60%),linear-gradient(135deg,#0D1117 0%,#0D1117 55%,#04060A 100%)}
.grille{position:absolute;inset:0;opacity:.4;
  background-image:linear-gradient(#31E7FD12 1px,transparent 1px),linear-gradient(90deg,#31E7FD12 1px,transparent 1px);
  background-size:46px 46px;-webkit-mask-image:radial-gradient(70% 100% at 8% 50%,#000 0%,transparent 72%)}
.cat{position:absolute;top:26px;right:30px;display:flex;gap:8px}
.cat b{font-family:'JetBrains Mono',monospace;font-weight:500;font-size:12px;letter-spacing:2.2px;
  color:#31E7FDE0;border:1px solid #31E7FD46;background:#31E7FD12;border-radius:5px;padding:7px 13px}
.cat i{font-style:normal;font-family:'JetBrains Mono',monospace;font-weight:500;font-size:12px;letter-spacing:2.2px;
  color:#94A3B0;border:1px solid #2A333D;background:#0C1117;border-radius:5px;padding:7px 13px}
.in{position:absolute;inset:0;display:flex;align-items:center;gap:48px;padding:0 66px}
.logo{width:150px;height:150px;flex-shrink:0;border-radius:36px;border:1.5px solid #31E7FD55;
  box-shadow:0 0 34px #31E7FD40,0 14px 30px #000A}
h1{font-family:Syne,sans-serif;font-weight:800;font-size:60px;line-height:1;letter-spacing:-1.5px}
h1 em{font-style:normal;color:var(--cyan)}
.sl{font-family:'Space Grotesk',sans-serif;font-size:22px;line-height:1.55;margin-top:18px;color:#94A3B0;max-width:860px}
.sl b{font-weight:500;color:#E6EDF3}.sl em{font-style:normal;color:var(--cyan)}
.pl{display:flex;gap:8px;margin-top:18px}
.pl span{font-family:'Space Grotesk',sans-serif;font-size:12.5px;font-weight:500;letter-spacing:.6px;
  color:#31E7FDD0;border:1px solid #31E7FD3A;background:#31E7FD0E;border-radius:6px;padding:6px 11px}
.ln{position:absolute;left:0;right:0;bottom:0;height:3px;background:linear-gradient(90deg,#31E7FD 0%,#01B9FD 40%,transparent 90%)}
</style></head><body>
<div class="w"><div class="grille"></div>
<div class="cat"><b>VPN</b><b>GO</b><b>ANDROID</b><i>EN COURS</i></div>
<div class="in"><img class="logo" src="$LOGO">
<div><h1>Cyber<em>Sas</em></h1>
<p class="sl"><b>Mon propre réseau privé, écrit de bout en bout.</b><br>Un serveur qui <em>relaie sans lire</em>, une clé qui ne quitte <em>jamais</em> le téléphone.</p>
<div class="pl"><span>Go</span><span>Noise IK</span><span>ChaCha20-Poly1305</span><span>Ed25519</span><span>nftables</span><span>Flutter</span></div></div></div>
<div class="ln"></div></div>
HTML
pied; } > "$D/html/banniere.html"
rendre banniere.html "$DOCS/banniere.png"

# -------------------------------------------------------------- bandeaux
bandeau () {
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
pied; } > "$D/html/s$1.html"
rendre "s$1.html" "$DOCS/sections/s$1.png"
}
n=1
for titre in "Ce que c'est" "L'appli" "Comment ça marche" "Rejoindre le réseau" "Qui peut aller où" \
             "L'équipe" "Essayer le labo" "Ce qu'il y a dedans" "La sécurité, et ses limites" "La feuille de route"; do
  bandeau "$(printf '%02d' $n)" "$titre"; n=$((n+1))
done

# ------------------------------------------------------------- les grilles
# grille <nom> <colonnes> "icone|titre|texte" ...
grille () {
local nom="$1" cols="$2"; shift 2
local cartes=""
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
rendre "$nom.html" "$DOCS/schemas/$nom.png"
}

grille promesses 3 \
  "hub|Un seul point d'entrée|Un petit serveur public, et c'est tout. À la maison, aucun port ouvert : la machine sort vers le serveur par le tunnel." \
  "lock|Chiffré de bout en bout|Entre deux appareils, le serveur relaie des paquets qu'il ne peut pas ouvrir. Il n'a pas les clés." \
  "verified_user|Un serveur qu'on n'a pas à croire|Chaque appareil porte un certificat signé par la clé du verrou. Un serveur piraté ne peut ni s'intercaler, ni faire entrer un intrus." \
  "fingerprint|La clé dans la puce du téléphone|La clé du verrou vit dans la puce sécurisée du téléphone de l'admin, et ne signe qu'après son empreinte." \
  "account_circle|Un compte Google, aucun mot de passe|On rejoint le réseau avec son compte Google. Rien n'est créé, stocké ni partagé ici." \
  "code|Tout écrit à la main|Le protocole, le serveur, les clients et l'appli. Seules les primitives cryptographiques viennent de bibliothèques éprouvées."

grille regles 3 \
  "admin_panel_settings|Les admins|Atteignent tout le réseau." \
  "devices|Chacun ses appareils|Chacun atteint ses propres appareils, jamais ceux des autres." \
  "language|L'équipe et la maison|L'équipe atteint les services web de la maison, pas son SSH." \
  "dns|Le port publié|Seul le serveur atteint le port que la maison publie sur Internet." \
  "block|La maison ne se retourne pas|La maison ne peut ouvrir de connexion vers personne." \
  "gpp_good|Signée par l'admin|La politique est signée par la clé du verrou : le serveur ne peut pas la changer sans que ça se voie."

grille dedans 3 \
  "sync_alt|Le protocole|<code>internal/noise</code> et <code>internal/tunnel</code> : poignée de main Noise IK, identique octet pour octet au vecteur officiel, puis ChaCha20-Poly1305, renouvelé toutes les deux minutes." \
  "dns|sasd, le serveur|<code>cmd/sasd</code> : le tunnel, le relais chiffré, l'API d'inscription en HTTPS, le pare-feu nftables et le DNS du réseau (<code>maison.sas.internal</code>)." \
  "terminal|sas, le client Linux|<code>cmd/sas</code> : pour les machines sans écran comme le serveur de la maison, et l'outil de l'admin pour le verrou." \
  "key|Le verrou|<code>internal/verrou</code> : certificats d'appareil avec expiration, politique signée et versionnée, révocations signées." \
  "smartphone|L'appli Android|<code>mobile/</code> : Flutter, pensée pour le téléphone comme pour le Fold déplié. Pour l'instant, une démo sur un réseau d'exemple." \
  "shield|Nginx et oauth2-proxy|Pour publier un service de la maison sur une page web, derrière la même connexion Google."

# ------------------------------------------------------- feuille de route
# etape <état> <titre> <texte> ; état : fait, cours, venir, discuter
etape () {
  local ch lib
  case "$1" in
    fait) ch=v; lib='FAIT';; cours) ch=c; lib='EN COURS';; venir) ch=g; lib='À VENIR';; discuter) ch=o; lib='À DISCUTER';;
  esac
  printf '<div class="e %s"><i></i><div class="t"><h3>%s</h3><p>%s</p></div><b>%s</b></div>' "$ch" "$2" "$3" "$lib"
}
{ entete 1280; cat <<HTML
<style>
.w{padding:24px 56px;display:flex;flex-direction:column;gap:10px;position:relative}
.w:before{content:'';position:absolute;left:79px;top:40px;bottom:40px;width:2px;background:linear-gradient(#3DDC97,#31E7FD 38%,#2A333D 60%)}
.e{display:flex;align-items:center;gap:22px;position:relative}
.e i{width:48px;height:48px;flex-shrink:0;border-radius:50%;background:#0D1117;border:2px solid var(--a);box-shadow:0 0 18px color-mix(in srgb,var(--a) 40%,transparent);position:relative;z-index:1}
.e i:after{content:'';position:absolute;inset:14px;border-radius:50%;background:var(--a)}
.t{flex:1;background:var(--carte);border:1px solid var(--bord);border-radius:14px;padding:14px 18px}
h3{font-family:'Space Grotesk',sans-serif;font-size:16px;font-weight:700;margin-bottom:4px}
p{font-family:'Space Grotesk',sans-serif;font-size:13.5px;line-height:1.5;color:var(--texte)}
b{font-family:'JetBrains Mono',monospace;font-size:11.5px;font-weight:500;letter-spacing:1.8px;color:var(--a);
  border:1px solid color-mix(in srgb,var(--a) 40%,transparent);background:color-mix(in srgb,var(--a) 8%,transparent);border-radius:6px;padding:6px 11px;width:128px;text-align:center}
.v{--a:#3DDC97}.c{--a:#31E7FD}.g{--a:#5C6A7A}.o{--a:#94A3B0}
.g i:after,.o i:after{background:transparent}
</style></head><body><div class="w">
$(etape fait 'Le tunnel, le serveur et le verrou' 'Noise IK, relais chiffré de bout en bout, certificats et politique signés. 71 tests Go, 18 vérifications de bout en bout dans le labo.')
$(etape fait 'Deux audits' '46 constats de trois relecteurs et d’une revue de sécurité, puis 10 de plus aux outils du métier. Tous traités.')
$(etape fait 'L’interface de l’appli Android' 'Tous les écrans, sur téléphone et sur Fold, avec la signature à l’empreinte. Elle tourne sur un réseau d’exemple.')
$(etape cours 'La connexion Google dans l’appli' 'Le client OAuth Google, puis l’invite native d’Android : un compte, une touche.')
$(etape venir 'Le vrai tunnel dans l’appli' 'Le moteur Go embarqué, et le service VPN d’Android : l’interrupteur ouvre enfin un vrai tunnel.')
$(etape venir 'Inviter pour de vrai' 'Une invitation qui porte le serveur et la clé du verrou, le scan du QR, l’écran d’attente du nouvel appareil, l’équipe et la révocation depuis l’appli.')
$(etape venir 'Le serveur en ligne' 'D’abord sur un ordinateur à la maison pour les essais, puis sur un VPS avec un certificat Let’s Encrypt.')
$(etape discuter 'L’appli Windows' 'Le moteur tourne déjà sur PC ; il manque le pilote réseau et l’interface.')
$(etape discuter 'Un site, et une console web' 'Une vitrine pour présenter CyberSas, et une console pour voir le réseau à distance, sans jamais pouvoir signer.')
</div>
HTML
pied; } > "$D/html/feuille.html"
rendre feuille.html "$DOCS/schemas/feuille.png"

# -------------------------------------------------------------- limites
{ entete 1280; echo "$ICONES"; cat <<'HTML'
<style>
.w{padding:24px 56px;display:grid;grid-template-columns:1fr 1fr;gap:16px}
.col{background:var(--carte);border:1px solid var(--bord);border-radius:14px;padding:18px 20px}
h3{display:flex;align-items:center;gap:10px;font-family:Syne,sans-serif;font-size:19px;margin-bottom:10px;color:var(--a)}
h3 span{font-family:'Material Symbols Rounded';font-size:24px}
li{list-style:none;display:flex;gap:10px;padding:9px 0;border-top:1px solid #1A222C;font-family:'Space Grotesk',sans-serif;font-size:14px;line-height:1.5;color:var(--texte)}
li:first-child{border-top:0}
li:before{content:'';flex-shrink:0;width:6px;height:6px;border-radius:50%;margin-top:8px;background:var(--a)}
b{color:#DDE4EC;font-weight:600}
</style></head><body><div class="w">
<div class="col" style="--a:#3DDC97"><h3><span>verified_user</span>Ce qui est vrai</h3><ul>
<li><span><b>Le serveur ne lit pas</b> ce que deux appareils s’envoient : une capture réseau sur le serveur ne voit que du chiffré, c’est l’un des essais du labo.</span></li>
<li><span><b>Un serveur piraté ne fait entrer personne.</b> Sans certificat signé par le verrou, un appareil est refusé par les autres.</span></li>
<li><span><b>Retirer quelqu’un de l’équipe</b> coupe ses appareils en cinq secondes au plus.</span></li>
<li><span><b>Deux audits</b>, 56 constats, tous traités, chacun avec son test quand c’est possible.</span></li>
</ul></div>
<div class="col" style="--a:#FF5C63"><h3><span>info</span>Ce qui ne l’est pas</h3><ul>
<li><span><b>Pas d’audit humain.</b> Pour des données dont la fuite serait grave, WireGuard reste le choix raisonnable.</span></li>
<li><span><b>Le serveur voit les métadonnées</b> : qui parle à qui, quand, et combien.</span></li>
<li><span><b>Ce n’est pas un VPN pour naviguer.</b> Il relie tes appareils entre eux ; ta navigation sur Internet ne passe pas par lui.</span></li>
<li><span><b>La clé du verrou n’a pas de secours</b> pour l’instant : perdre le téléphone de l’admin gèle les signatures. C’est le prochain gros sujet.</span></li>
</ul></div>
</div>
HTML
pied; } > "$D/html/limites.html"
rendre limites.html "$DOCS/schemas/limites.png"
