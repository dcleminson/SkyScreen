#!/usr/bin/env bash
set -euo pipefail

ALEXA_PACKAGE="com.amazon.dee.app"

if ! adb shell pm list packages | grep -q "${ALEXA_PACKAGE}"; then
  echo "Alexa package not found: ${ALEXA_PACKAGE}"
  exit 0
fi

adb shell pm disable-user --user 0 "${ALEXA_PACKAGE}" >/dev/null
adb shell cmd package set-home-activity ch.deletescape.lawnchair/.Launcher >/dev/null 2>&1 || true
adb shell input keyevent 3

echo "Disabled ${ALEXA_PACKAGE} for user 0 and sent HOME to Android launcher."
