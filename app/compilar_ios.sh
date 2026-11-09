#!/usr/bin/env bash
# Compila GeoMaps para iOS y la sube a TestFlight. Se corre en el MAC PRO (ahi
# estan la firma del equipo G4M5669P37 y la llave .p8 de App Store Connect).
# App «GeoMaps Sirius», Apple ID 6832715504, bundle net.meshtrama.geomaps. Ver docs/IOS.md.
#
#   ./compilar_ios.sh 10        <- numero de build (subilo en cada entrega)
#
# No cambies la VERSION de pubspec.yaml para esto: Apple aprueba la revision
# externa por version, y con la misma version las builds nuevas salen en
# minutos. Solo cambia el build.
# Se sube con altool (audiencia App Store). NUNCA con "TestFlight Internal Only"
# del Organizer: esa build despues no se puede mandar a pruebas externas.
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${1:?Uso: $0 <numero de build>}"
KEY_ID=L87262Y77T
ISSUER=5b50c44f-6315-4ec3-9c22-e811470b8fbf
# GeoMaps pide Dart ^3.13; el Flutter de Homebrew de este Mac es mas viejo y lo
# usan otros proyectos. Este es un SDK aparte, solo para GeoMaps.
FLUTTER="${FLUTTER:-$HOME/flutter-stable/bin/flutter}"

[ -f dart_defines.json ] || { echo "✗ falta dart_defines.json (copiar dart_defines.example.json y llenar)"; exit 1; }

# --enforce-lockfile: el mismo pubspec.lock que el APK, sin re-resolver.
"$FLUTTER" pub get --enforce-lockfile
"${FLUTTER%flutter}dart" run build_runner build --delete-conflicting-outputs
"$FLUTTER" build ipa --release --build-number="$BUILD" --dart-define-from-file=dart_defines.json
IPA=$(ls build/ios/ipa/*.ipa | head -1)
echo "📦 $IPA"
xcrun altool --upload-app --type ios -f "$IPA" --apiKey "$KEY_ID" --apiIssuer "$ISSUER"
echo "✅ Subida. En 10-20 min aparece en App Store Connect → TestFlight (procesando → VALID)."
