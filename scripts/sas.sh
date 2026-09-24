#!/bin/bash
# CyberSas : tout ce qu'on fait sur la pile passe par ce script.
#
#   sas.sh init                      secrets, autorité du labo, configurations
#   sas.sh google <id> <secret>      le client OAuth créé dans Google Cloud
#   sas.sh membre <email> <groupe>   donne l'accès à un compte Google (admins ou equipe)
#   sas.sh retirer <email>           le lui retire
#   sas.sh demarrer                  construit et lance la pile
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
# sasd relit les siennes toutes les cinq secondes, oauth2-proxy surveille
# sa liste : aucun redémarrage n'est nécessaire après un changement.
rendre () {
  mkdir -p "$ETAT/sasd" "$ETAT/oauth2-proxy"
  touch "$EQUIPE"
  local id; id="$(cat "$GOOGLE/client_id")"
  awk 'NF>=2 && $1 !~ /^#/ {print $1}' "$EQUIPE" > "$ETAT/oauth2-proxy/emails.txt"
  # Le poste d'essai du labo s'inscrit avec une clé, sans compte Google.
  { cat "$EQUIPE"; [ "${TLS:-labo}" = labo ] && echo "essai@labo.local equipe"; } > "$ETAT/sasd/equipe.txt.tmp"
  mv "$ETAT/sasd/equipe.txt.tmp" "$ETAT/sasd/equipe.txt"
  printf '%s\n' "$id" > "$ETAT/sasd/clients_google"
  sed -e "s|@DOMAINE@|$DOMAINE|g" -e "s|@GOOGLE_CLIENT_ID@|$id|g" oauth2-proxy/oauth2-proxy.cfg > "$ETAT/oauth2-proxy/oauth2-proxy.cfg"
}

sasd () { docker compose exec -T sasd sasd "$@"; }

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
  dit "Prêt. Suite : bash scripts/sas.sh demarrer"
}

# --- Google et accès ----------------------------------------------------------

cmd_google () {
  [ $# -eq 2 ] || meurt "usage : sas.sh google <client_id> <client_secret>"
  [[ "$1" == *.apps.googleusercontent.com ]] || meurt "un identifiant Google finit par .apps.googleusercontent.com"
  mkdir -p "$GOOGLE"
  printf '%s\n' "$1" > "$GOOGLE/client_id"
  printf '%s\n' "$2" > "$GOOGLE/client_secret"
  rendre
  ok "client Google enregistré"
  # oauth2-proxy ne relit son identifiant qu'au démarrage.
  en_route oauth2-proxy && docker compose restart oauth2-proxy >/dev/null 2>&1 && ok "oauth2-proxy relancé" || true
}

cmd_membre () {
  [ $# -eq 2 ] || meurt "usage : sas.sh membre <adresse google> <admins|equipe>"
  local mail="${1,,}" groupe="$2"
  case "$groupe" in admins|equipe) ;; *) meurt "groupe inconnu : $groupe (admins ou equipe)";; esac
  [[ "$mail" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[a-z]+$ ]] || meurt "adresse invalide : $mail"
  touch "$EQUIPE"
  awk -v m="$mail" '$1 != m' "$EQUIPE" > "$EQUIPE.tmp" && mv "$EQUIPE.tmp" "$EQUIPE"
  printf '%s %s\n' "$mail" "$groupe" >> "$EQUIPE"
  rendre
  ok "$mail : $groupe, pris en compte d'ici cinq secondes"
}

cmd_retirer () {
  [ $# -eq 1 ] || meurt "usage : sas.sh retirer <adresse google>"
  local mail="${1,,}"
  grep -q "^$mail " "$EQUIPE" 2>/dev/null || meurt "$mail n'est pas dans l'équipe"
  awk -v m="$mail" '$1 != m' "$EQUIPE" > "$EQUIPE.tmp" && mv "$EQUIPE.tmp" "$EQUIPE"
  rendre
  # sasd purge lui-même les appareils d'une personne sortie de l'équipe.
  ok "$mail retiré : ses appareils sont coupés d'ici cinq secondes"
}

# --- démarrage ---------------------------------------------------------------

attendre_sasd () {
  local i
  for i in $(seq 1 60); do
    docker compose exec -T sasd wget -qO- http://127.0.0.1:8080/api/v1/sante >/dev/null 2>&1 && return 0
    sleep 2
  done
  docker compose logs --tail 30 sasd nginx
  meurt "sasd ne répond pas après deux minutes."
}

# Inscrit une machine du labo si elle ne l'est pas déjà.
inscrire () {
  local svc="$1"; shift
  if "${LABO[@]}" exec -T "$svc" sas etat >/dev/null 2>&1; then
    ok "$svc déjà dans le VPN"; return
  fi
  local cle; cle="$(sasd cle "$@" | tr -d '\r')"
  [ -n "$cle" ] || meurt "pas de clé pour $svc"
  "${LABO[@]}" exec -T "$svc" sas rejoindre --serveur "https://vpn.$DOMAINE" --cle "$cle" --nom "$svc" | sed 's/^/  /'
}

cmd_demarrer () {
  charger_env
  [ -f "$ETAT/sasd/equipe.txt" ] || meurt "lancer d'abord : bash scripts/sas.sh init"
  dit "Construction et démarrage de la pile"
  docker compose up -d --build
  attendre_sasd
  ok "sasd répond"
  dit "En ligne : https://vpn.$DOMAINE  https://auth.$DOMAINE  https://maison.$DOMAINE"
}

cmd_labo () {
  charger_env
  dit "Démarrage du labo"
  "${LABO[@]}" up -d
  inscrire maison --etiquette maison
  inscrire poste --utilisateur essai@labo.local
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

  # L'adresse vers laquelle une page renvoie, sans la suivre.
  lieu () {
    curl -s -D - -o "$NUL" --max-time 10 --ssl-no-revoke --cacert "$ETAT/ca/public/cybersas-ca.pem" \
      --resolve "$1.$DOMAINE:$PORT_HTTPS:127.0.0.1" "$2" 2>/dev/null | tr -d '\r' | sed -n 's/^[Ll]ocation: //p' || true
  }
  # Code HTTP d'un appel à l'API, avec un corps JSON éventuel.
  api () {
    curl -s -o "$NUL" -w '%{http_code}' --max-time 10 --ssl-no-revoke --cacert "$ETAT/ca/public/cybersas-ca.pem" \
      --resolve "vpn.$DOMAINE:$PORT_HTTPS:127.0.0.1" -H 'Content-Type: application/json' "$@" || true
  }
  local V="https://vpn.$DOMAINE:$PORT_HTTPS"
  # Une vraie clé publique X25519, tirée pour l'essai.
  local CLE; CLE="$(openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | base64)"
  local NULLE="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  dit "Depuis Internet"
  code="$("${c[@]}" $r "vpn.$DOMAINE:$PORT_HTTPS:127.0.0.1" "$V/api/v1/sante" || true)"
  [ "$code" = 200 ] && ok "l'API du VPN répond" || rate "vpn.$DOMAINE/api/v1/sante : $code"

  code="$("${c[@]}" $r "auth.$DOMAINE:$PORT_HTTPS:127.0.0.1" "https://auth.$DOMAINE:$PORT_HTTPS/ping" || true)"
  [ "$code" = 200 ] && ok "le portail de connexion répond" || rate "auth.$DOMAINE/ping : $code"

  local loc
  loc="$(lieu maison "https://maison.$DOMAINE:$PORT_HTTPS/")"
  [[ "$loc" == "https://auth.$DOMAINE/oauth2/start?rd=https://maison.$DOMAINE"* ]] \
    && ok "maison.$DOMAINE renvoie vers la connexion" || rate "maison.$DOMAINE sans session : ${loc:-pas de renvoi}"

  loc="$(lieu auth "https://auth.$DOMAINE:$PORT_HTTPS/oauth2/start?rd=https://maison.$DOMAINE/")"
  [[ "$loc" == "https://accounts.google.com/"*"code_challenge_method=S256"* ]] \
    && ok "la connexion web part chez Google, avec PKCE" || rate "auth.$DOMAINE/oauth2/start : ${loc:-pas de renvoi}"

  code="$(curl -sk -o "$NUL" -w '%{http_code}' --max-time 5 --resolve "inconnu.test:$PORT_HTTPS:127.0.0.1" "https://inconnu.test:$PORT_HTTPS/" || true)"
  [ "$code" = 000 ] && ok "un nom inconnu n'obtient même pas de certificat" || rate "nom inconnu : $code, coupure attendue"

  code="$(curl -s -o "$NUL" -w '%{http_code}' --max-time 5 --resolve "vpn.$DOMAINE:${PORT_HTTP:-80}:127.0.0.1" "http://vpn.$DOMAINE:${PORT_HTTP:-80}/" || true)"
  [ "$code" = 301 ] && ok "le HTTP en clair est redirigé" || rate "HTTP : $code, 301 attendu"

  dit "L'API refuse ce qu'elle doit refuser"
  code="$(api -X POST -d "{\"jeton_google\":\"eyJ.faux.jeton\",\"cle_publique\":\"$CLE\",\"nom\":\"x\"}" "$V/api/v1/connexion")"
  [ "$code" = 401 ] && ok "un faux jeton Google est refusé (401)" || rate "faux jeton Google : $code"
  code="$(api -X POST -d "{\"cle_inscription\":\"sas-inventee\",\"cle_publique\":\"$CLE\",\"nom\":\"x\"}" "$V/api/v1/connexion")"
  [ "$code" = 401 ] && ok "une clé d'inscription inventée est refusée (401)" || rate "clé inventée : $code"
  code="$(api "$V/api/v1/appareils")"
  [ "$code" = 401 ] && ok "la liste des appareils demande un jeton (401)" || rate "appareils sans jeton : $code"
  local cle; cle="$(sasd cle --etiquette essai | tr -d '\r')"
  code="$(api -X POST -d "{\"cle_inscription\":\"$cle\",\"cle_publique\":\"$NULLE\",\"nom\":\"x\"}" "$V/api/v1/connexion")"
  [ "$code" = 400 ] && ok "une clé publique faible (nulle) est refusée (400)" || rate "clé nulle : $code"
  api -X POST -d "{\"cle_inscription\":\"$cle\",\"cle_publique\":\"$CLE\",\"nom\":\"jetable\"}" "$V/api/v1/connexion" >/dev/null
  code="$(api -X POST -d "{\"cle_inscription\":\"$cle\",\"cle_publique\":\"$CLE\",\"nom\":\"jetable\"}" "$V/api/v1/connexion")"
  [ "$code" = 401 ] && ok "une clé d'inscription ne sert qu'une fois" || rate "clé réutilisée : $code"
  sasd retirer jetable >/dev/null 2>&1 || true

  dit "Dans le VPN, par notre tunnel"
  local maison
  maison="$("${LABO[@]}" exec -T poste sas appareils 2>/dev/null | awk '$1=="maison" {print $2}' | tr -d '\r' || true)"
  [ -n "$maison" ] && ok "le poste voit maison ($maison) dans sa liste" || rate "le poste ne voit pas maison"

  # Si le serveur vient de redémarrer, les appareils ont perdu leur session
  # et doivent s'en apercevoir seuls. On leur laisse une minute.
  local t0=$SECONDS joint=""
  while [ $((SECONDS - t0)) -lt 60 ]; do
    if "${LABO[@]}" exec -T poste wget -qO- -T 2 "http://$maison/" >/dev/null 2>&1 \
       && docker compose exec -T sasd wget -qO- -T 2 "http://$maison/" >/dev/null 2>&1; then joint=1; break; fi
    sleep 1
  done
  [ -n "$joint" ] && ok "tous les appareils sont joignables (en $((SECONDS - t0)) s)" || rate "des appareils restent injoignables après une minute"

  local nom
  nom="$(docker compose exec -T sasd nslookup maison.sas.internal 10.77.0.1 2>/dev/null \
         | sed -n 's/^Address: *\(10\.[0-9.]*\).*/\1/p' | head -1 || true)"
  if [ -n "$nom" ] && docker compose exec -T sasd wget -qO- -T 5 "http://$nom/" 2>/dev/null | grep -q Hostname; then
    ok "le serveur trouve maison.sas.internal ($nom) et atteint son service"
  else rate "le serveur n'atteint pas maison.sas.internal"; fi

  if "${LABO[@]}" exec -T poste wget -qO- -T 5 "http://$maison/" 2>/dev/null | grep -q Hostname; then
    ok "l'équipe atteint le service web de la maison"
  else rate "le poste n'atteint pas maison:80"; fi

  if "${LABO[@]}" exec -T poste wget -qO- -T 5 "http://$maison:8080/" >/dev/null 2>&1; then
    rate "le poste atteint maison:8080, que la politique ne lui donne pas"
  else ok "maison:8080 reste fermé à l'équipe"; fi

  local poste
  poste="$("${LABO[@]}" exec -T poste sas etat 2>/dev/null | awk '{print $2}' | tr -d '\r' || true)"
  if "${LABO[@]}" exec -T maison wget -qO- -T 5 "http://$poste:80/" >/dev/null 2>&1 \
     || "${LABO[@]}" exec -T maison ping -c1 -W3 "$poste" >/dev/null 2>&1; then
    rate "maison atteint le poste : elle ne devrait rien pouvoir ouvrir"
  else ok "maison ne peut pas se retourner vers le poste"; fi

  if docker compose exec -T sasd sh -c "nft list chain inet cybersas depuis_vpn" 2>/dev/null | grep -q "counter packets [1-9]"; then
    ok "le pare-feu du serveur a bien bloqué des paquets"
  else rate "le compteur de refus du pare-feu est resté à zéro"; fi

  dit "Retirer un appareil le coupe"
  sasd retirer poste >/dev/null
  sleep 7
  if "${LABO[@]}" exec -T poste wget -qO- -T 5 "http://$maison/" >/dev/null 2>&1; then
    rate "le poste retiré atteint encore la maison"
  else ok "le poste retiré n'atteint plus rien"; fi
  # On le remet, pour que l'essai puisse se relancer.
  "${LABO[@]}" exec -T poste rm -f /var/lib/sas/etat.json
  inscrire poste --utilisateur essai@labo.local >/dev/null

  echo
  [ "$ECHECS" -eq 0 ] && dit "Tout est conforme." || meurt "$ECHECS vérification(s) en échec."
}

# --- divers -----------------------------------------------------------------

cmd_etat ()      { charger_env; sasd appareils; }
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
