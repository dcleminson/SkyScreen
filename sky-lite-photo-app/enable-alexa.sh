#!/usr/bin/env bash
set -euo pipefail

ALEXA_PACKAGE="com.amazon.dee.app"

if ! adb shell pm list packages | grep -q "${ALEXA_PACKAGE}"; then
  echo "Alexa package not found: ${ALEXA_PACKAGE}"
  exit 0
fi

adb shell pm enable --user 0 "${ALEXA_PACKAGE}" >/dev/null
echo "Re-enabled ${ALEXA_PACKAGE} for user 0."
