#!/bin/bash
# CyberSas : tout ce qu'on fait sur la pile passe par ce script.
#
#   sas.sh init                              secrets, autorité du labo, configurations
#   sas.sh utilisateur <login> <email> <nom> <groupe>
#                                            crée un compte, ou refait son mot de passe
#   sas.sh demarrer                          lance la pile et inscrit le relais au VPN
#   sas.sh labo                              lance la fausse maison et le poste d'essai
#   sas.sh essai                             vérifie que tout répond comme prévu
#   sas.sh politique                         recharge les règles d'accès du VPN
#   sas.sh etat                              les appareils du VPN
#   sas.sh arreter                           arrête tout, sans rien effacer
#
# Tout ce qui est secret ou propre à une installation s'écrit dans etat/,
# qui n'est jamais versionné.
set -euo pipefail

# Sous Git Bash, sans cela, « /CN=... » et « /secrets » deviendraient des
# chemins Windows.
export MSYS_NO_PATHCONV=1

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RACINE"
ETAT="$RACINE/etat"
AUTHELIA_IMAGE="authelia/authelia:4.39.28"
LABO=(docker compose -f labo/maison.yaml)

dit ()    { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok ()     { printf '  \033[32mok\033[0m  %s\n' "$*"; }
rate ()   { printf '  \033[31mKO\033[0m  %s\n' "$*"; ECHECS=$((ECHECS+1)); }
meurt ()  { printf '\033[31merreur :\033[0m %s\n' "$*" >&2; exit 1; }
alea ()   { openssl rand -hex "${1:-32}"; }

charger_env () {
  [ -f .env ] || meurt ".env manquant : copier .env.exemple en .env et le remplir."
  set -a; . ./.env; set +a
  : "${DOMAINE:?DOMAINE manque dans .env}"
  PORT_HTTPS="${PORT_HTTPS:-443}"
}

# Empreinte d'un secret, calculée par Authelia elle-même : on n'a pas à
# réimplémenter pbkdf2 ou argon2.
empreinte () {
  docker run --rm "$AUTHELIA_IMAGE" authelia crypto hash generate "$1" ${3:-} --password "$2" \
    | sed -n 's/^Digest: //p'
}

# Champ d'un objet JSON sur une ligne, sans jq : assez pour lire ce que
# rendent headscale et tailscale.
champ () { grep -o "\"$1\": *\"\?[^\",}]*" | head -1 | sed 's/.*: *"\{0,1\}//'; }

hs () { docker compose exec -T headscale headscale "$@"; }

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
  local a="$ETAT/secrets/authelia" h="$ETAT/secrets/headscale"
  mkdir -p "$a" "$h"
  for s in session stockage jwt oidc_hmac; do
    [ -f "$a/$s" ] || { alea > "$a/$s"; ok "secret Authelia : $s"; }
  done
  [ -f "$a/oidc_jwks.pem" ] || { openssl genrsa -out "$a/oidc_jwks.pem" 4096 2>/dev/null; ok "clé de signature OIDC"; }
  # Headscale garde le secret en clair, Authelia n'en garde que l'empreinte.
  if [ ! -f "$h/oidc_client_secret" ]; then
    alea 48 > "$h/oidc_client_secret"
    empreinte pbkdf2 "$(cat "$h/oidc_client_secret")" "--variant sha512" > "$a/headscale_oidc_empreinte"
    [ -s "$a/headscale_oidc_empreinte" ] || meurt "Authelia n'a pas rendu d'empreinte (Docker tourne ?)"
    ok "secret du client OIDC Headscale"
  fi
}

cmd_init () {
  charger_env
  command -v docker >/dev/null || meurt "Docker est introuvable."
  dit "Autorité et certificat du labo"
  if [ "${TLS:-labo}" = labo ]; then init_ca; else ok "TLS=$TLS : rien à faire ici"; fi
  dit "Secrets"
  init_secrets
  dit "Configurations"
  mkdir -p "$ETAT/headscale" "$ETAT/authelia"
  sed "s/@DOMAINE@/$DOMAINE/g" headscale/config.yaml > "$ETAT/headscale/config.yaml"
  ok "etat/headscale/config.yaml"
  if [ ! -f "$ETAT/authelia/utilisateurs.yml" ]; then
    : "${ADMIN_LOGIN:?ADMIN_LOGIN manque dans .env}" "${ADMIN_EMAIL:?ADMIN_EMAIL manque dans .env}"
    printf 'users:\n' > "$ETAT/authelia/utilisateurs.yml"
    cmd_utilisateur "$ADMIN_LOGIN" "$ADMIN_EMAIL" "${ADMIN_NOM:-$ADMIN_LOGIN}" admins
  fi
  dit "Prêt. Suite : bash scripts/sas.sh demarrer"
}

# --- utilisateurs -----------------------------------------------------------

cmd_utilisateur () {
  [ $# -eq 4 ] || meurt "usage : sas.sh utilisateur <login> <email> <nom> <admins|equipe>"
  local login="$1" email="$2" nom="$3" groupe="$4" f="$ETAT/authelia/utilisateurs.yml"
  case "$groupe" in admins|equipe) ;; *) meurt "groupe inconnu : $groupe (admins ou equipe)";; esac
  [[ "$login" =~ ^[a-z][a-z0-9._-]*$ ]] || meurt "login : minuscules, chiffres, . _ -"
  [ -f "$f" ] || printf 'users:\n' > "$f"
  local mdp; mdp="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"
  local hash; hash="$(empreinte argon2 "$mdp")"
  [ -n "$hash" ] || meurt "Authelia n'a pas rendu d'empreinte (Docker tourne ?)"
  # Retire l'ancien bloc du même login, puis écrit le nouveau.
  awk -v l="  $login:" '$0==l{skip=1;next} skip && /^  [^ ]/{skip=0} !skip' "$f" > "$f.tmp"
  cat >> "$f.tmp" <<EOF
  $login:
    disabled: false
    displayname: '$nom'
    email: '$email'
    password: '$hash'
    groups: ['$groupe']
EOF
  mv "$f.tmp" "$f"
  ok "compte $login ($groupe)"
  printf '\n     mot de passe provisoire : \033[1m%s\033[0m\n' "$mdp"
  printf '     il ne sera plus jamais affiché. Le second facteur se règle à la première connexion.\n'
  printf '     Pour le VPN, ajouter aussi « %s@ » dans group:%s de headscale/politique.hujson.\n\n' "$login" "$groupe"
}

# --- démarrage ---------------------------------------------------------------

attendre_headscale () {
  local i
  for i in $(seq 1 60); do
    hs health >/dev/null 2>&1 && return 0
    sleep 2
  done
  docker compose logs --tail 30 headscale authelia nginx
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
  local c=(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --cacert "$ETAT/ca/public/cybersas-ca.pem")
  local r="--resolve"
  local code

  dit "Depuis Internet"
  code="$("${c[@]}" $r "hs.$DOMAINE:$PORT_HTTPS:127.0.0.1" "https://hs.$DOMAINE:$PORT_HTTPS/health" || true)"
  [ "$code" = 200 ] && ok "hs.$DOMAINE/health répond 200" || rate "hs.$DOMAINE/health : $code"

  code="$("${c[@]}" $r "auth.$DOMAINE:$PORT_HTTPS:127.0.0.1" "https://auth.$DOMAINE:$PORT_HTTPS/api/health" || true)"
  [ "$code" = 200 ] && ok "le portail Authelia répond" || rate "auth.$DOMAINE/api/health : $code"

  code="$("${c[@]}" $r "maison.$DOMAINE:$PORT_HTTPS:127.0.0.1" "https://maison.$DOMAINE:$PORT_HTTPS/" || true)"
  [ "$code" = 302 ] && ok "maison.$DOMAINE renvoie vers la connexion (302)" || rate "maison.$DOMAINE sans session : $code, 302 attendu"

  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 --resolve "inconnu.test:$PORT_HTTPS:127.0.0.1" "https://inconnu.test:$PORT_HTTPS/" || true)"
  [ "$code" = 000 ] && ok "un nom inconnu n'obtient même pas de certificat" || rate "nom inconnu : $code, coupure attendue"

  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 --resolve "hs.$DOMAINE:${PORT_HTTP:-80}:127.0.0.1" "http://hs.$DOMAINE:${PORT_HTTP:-80}/" || true)"
  [ "$code" = 301 ] && ok "le HTTP en clair est redirigé" || rate "HTTP : $code, 301 attendu"

  dit "Dans le VPN"
  local maison
  maison="$("${LABO[@]}" exec -T poste tailscale ip -4 maison 2>/dev/null | tr -d '\r' || true)"
  [ -n "$maison" ] && ok "le poste voit maison ($maison)" || rate "le poste ne trouve pas maison"

  if docker compose exec -T relais wget -qO- -T 5 http://maison.sas.internal/ 2>/dev/null | grep -q Hostname; then
    ok "le relais atteint le service de la maison par son nom"
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

  echo
  [ "$ECHECS" -eq 0 ] && dit "Tout est conforme." || meurt "$ECHECS vérification(s) en échec."
}

# --- divers -----------------------------------------------------------------

cmd_politique () { charger_env; docker compose kill -s HUP headscale >/dev/null; sleep 2; docker compose logs --tail 5 headscale; }
cmd_etat ()      { charger_env; hs nodes list; }
cmd_arreter ()   { charger_env; "${LABO[@]}" down 2>/dev/null || true; docker compose down; }

c="${1:-}"; shift || true
case "$c" in
  init) cmd_init ;;
  utilisateur) charger_env; cmd_utilisateur "$@" ;;
  demarrer) cmd_demarrer ;;
  labo) cmd_labo ;;
  essai) cmd_essai ;;
  politique) cmd_politique ;;
  etat) cmd_etat ;;
  arreter) cmd_arreter ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
