#!/usr/bin/env bash
set -euo pipefail

APP_URL="${1:-http://127.0.0.1:5173}"

adb start-server >/dev/null
adb reverse tcp:5173 tcp:5173
adb shell am start -a android.intent.action.VIEW -d "${APP_URL}"

echo "Opened ${APP_URL} on connected Android device."
