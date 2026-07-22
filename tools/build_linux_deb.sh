#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_ROOT="$ROOT_DIR/build/deb/actit-pass-storage"
VERSION="0.1.12"
ARCH="amd64"
BIN_NAME="actit_pass_storage"
DEB_PATH="$DIST_DIR/actit-pass-storage_${VERSION}_${ARCH}.deb"
DISPLAY_NAME="$(sed -n 's/^name:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$APP_DIR/branding.yaml" | head -1)"

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK не найден. Установите Flutter stable и добавьте flutter в PATH." >&2
  exit 1
}
command -v dpkg-deb >/dev/null 2>&1 || {
  echo "dpkg-deb не найден. Установите dpkg-dev." >&2
  exit 1
}

mkdir -p "$DIST_DIR"
cd "$APP_DIR"

if [ ! -f "linux/CMakeLists.txt" ]; then
  flutter create --platforms=linux .
fi
flutter pub get
"$ROOT_DIR/tools/apply_branding.sh"
flutter build linux --release

rm -rf "$PACKAGE_ROOT"
mkdir -p \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT/opt/ActitPassStorage" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/256x256/apps"

cp -R "$APP_DIR/build/linux/x64/release/bundle/." "$PACKAGE_ROOT/opt/ActitPassStorage/"
cp "$ROOT_DIR/assets/icon.png" "$PACKAGE_ROOT/usr/share/icons/hicolor/256x256/apps/actit-pass-storage.png"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<CONTROL
Package: actit-pass-storage
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: ActitPassStorage <noreply@example.local>
Depends: libgtk-3-0, libblkid1, liblzma5
Description: Локальный менеджер паролей, заметок и карточек
 ActitPassStorage хранит локальные базы секретов и поддерживает настраиваемые карточки.
CONTROL

cat > "$PACKAGE_ROOT/usr/share/applications/actit-pass-storage.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=Локальный менеджер паролей, заметок и карточек
Exec=/opt/ActitPassStorage/$BIN_NAME
Icon=actit-pass-storage
Terminal=false
Categories=Utility;Security;
DESKTOP

cat > "$PACKAGE_ROOT/usr/bin/actit-pass-storage" <<LAUNCHER
#!/usr/bin/env bash
exec /opt/ActitPassStorage/$BIN_NAME "\$@"
LAUNCHER
chmod 0755 "$PACKAGE_ROOT/usr/bin/actit-pass-storage"

fakeroot dpkg-deb --build "$PACKAGE_ROOT" "$DEB_PATH"
cp "$DEB_PATH" "$DIST_DIR/ActitPassStorage-linux-amd64.deb"
echo "deb готов: $DEB_PATH"
