#!/usr/bin/env bash
set -euo pipefail

# Keep Android launcher as Home target so Home key does not bounce into terminal apps.
adb shell cmd package set-home-activity ch.deletescape.lawnchair/.Launcher >/dev/null 2>&1 || true
adb shell input keyevent 3

echo "Sent HOME key and preferred Android launcher is set to Lawnchair (if available)."
