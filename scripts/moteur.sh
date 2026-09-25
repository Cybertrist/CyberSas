#!/bin/bash
# Compile le moteur Go (pont/) en bibliothèque Android pour l'appli :
# mobile/android/app/libs/moteur.aar, pour arm64 (téléphones) et x86_64
# (émulateur). À relancer après toute modification du code Go du client.
#
# Il faut Go, le SDK et le NDK Android (ANDROID_HOME, ANDROID_NDK_HOME).
# gomobile est déclaré comme outil dans go.mod : rien à installer.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p mobile/android/app/libs
go tool gomobile init
go tool gomobile bind -target=android/arm64,android/amd64 -androidapi 28 -javapkg=fr.cybersas \
  -trimpath -ldflags="-s -w" -o mobile/android/app/libs/moteur.aar ./pont
echo "moteur.aar prêt"
