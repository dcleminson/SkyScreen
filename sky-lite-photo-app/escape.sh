#!/usr/bin/env bash
set -euo pipefail

# Kill likely full-screen/sticky apps and return to Android launcher.
adb shell am force-stop com.android.rk >/dev/null 2>&1 || true
adb shell am force-stop acr.browser.barebones >/dev/null 2>&1 || true
adb shell am force-stop org.chromium.webview_shell >/dev/null 2>&1 || true

# Ensure launcher remains the Home target and navigate there.
adb shell cmd package set-home-activity ch.deletescape.lawnchair/.Launcher >/dev/null 2>&1 || true
adb shell input keyevent 3

echo "Escape complete: returned to Android Home launcher."
