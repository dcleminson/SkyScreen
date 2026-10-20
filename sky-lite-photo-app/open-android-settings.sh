#!/usr/bin/env bash
set -euo pipefail

adb shell am start -a android.settings.SETTINGS
echo "Opened Android Settings on device."
