#!/bin/bash

# Catalog-driven theme command. Any installed theme ID is accepted; aliases
# below remain for compatibility with older launchers.

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

ACTION="${1:-status}"
case "$ACTION" in
  prince|little-prince|inspiration-universe|小王子)
    exec "$SCRIPT_DIR/switch-theme-macos.sh" --id skin-05
    ;;
  qq|qq2007|retro-qq|复古qq|复古QQ)
    exec "$SCRIPT_DIR/switch-theme-macos.sh" --id qq2007
    ;;
  original|off|none|stock|原皮|取消皮肤)
    "$SCRIPT_DIR/pause-dream-skin-macos.sh"
    ensure_state_root
    temporary="$ACTIVE_THEME_ID_PATH.$$.tmp"
    /usr/bin/printf '%s\n' original > "$temporary"
    /bin/chmod 600 "$temporary"
    /bin/mv -f "$temporary" "$ACTIVE_THEME_ID_PATH"
    printf 'Codex original appearance is active.\n'
    ;;
  list)
    ensure_state_root
    current="$(active_theme_id 2>/dev/null || true)"
    marker=""
    [ "$current" = "original" ] && marker=" *"
    printf '%-10s %s%s\n' original 'Codex 原皮' "$marker"
    for dir in "$THEMES_ROOT"/*; do
      [ -d "$dir" ] || continue
      [ -f "$dir/theme.json" ] || continue
      id="$(/usr/bin/basename "$dir")"
      name="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("name") or sys.argv[2])' "$dir/theme.json" "$id")"
      marker=""
      [ "$id" = "$current" ] && marker=" *"
      printf '%-10s %s%s\n' "$id" "$name" "$marker"
    done
    ;;
  status)
    exec "$SCRIPT_DIR/status-dream-skin-macos.sh"
    ;;
  *)
    exec "$SCRIPT_DIR/switch-theme-macos.sh" --id "$ACTION"
    ;;
esac
