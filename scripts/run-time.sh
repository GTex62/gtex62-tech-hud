#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/conky-env.sh"

"$SCRIPT_DIR/sky_update.py" || true

SUITE="$CONKY_SUITE_DIR"
CONF="$SUITE/widgets/time.conky.conf"
exec conky -c "$CONF"
