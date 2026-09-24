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
RUN apk add --no-cache nftables iproute2 ca-certificates
COPY --from=construction /sortie/ /usr/local/bin/
CMD ["sasd"]
