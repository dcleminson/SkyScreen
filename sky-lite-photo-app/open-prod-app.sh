#!/usr/bin/env bash
set -euo pipefail

APP_URL="${1:-http://127.0.0.1:4173}"

adb start-server >/dev/null
adb reverse tcp:4173 tcp:4173
adb shell am start -a android.intent.action.VIEW -d "${APP_URL}"

echo "Opened production preview ${APP_URL} on connected Android device."
