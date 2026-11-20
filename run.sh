#!/bin/bash
# Compila, instala em /Applications e reinicia o app.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

./build.sh

TARGET=/Applications/LetrasPiP.app
if [ ! -w /Applications ]; then
    TARGET="$HOME/Applications/LetrasPiP.app"
    mkdir -p "$HOME/Applications"
fi

pkill -f LetrasPiP.app 2>/dev/null || true
sleep 0.4
rm -rf "$TARGET"
cp -R build/LetrasPiP.app "$TARGET"
open "$TARGET"

echo "rodando: $TARGET"
