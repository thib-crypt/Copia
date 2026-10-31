#!/bin/zsh
# Compile en Release, installe dans /Applications et relance Copia.
set -e
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Copia.xcodeproj -scheme Copia -configuration Release -derivedDataPath build/DD build | grep -E "error:|BUILD" || true
pkill -x Copia 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Copia.app
cp -R build/DD/Build/Products/Release/Copia.app /Applications/
open /Applications/Copia.app
echo "Copia installé et lancé."
