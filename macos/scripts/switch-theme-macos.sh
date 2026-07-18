#!/bin/bash

# Switch to a theme pack under themes/<id>/ — hot path when CDP is live.

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

THEME_ID=""
APPLY_NOW="true"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --id) THEME_ID="${2:-}"; shift 2 ;;
    --no-apply) APPLY_NOW="false"; shift ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[ -n "$THEME_ID" ] || fail "Usage: switch-theme-macos.sh --id <theme-id>"

case "$THEME_ID" in
  prince|little-prince|inspiration-universe) THEME_ID="skin-05" ;;
  qq|retro-qq|qq2007) THEME_ID="qq2007" ;;
esac

ensure_state_root
SRC="$THEMES_ROOT/$THEME_ID"
[ -d "$SRC" ] || fail "Theme not found: $THEME_ID"
[ -f "$SRC/theme.json" ] || fail "theme.json missing in $THEME_ID"

progress() {
  printf '%s\n' "$*" >&2
  /usr/bin/osascript -e "display notification \"$*\" with title \"Codex Dream Skin\"" >/dev/null 2>&1 || true
}

progress "Switching..."

ensure_node_runtime
"$NODE" "$INJECTOR" --check-payload --theme-dir "$SRC" >/dev/null \
  || fail "Theme validation failed before switch: $THEME_ID"

temporary="$STATE_ROOT/theme.switching.$$"
previous="$STATE_ROOT/theme.previous.$$"
previous_id="$(active_theme_id 2>/dev/null || true)"
cleanup_switch() {
  /bin/rm -rf "$temporary" 2>/dev/null || true
}
trap cleanup_switch EXIT
/bin/rm -rf "$temporary" "$previous"
/bin/mkdir -p "$temporary"
/usr/bin/rsync -a "$SRC/" "$temporary/"
/bin/chmod 700 "$temporary"
/usr/bin/find "$temporary" -type f -exec /bin/chmod 600 {} +
"$NODE" "$INJECTOR" --check-payload --theme-dir "$temporary" >/dev/null \
  || fail "Staged theme validation failed: $THEME_ID"

if [ -e "$THEME_DIR" ]; then /bin/mv "$THEME_DIR" "$previous"; fi
if ! /bin/mv "$temporary" "$THEME_DIR"; then
  [ -e "$previous" ] && /bin/mv "$previous" "$THEME_DIR"
  fail "Could not activate theme: $THEME_ID"
fi
id_temporary="$ACTIVE_THEME_ID_PATH.$$.tmp"
/usr/bin/printf '%s\n' "$THEME_ID" > "$id_temporary"
/bin/chmod 600 "$id_temporary"
/bin/mv -f "$id_temporary" "$ACTIVE_THEME_ID_PATH"

THEME_NAME="$("$NODE" -e 'try{const t=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(t.name||"")}catch{}' "$THEME_DIR/theme.json" 2>/dev/null || true)"
[ -n "$THEME_NAME" ] || THEME_NAME="$THEME_ID"

if [ "$APPLY_NOW" != "true" ]; then
  /bin/rm -rf "$previous"
  trap - EXIT
  progress "Ready: ${THEME_NAME} (not applied)"
  exit 0
fi

PORT=9341
if [ -f "$STATE_PATH" ]; then
  saved="$(state_field port 2>/dev/null || true)"
  [ -n "${saved:-}" ] && PORT="$saved"
fi

# Hot path: CDP already open → seconds, not tens of seconds
if hot_reapply_theme "$PORT" 8000; then
  activate_codex_window
  /bin/rm -rf "$previous"
  trap - EXIT
  progress "Done: ${THEME_NAME}"
  exit 0
fi

# Cold path only when debug port is missing
progress "Hot apply was not healthy; restarting Codex..."
if "$SCRIPT_DIR/start-dream-skin-macos.sh" --port "$PORT" --restart-existing; then
  /bin/rm -rf "$previous"
  trap - EXIT
  progress "Done: ${THEME_NAME}"
  exit 0
fi

progress "Switch failed, restoring previous theme..."
/bin/rm -rf "$THEME_DIR"
if [ -e "$previous" ]; then /bin/mv "$previous" "$THEME_DIR"; fi
if [ -n "$previous_id" ]; then
  /usr/bin/printf '%s\n' "$previous_id" > "$ACTIVE_THEME_ID_PATH"
else
  /bin/rm -f "$ACTIVE_THEME_ID_PATH"
fi
hot_reapply_theme "$PORT" 8000 >/dev/null 2>&1 || true
/usr/bin/osascript -e 'display alert "Codex Dream Skin" message "Theme switch failed; the previous theme was restored."' >/dev/null 2>&1 || true
fail "Theme switch failed and was rolled back: $THEME_ID"
