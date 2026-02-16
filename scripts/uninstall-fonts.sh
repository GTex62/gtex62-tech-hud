#!/usr/bin/env bash
set -euo pipefail

DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
MANIFEST="$DEST_DIR/.gtex62-tech-hud-fonts.manifest"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Nothing to uninstall (manifest not found): $MANIFEST"
  exit 0
fi

echo "Removing Tech HUD fonts listed in:"
echo "  $MANIFEST"
echo

removed=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ -f "$path" ]]; then
    rm -f "$path"
    ((removed+=1))
  fi
done < "$MANIFEST"

rm -f "$MANIFEST"

echo "Removed $removed font file(s)."
echo "Rebuilding font cache..."
fc-cache -f >/dev/null
echo "Done."
