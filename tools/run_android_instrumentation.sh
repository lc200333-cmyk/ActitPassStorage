#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID=com.example.actit_pass_storage

adb uninstall $PACKAGE_ID >/dev/null

cd app
flutter pub get

cd android
./gradlew connectedDebugAndroidTest --no-daemon
