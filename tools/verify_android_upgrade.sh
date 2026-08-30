#!/usr/bin/env bash
set -euo pipefail

PREVIOUS_APK="${1:?previous APK path is required}"
CURRENT_APK="${2:?current APK path is required}"
PACKAGE_ID="com.example.actit_pass_storage"

adb install -r "$PREVIOUS_APK"
BEFORE="$(adb shell dumpsys package "$PACKAGE_ID" | sed -n 's/.*firstInstallTime=//p' | head -n 1 | tr -d '\r')"
test -n "$BEFORE"

adb install -r "$CURRENT_APK"
AFTER="$(adb shell dumpsys package "$PACKAGE_ID" | sed -n 's/.*firstInstallTime=//p' | head -n 1 | tr -d '\r')"

test "$BEFORE" = "$AFTER"
adb shell pm path "$PACKAGE_ID" >/dev/null
echo "Android in-place upgrade succeeded; firstInstallTime remained $AFTER"
