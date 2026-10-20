#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-4173}"

npm run build
npm run preview -- --host "${HOST}" --port "${PORT}"
