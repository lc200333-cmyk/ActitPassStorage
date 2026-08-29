#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
BRANDING_FILE="$APP_DIR/branding.yaml"

APP_NAME="$(sed -n 's/^name:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$BRANDING_FILE" | head -1)"
WINDOWS_APP_NAME="$(sed -n 's/^windows_name:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$BRANDING_FILE" | head -1)"
[ -n "$APP_NAME" ] || {
  echo "branding.yaml: не удалось прочитать name" >&2
  exit 1
}
[ -n "$WINDOWS_APP_NAME" ] || WINDOWS_APP_NAME="$APP_NAME"

cd "$APP_DIR"
dart run flutter_launcher_icons -f branding.yaml
dart run tool/generate_platform_icons.dart

if [ -f android/app/src/main/AndroidManifest.xml ]; then
  sed -i "s/android:label=\"[^\"]*\"/android:label=\"$APP_NAME\"/" \
    android/app/src/main/AndroidManifest.xml
fi

if [ -f windows/runner/Runner.rc ]; then
  sed -i \
    -e "s/VALUE \"FileDescription\", \"[^\"]*\"/VALUE \"FileDescription\", \"$WINDOWS_APP_NAME\"/" \
    -e "s/VALUE \"ProductName\", \"[^\"]*\"/VALUE \"ProductName\", \"$WINDOWS_APP_NAME\"/" \
    windows/runner/Runner.rc
fi
if [ -f windows/runner/main.cpp ]; then
  sed -i "s/window.Create(L\"[^\"]*\"/window.Create(L\"$WINDOWS_APP_NAME\"/" windows/runner/main.cpp
fi

if [ -f linux/runner/my_application.cc ]; then
  sed -i \
    -e "s/gtk_header_bar_set_title(header_bar, \"[^\"]*\")/gtk_header_bar_set_title(header_bar, \"$APP_NAME\")/" \
    -e "s/gtk_window_set_title(window, \"[^\"]*\")/gtk_window_set_title(window, \"$APP_NAME\")/" \
    linux/runner/my_application.cc
fi

if [ -f "$ROOT_DIR/tools/windows/Wallet-APS.iss" ]; then
  sed -i "s/#define MyAppName \"[^\"]*\"/#define MyAppName \"$WINDOWS_APP_NAME\"/" \
    "$ROOT_DIR/tools/windows/Wallet-APS.iss"
fi

echo "Брендинг применён: $APP_NAME"
