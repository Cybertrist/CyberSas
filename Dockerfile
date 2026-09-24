# Une seule image pour le serveur (sasd) et le client Linux (sas).
FROM golang:1.27.1-alpine3.24@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS construction
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /sortie/sasd ./cmd/sasd \
 && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /sortie/sas ./cmd/sas

FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
# nftables pour le pare-feu du serveur, iproute2 pour monter l'interface.
# Versions fixées à la révision près du correctif : une mise à jour de
# sécurité d'Alpine passe, un changement de version non.
RUN apk add --no-cache nftables~=1.1.6 iproute2~=7.0.0 ca-certificates~=20260909
COPY --from=construction /sortie/ /usr/local/bin/
# Pas de USER : sasd et sas montent une interface réseau et écrivent des
# règles nftables. Sous un autre utilisateur, les capacités données par
# compose (cap_add) ne seraient pas effectives, et no-new-privileges
# interdit les capacités posées sur le fichier. Le root du conteneur n'a
# que les capacités listées dans compose.yaml, tout le reste est retiré.
#
# Pas de HEALTHCHECK ici : la même image sert au client sas, qui n'a pas
# d'API. La vérification de sasd est dans compose.yaml.
CMD ["sasd"]
