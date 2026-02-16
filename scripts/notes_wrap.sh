#!/usr/bin/env bash

wrap="${1:-39}"
lines="${2:-61}"
text_x="${3:-0}"
notes_file="${4:-$HOME/Documents/conky-notes-tech.txt}"

fold -s -w "$wrap" "$notes_file" 2>/dev/null | \
  sed -n "1,${lines}p" | \
  awk -v x="$text_x" '{printf "%c{goto %d}%s\n", 36, x, $0}'
