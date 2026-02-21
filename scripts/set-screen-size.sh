#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/conky-env.sh"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run|-n]

Detect primary screen size via xrandr and write CONKY_SCREEN_W/H into scripts/conky-env.sh.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if ! command -v xrandr >/dev/null 2>&1; then
  echo "Error: xrandr not found. Set CONKY_SCREEN_W/H manually in $ENV_FILE." >&2
  exit 1
fi

xr_line="$(xrandr --current 2>/dev/null | awk '/ primary / {print; exit}')"
if [ -z "$xr_line" ]; then
  xr_line="$(xrandr --current 2>/dev/null | awk '/ connected / {print; exit}')"
fi

if [ -z "$xr_line" ]; then
  echo "Error: could not detect a connected display via xrandr." >&2
  exit 1
fi

read -r xr_w xr_h <<< "$(awk 'match($0,/([0-9]+)x([0-9]+)/,a){print a[1],a[2]; exit}' <<< "$xr_line")"
if [ -z "${xr_w:-}" ] || [ -z "${xr_h:-}" ]; then
  echo "Error: could not parse resolution from xrandr output." >&2
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo "Detected primary screen size:"
  echo "  CONKY_SCREEN_W=$xr_w"
  echo "  CONKY_SCREEN_H=$xr_h"
  exit 0
fi

tmp="$(mktemp --tmpdir conky-env.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

awk -v w="$xr_w" -v h="$xr_h" '
  BEGIN { found_w=0; found_h=0 }
  {
    if ($0 ~ /^[[:space:]]*#?[[:space:]]*export[[:space:]]+CONKY_SCREEN_W=/) {
      print "export CONKY_SCREEN_W=\"" w "\""
      found_w=1
      next
    }
    if ($0 ~ /^[[:space:]]*#?[[:space:]]*export[[:space:]]+CONKY_SCREEN_H=/) {
      print "export CONKY_SCREEN_H=\"" h "\""
      found_h=1
      next
    }
    print
  }
  END {
    if (!found_w) print "export CONKY_SCREEN_W=\"" w "\""
    if (!found_h) print "export CONKY_SCREEN_H=\"" h "\""
  }
' "$ENV_FILE" > "$tmp"

mv "$tmp" "$ENV_FILE"
trap - EXIT

echo "Updated $ENV_FILE with:"
echo "  CONKY_SCREEN_W=$xr_w"
echo "  CONKY_SCREEN_H=$xr_h"
