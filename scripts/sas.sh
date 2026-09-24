#!/bin/bash
# CyberSas : tout ce qu'on fait sur la pile passe par ce script.
#
#   sas.sh init                      secrets, autorité du labo, configurations
#   sas.sh google <id> <secret>      le client OAuth créé dans Google Cloud
#   sas.sh membre <email> <groupe>   donne l'accès à un compte Google (admins ou equipe)
#   sas.sh retirer <email>           le lui retire
#   sas.sh demarrer                  lance la pile et inscrit le relais au VPN
#   sas.sh labo                      lance la fausse maison et le poste d'essai
#   sas.sh essai                     vérifie que tout répond comme prévu
#   sas.sh etat                      les appareils du VPN
#   sas.sh arreter                   arrête tout, sans rien effacer
#
# Tout ce qui est secret ou propre à une installation s'écrit dans etat/,
# qui n'est jamais versionné. etat/equipe.txt est la seule liste des
# personnes autorisées : le VPN et les services web la lisent tous deux.
set -euo pipefail

# Sous Git Bash, sans cela, « /CN=... » et « /secrets » deviendraient des
# chemins Windows.
export MSYS_NO_PATHCONV=1
# Pour la même raison, curl sous Windows ne connaît pas /dev/null.
NUL=/dev/null; [ -n "${MSYSTEM:-}" ] && NUL=NUL

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE"
# Relatif : openssl sous Git Bash ne lit pas les chemins /c/...
ETAT="etat"
EQUIPE="$ETAT/equipe.txt"
GOOGLE="$ETAT/secrets/google"
LABO=(docker compose -f labo/maison.yaml)

dit ()    { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok ()     { printf '  \033[32mok\033[0m  %s\n' "$*"; }
rate ()   { printf '  \033[31mKO\033[0m  %s\n' "$*"; ECHECS=$((ECHECS+1)); }
meurt ()  { printf '\033[31merreur :\033[0m %s\n' "$*" >&2; exit 1; }

charger_env () {
  [ -f .env ] || meurt ".env manquant : copier .env.exemple en .env et le remplir."
  set -a; . ./.env; set +a
  : "${DOMAINE:?DOMAINE manque dans .env}"
  PORT_HTTPS="${PORT_HTTPS:-443}"
}

# Champ d'un objet JSON sur une ligne, sans jq : assez pour lire ce que
# rendent headscale et tailscale.
champ () { grep -o "\"$1\": *\"\?[^\",}]*" | head -1 | sed 's/.*: *"\{0,1\}//'; }

hs () { docker compose exec -T headscale headscale "$@"; }
en_route () { docker compose ps --status running --services 2>/dev/null | grep -qx "$1"; }

# --- init -------------------------------------------------------------------

init_ca () {
  local ca="$ETAT/ca" tls="$ETAT/tls"
  mkdir -p "$ca/prive" "$ca/public" "$tls"
  if [ ! -f "$ca/public/cybersas-ca.pem" ]; then
    # nameConstraints : cette autorité ne peut signer que pour DOMAINE et
    # ses sous-domaines. Installée sur un téléphone, elle ne pourrait pas
    # servir à usurper un autre site.
    openssl req -x509 -new -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
      -keyout "$ca/prive/ca.key" -out "$ca/public/cybersas-ca.pem" -days 1825 \
      -subj "/O=CyberSas/CN=CyberSas Labo CA" \
      -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
      -addext "keyUsage=critical,keyCertSign,cRLSign" \
      -addext "nameConstraints=critical,permitted;DNS:$DOMAINE" 2>/dev/null
    ok "autorité du labo créée, limitée à $DOMAINE"
  fi
  if [ ! -f "$tls/fullchain.pem" ]; then
    openssl req -new -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
      -keyout "$tls/privkey.pem" -out "$tls/requete.csr" -subj "/CN=$DOMAINE" 2>/dev/null
    printf 'subjectAltName=DNS:%s,DNS:*.%s\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature\n' \
      "$DOMAINE" "$DOMAINE" > "$tls/extensions.cnf"
    openssl x509 -req -in "$tls/requete.csr" -CA "$ca/public/cybersas-ca.pem" -CAkey "$ca/prive/ca.key" \
      -CAcreateserial -out "$tls/serveur.pem" -days 397 -extfile "$tls/extensions.cnf" 2>/dev/null
    cat "$tls/serveur.pem" "$ca/public/cybersas-ca.pem" > "$tls/fullchain.pem"
    rm -f "$tls/requete.csr" "$tls/extensions.cnf"
    ok "certificat *.$DOMAINE signé"
  fi
}

init_secrets () {
  mkdir -p "$GOOGLE"
  # La clé qui chiffre le cookie de session. Lue dans un fichier,
  # oauth2-proxy la prend octet pour octet : 32 caractères, sans retour à
  # la ligne, soit une clé AES-256.
  [ -f "$GOOGLE/cookie_secret" ] || { printf '%s' "$(openssl rand -hex 16)" > "$GOOGLE/cookie_secret"; ok "clé des cookies"; }
  # Tant que le vrai client Google n'est pas là, des valeurs de réserve
  # laissent la pile démarrer : tout marche jusqu'à la page de Google.
  [ -f "$GOOGLE/client_id" ]     || { echo "a-remplir.apps.googleusercontent.com" > "$GOOGLE/client_id"; ok "client Google provisoire"; }
  [ -f "$GOOGLE/client_secret" ] || echo "a-remplir" > "$GOOGLE/client_secret"
}

# Écrit les configurations de etat/ à partir des modèles et de equipe.txt.
rendre () {
  mkdir -p "$ETAT/headscale" "$ETAT/oauth2-proxy"
  touch "$EQUIPE"
  local id; id="$(cat "$GOOGLE/client_id")"
  local mails admins equipe
  mails="$(awk 'NF>=2 && $1 !~ /^#/ {print $1}' "$EQUIPE")"
  # Dans la politique, une adresse email désigne son propriétaire.
  admins="$(awk 'NF>=2 && $2=="admins" {printf "%s\"%s\"", (n++?", ":""), $1}' "$EQUIPE")"
  equipe="$(awk 'NF>=2 && $2=="equipe" {printf "%s\"%s\"", (n++?", ":""), $1}' "$EQUIPE")"
  # Le poste d'essai du labo est un utilisateur local, sans compte Google.
  if [ "${TLS:-labo}" = labo ]; then equipe="${equipe:+$equipe, }\"essai@\""; fi

  printf '%s\n' "$mails" > "$ETAT/oauth2-proxy/emails.txt"
  local liste; liste="$(printf '%s\n' "$mails" | awk 'NF {print "    - \"" $1 "\""}')"
  [ -n "$liste" ] || liste='    - "personne@invalid"'
  awk -v d="$DOMAINE" -v i="$id" -v l="$liste" '
    $0 == "@UTILISATEURS@" { print l; next }
    { gsub(/@DOMAINE@/, d); gsub(/@GOOGLE_CLIENT_ID@/, i); print }' \
    headscale/config.yaml > "$ETAT/headscale/config.yaml"
  sed -e "s|@ADMINS@|$admins|" -e "s|@EQUIPE@|$equipe|" headscale/politique.hujson > "$ETAT/headscale/politique.hujson"
  sed -e "s|@DOMAINE@|$DOMAINE|g" -e "s|@GOOGLE_CLIENT_ID@|$id|g" oauth2-proxy/oauth2-proxy.cfg > "$ETAT/oauth2-proxy/oauth2-proxy.cfg"
}

# Après un changement d'accès : Headscale relit sa liste au démarrage,
# oauth2-proxy surveille la sienne.
appliquer () {
  rendre
  ok "configurations réécrites"
  if en_route headscale; then
    docker compose restart headscale oauth2-proxy >/dev/null 2>&1
    ok "Headscale et oauth2-proxy relancés"
  fi
}

cmd_init () {
  charger_env
  command -v docker >/dev/null || meurt "Docker est introuvable."
  dit "Autorité et certificat du labo"
  if [ "${TLS:-labo}" = labo ]; then init_ca; else ok "TLS=$TLS : rien à faire ici"; fi
  dit "Secrets"
  init_secrets
  dit "Accès"
  if [ ! -s "$EQUIPE" ] && [ -n "${ADMIN_EMAIL:-}" ]; then
    printf '# adresse Google        groupe (admins ou equipe)\n%s admins\n' "$ADMIN_EMAIL" > "$EQUIPE"
    ok "$ADMIN_EMAIL admin"
  fi
  rendre
  ok "configurations écrites dans etat/"
  dit "Prêt. Suite : bash scripts/sas.sh google <id> <secret>, puis demarrer"
}

# --- Google et accès ----------------------------------------------------------

cmd_google () {
  [ $# -eq 2 ] || meurt "usage : sas.sh google <client_id> <client_secret>"
  [[ "$1" == *.apps.googleusercontent.com ]] || meurt "un identifiant Google finit par .apps.googleusercontent.com"
  mkdir -p "$GOOGLE"
  printf '%s\n' "$1" > "$GOOGLE/client_id"
  printf '%s\n' "$2" > "$GOOGLE/client_secret"
  ok "client Google enregistré"
  appliquer
}

cmd_membre () {
  [ $# -eq 2 ] || meurt "usage : sas.sh membre <adresse google> <admins|equipe>"
  local mail="${1,,}" groupe="$2"
  case "$groupe" in admins|equipe) ;; *) meurt "groupe inconnu : $groupe (admins ou equipe)";; esac
  [[ "$mail" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[a-z]+$ ]] || meurt "adresse invalide : $mail"
  touch "$EQUIPE"
  awk -v m="$mail" '$1 != m' "$EQUIPE" > "$EQUIPE.tmp" && mv "$EQUIPE.tmp" "$EQUIPE"
  printf '%s %s\n' "$mail" "$groupe" >> "$EQUIPE"
  ok "$mail : $groupe"
  appliquer
}

cmd_retirer () {
  [ $# -eq 1 ] || meurt "usage : sas.sh retirer <adresse google>"
  local mail="${1,,}"
  grep -q "^$mail " "$EQUIPE" 2>/dev/null || meurt "$mail n'est pas dans l'équipe"
  awk -v m="$mail" '$1 != m' "$EQUIPE" > "$EQUIPE.tmp" && mv "$EQUIPE.tmp" "$EQUIPE"
  ok "$mail retiré"
  appliquer
  # Ses appareils déjà connectés restent inscrits : on les expire.
  if en_route headscale; then
    local ids
    ids="$(hs nodes list -o json 2>/dev/null | tr -d '\n' | sed 's/},{"id"/}\n{"id"/g' | grep -i "\"$mail\"" | grep -o '^{"id": *[0-9]*' | grep -o '[0-9]*$' || true)"
    for i in $ids; do hs nodes expire -i "$i" >/dev/null && ok "appareil $i déconnecté"; done
  fi
}

# --- démarrage ---------------------------------------------------------------

attendre_headscale () {
  local i
  for i in $(seq 1 60); do
    hs health >/dev/null 2>&1 && return 0
    sleep 2
  done
  docker compose logs --tail 30 headscale oauth2-proxy nginx
  meurt "Headscale ne répond pas après deux minutes."
}

# Inscrit un nœud s'il ne l'est pas déjà. $1 : commande compose, $2 : service,
# $3 : clé d'inscription.
inscrire () {
  local -n compose=$1
  local svc="$2"
  if "${compose[@]}" exec -T "$svc" tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
    ok "$svc déjà dans le VPN"; return
  fi
  local cle; cle="$($3)"
  [ -n "$cle" ] || meurt "pas de clé pour $svc"
  # --accept-dns=false : le conteneur garde le DNS de Docker, sans quoi il
  # ne trouverait plus hs.DOMAINE. Le résolveur du VPN reste joignable
  # à 100.100.100.100.
  "${compose[@]}" exec -T "$svc" tailscale up --login-server="https://hs.$DOMAINE" \
    --authkey="$cle" --hostname="$svc" --accept-dns=false --timeout=60s
  ok "$svc inscrit"
}

cle_etiquette () { hs preauthkeys create --tags "$1" --expiration 10m -o json | champ key; }
cle_relais () { cle_etiquette tag:relais; }
cle_maison () { cle_etiquette tag:maison; }
cle_poste () {
  hs users create essai >/dev/null 2>&1 || true
  local id
  id="$(hs users list -o json | tr -d '\n' | sed 's/},/}\n/g' | grep '"name": *"essai"' | champ id)"
  hs preauthkeys create --user "$id" --expiration 10m -o json | champ key
}

cmd_demarrer () {
  charger_env
  [ -f "$ETAT/headscale/config.yaml" ] || meurt "lancer d'abord : bash scripts/sas.sh init"
  dit "Démarrage de la pile"
  docker compose up -d
  attendre_headscale
  ok "Headscale répond"
  local PILE=(docker compose)
  inscrire PILE relais cle_relais
  dit "En ligne : https://auth.$DOMAINE  https://hs.$DOMAINE  https://maison.$DOMAINE"
}

cmd_labo () {
  charger_env
  dit "Démarrage du labo"
  "${LABO[@]}" up -d
  inscrire LABO maison cle_maison
  inscrire LABO poste cle_poste
}

# --- essais -----------------------------------------------------------------

cmd_essai () {
  charger_env
  ECHECS=0
  # --ssl-no-revoke : le curl de Windows (Schannel) exige sinon une liste de
  # révocation que l'autorité du labo ne publie pas. Ignoré ailleurs.
  local c=(curl -s -o "$NUL" -w '%{http_code}' --max-time 10 --ssl-no-revoke --cacert "$ETAT/ca/public/cybersas-ca.pem")
  local r="--resolve"
  local code

  dit "Depuis Internet"
  code="$("${c[@]}" $r "hs.$DOMAINE:$PORT_HTTPS:127.0.0.1" "https://hs.$DOMAINE:$PORT_HTTPS/health" || true)"
  [ "$code" = 200 ] && ok "hs.$DOMAINE/health répond 200" || rate "hs.$DOMAINE/health : $code"

  # L'adresse vers laquelle une page renvoie, sans la suivre.
  lieu () {
    curl -s -D - -o "$NUL" --max-time 10 --ssl-no-revoke --cacert "$ETAT/ca/public/cybersas-ca.pem" \
      --resolve "$1.$DOMAINE:$PORT_HTTPS:127.0.0.1" "$2" 2>/dev/null | tr -d '\r' | sed -n 's/^[Ll]ocation: //p' || true
  }

  code="$("${c[@]}" $r "auth.$DOMAINE:$PORT_HTTPS:127.0.0.1" "https://auth.$DOMAINE:$PORT_HTTPS/ping" || true)"
  [ "$code" = 200 ] && ok "le portail de connexion répond" || rate "auth.$DOMAINE/ping : $code"

  local loc
  loc="$(lieu maison "https://maison.$DOMAINE:$PORT_HTTPS/")"
  [[ "$loc" == "https://auth.$DOMAINE/oauth2/start?rd=https://maison.$DOMAINE"* ]] \
    && ok "maison.$DOMAINE renvoie vers la connexion" || rate "maison.$DOMAINE sans session : ${loc:-pas de renvoi}"

  loc="$(lieu auth "https://auth.$DOMAINE:$PORT_HTTPS/oauth2/start?rd=https://maison.$DOMAINE/")"
  [[ "$loc" == "https://accounts.google.com/"*"code_challenge_method=S256"* ]] \
    && ok "la connexion part chez Google, avec PKCE" || rate "auth.$DOMAINE/oauth2/start : ${loc:-pas de renvoi}"

  code="$(curl -sk -o "$NUL" -w '%{http_code}' --max-time 5 --resolve "inconnu.test:$PORT_HTTPS:127.0.0.1" "https://inconnu.test:$PORT_HTTPS/" || true)"
  [ "$code" = 000 ] && ok "un nom inconnu n'obtient même pas de certificat" || rate "nom inconnu : $code, coupure attendue"

  code="$(curl -s -o "$NUL" -w '%{http_code}' --max-time 5 --resolve "hs.$DOMAINE:${PORT_HTTP:-80}:127.0.0.1" "http://hs.$DOMAINE:${PORT_HTTP:-80}/" || true)"
  [ "$code" = 301 ] && ok "le HTTP en clair est redirigé" || rate "HTTP : $code, 301 attendu"

  dit "Dans le VPN"
  local maison
  maison="$("${LABO[@]}" exec -T poste tailscale ip -4 maison 2>/dev/null | tr -d '\r' || true)"
  [ -n "$maison" ] && ok "le poste voit maison ($maison)" || rate "le poste ne trouve pas maison"

  # Le relais garde le DNS de Docker : son nom VPN se demande au résolveur du
  # VPN, comme le fait Nginx.
  local nom
  nom="$(docker compose exec -T relais nslookup maison.sas.internal 100.100.100.100 2>/dev/null \
         | sed -n 's/^Address: *\(100\.[0-9.]*\).*/\1/p' | head -1)"
  if [ -n "$nom" ] && docker compose exec -T relais wget -qO- -T 5 "http://$nom/" 2>/dev/null | grep -q Hostname; then
    ok "le relais trouve maison.sas.internal ($nom) et atteint son service"
  else rate "le relais n'atteint pas maison.sas.internal"; fi

  if "${LABO[@]}" exec -T poste wget -qO- -T 5 "http://$maison/" 2>/dev/null | grep -q Hostname; then
    ok "l'équipe atteint le service web de la maison"
  else rate "le poste n'atteint pas maison:80"; fi

  if "${LABO[@]}" exec -T poste wget -qO- -T 5 "http://$maison:8080/" >/dev/null 2>&1; then
    rate "le poste atteint maison:8080, que la politique réserve aux admins"
  else ok "maison:8080 reste fermé à l'équipe"; fi

  local poste
  poste="$("${LABO[@]}" exec -T poste tailscale ip -4 2>/dev/null | head -1 | tr -d '\r' || true)"
  if "${LABO[@]}" exec -T maison wget -qO- -T 5 "http://$poste:80/" >/dev/null 2>&1 \
     || "${LABO[@]}" exec -T maison ping -c1 -W3 "$poste" >/dev/null 2>&1; then
    rate "maison atteint le poste : elle ne devrait rien pouvoir ouvrir"
  else ok "maison ne peut pas se retourner vers le poste"; fi


  dit "Rejoindre le VPN"
  # Un appareil neuf, sans clé : Headscale doit l'envoyer chez Google.
  docker run -d --rm --name sas-essai-oidc --network cybersas_public --cap-add NET_ADMIN \
    --device /dev/net/tun -e SSL_CERT_DIR=/etc/ssl/certs:/ca -v "$(cd "$ETAT/ca/public" && pwd -W 2>/dev/null || pwd):/ca:ro" \
    tailscale/tailscale:v1.102.4 tailscaled --state=mem: >/dev/null
  sleep 3
  local url
  url="$(docker exec sas-essai-oidc tailscale up --login-server="https://hs.$DOMAINE" --accept-dns=false --timeout=8s 2>&1 \
         | grep -o "https://hs\.$DOMAINE/register/[^ ]*" | head -1 || true)"
  docker rm -f sas-essai-oidc >/dev/null 2>&1 || true
  loc="$(lieu hs "${url/hs.$DOMAINE/hs.$DOMAINE:$PORT_HTTPS}")"
  [[ "$loc" == "https://accounts.google.com/"*"code_challenge_method=S256"* ]] \
    && ok "un nouvel appareil est envoyé chez Google, avec PKCE" || rate "pas de renvoi vers Google (${loc:-rien})"

  echo
  [ "$ECHECS" -eq 0 ] && dit "Tout est conforme." || meurt "$ECHECS vérification(s) en échec."
}

# --- divers -----------------------------------------------------------------

cmd_etat ()      { charger_env; hs nodes list; }
cmd_arreter ()   { charger_env; "${LABO[@]}" down 2>/dev/null || true; docker compose down; }

c="${1:-}"; shift || true
case "$c" in
  init) cmd_init ;;
  google) charger_env; cmd_google "$@" ;;
  membre) charger_env; cmd_membre "$@" ;;
  retirer) charger_env; cmd_retirer "$@" ;;
  demarrer) cmd_demarrer ;;
  labo) cmd_labo ;;
  essai) cmd_essai ;;
  etat) cmd_etat ;;
  arreter) cmd_arreter ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
