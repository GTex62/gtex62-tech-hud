#!/usr/bin/env bash
set -euo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$SUITE_DIR/fonts"
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
MANIFEST="$DEST_DIR/.gtex62-tech-hud-fonts.manifest"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: fonts directory not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
: > "$MANIFEST"

echo "Installing Tech HUD fonts from:"
echo "  $SRC_DIR"
echo "Into:"
echo "  $DEST_DIR"
echo

count=0
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  cp -f "$f" "$DEST_DIR/$base"
  echo "$DEST_DIR/$base" >> "$MANIFEST"
  ((count+=1))
done < <(find "$SRC_DIR" -type f \( -iname "*.ttf" -o -iname "*.otf" \) -print0)

echo "Copied $count font file(s)."
echo "Rebuilding font cache..."
fc-cache -f >/dev/null

echo "Done."
echo "Manifest saved to: $MANIFEST"
echo "Tip: restart apps (or log out/in) if fonts don't appear immediately."
