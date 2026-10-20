#!/usr/bin/env bash
set -euo pipefail

APP_URL="${1:-http://127.0.0.1:5173}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/open-android-home.sh"
sleep 1
"${SCRIPT_DIR}/open-android-settings.sh"
sleep 1
"${SCRIPT_DIR}/open-app.sh" "${APP_URL}"

echo "Recovery flow complete: Home -> Settings -> App (${APP_URL})"
