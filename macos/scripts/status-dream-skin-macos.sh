#!/bin/bash

# Fast status for SwiftBar. No codesign / CDP probes by default.

set +e
set -u

SHORT="false"
JSON="false"
DEEP="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --short) SHORT="true"; shift ;;
    --json) JSON="true"; shift ;;
    --deep) DEEP="true"; shift ;;
    *) printf 'Unknown status argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

STATE_ROOT="${HOME}/Library/Application Support/CodexDreamSkinStudio"
STATE_PATH="${STATE_ROOT}/state.json"
THEME_DIR="${STATE_ROOT}/theme"
ACTIVE_THEME_ID_PATH="${STATE_ROOT}/active-theme-id"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"

PORT="9341"
SESSION="off"
INJECTOR_ALIVE="false"
CDP_OK="false"
THEME_NAME=""
THEME_ID=""
DESIRED_THEME_ID=""
LIVE_THEME_ID=""
THEME_APPLIED="false"
CODEX_RUNNING="false"
APP_INTEGRITY_OK="true"
APP_INTEGRITY_MESSAGE=""

read_json_field() {
  /usr/bin/python3 - "$1" "$2" 2>/dev/null <<'PY' || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    v = data.get(sys.argv[2])
    if v is not None:
        print(v, end="")
except Exception:
    pass
PY
}

if [ -f "$STATE_PATH" ]; then
  saved_port="$(read_json_field "$STATE_PATH" port)"
  [ -n "${saved_port:-}" ] && PORT="$saved_port"
  SESSION="$(read_json_field "$STATE_PATH" session)"
  pid="$(read_json_field "$STATE_PATH" injectorPid)"
  if [ -n "${pid:-}" ] && [ "$pid" != "0" ] && /bin/kill -0 "$pid" 2>/dev/null; then
    INJECTOR_ALIVE="true"
    SESSION="active"
  elif [ "${SESSION:-}" = "paused" ]; then
    SESSION="paused"
  elif [ -n "${pid:-}" ] && [ "$pid" != "0" ]; then
    SESSION="stale"
  elif [ -z "${SESSION:-}" ]; then
    SESSION="unknown"
  fi
  codex_pid="$(read_json_field "$STATE_PATH" codexPid)"
  if [ -n "${codex_pid:-}" ] && [ "$codex_pid" != "0" ] && /bin/kill -0 "$codex_pid" 2>/dev/null; then
    CODEX_RUNNING="true"
  fi
fi

# Fallback for sessions created before codexPid was recorded.
if [ "$CODEX_RUNNING" != "true" ] && /usr/bin/pgrep -x ChatGPT >/dev/null 2>&1; then
  CODEX_RUNNING="true"
fi
if [ "$CODEX_RUNNING" != "true" ] && /usr/bin/pgrep -f '/(ChatGPT|Codex)\.app/Contents/MacOS/(ChatGPT|Codex)( |$)' >/dev/null 2>&1; then
  CODEX_RUNNING="true"
fi

if [ -f "$THEME_DIR/theme.json" ]; then
  THEME_NAME="$(read_json_field "$THEME_DIR/theme.json" name)"
  [ -n "$THEME_NAME" ] || THEME_NAME="$(read_json_field "$THEME_DIR/theme.json" id)"
fi
if [ -f "$ACTIVE_THEME_ID_PATH" ]; then
  THEME_ID="$(/usr/bin/tr -d '\r\n[:space:]' < "$ACTIVE_THEME_ID_PATH")"
fi
DESIRED_THEME_ID="$THEME_ID"
if [ "$SESSION" = "paused" ]; then
  THEME_ID="original"
  LIVE_THEME_ID="original"
  THEME_APPLIED="true"
fi
if [ "$THEME_ID" = "original" ]; then
  THEME_NAME="Codex 原皮"
fi

if /usr/bin/curl --noproxy '*' --silent --fail --max-time 1 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
  CDP_OK="true"
  CODEX_RUNNING="true"
fi

if [ "$DEEP" = "true" ] && [ "$CDP_OK" = "true" ] && [ "$SESSION" != "paused" ] && [ -f "$SCRIPT_DIR/injector.mjs" ]; then
  NODE=""
  for candidate in \
    "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
    "/Applications/Codex.app/Contents/Resources/cua_node/bin/node" \
    "$HOME/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
    "$HOME/Applications/Codex.app/Contents/Resources/cua_node/bin/node"
  do
    if [ -x "$candidate" ]; then NODE="$candidate"; break; fi
  done
  if [ -n "$NODE" ]; then
    live_json=""
    for attempt in 1 2; do
      live_json="$("$NODE" "$SCRIPT_DIR/injector.mjs" --verify --port "$PORT" --theme-dir "$THEME_DIR" --timeout-ms 1800 2>/dev/null || true)"
      /usr/bin/printf '%s' "$live_json" | /usr/bin/python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 && break
      /bin/sleep 0.15
    done
    live_probe="$(/usr/bin/printf '%s' "$live_json" | /usr/bin/python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    results = [target.get("result", {}) for target in data.get("targets", [])]
    ids = {str(result.get("themeId", "")) for result in results if result.get("themeId")}
    live = ids.pop() if len(ids) == 1 else ""
    passed = bool(results) and all(result.get("pass") is True for result in results)
    print(f"{live}\t{str(passed).lower()}", end="")
except Exception:
    pass
' 2>/dev/null || true)"
    IFS=$'\t' read -r LIVE_THEME_ID LIVE_VERIFY_PASS <<EOF
$live_probe
EOF
    if [ -n "$LIVE_THEME_ID" ]; then THEME_ID="$LIVE_THEME_ID"; fi
    if [ -n "$LIVE_THEME_ID" ] && [ "$LIVE_THEME_ID" = "$DESIRED_THEME_ID" ] && [ "${LIVE_VERIFY_PASS:-false}" = "true" ]; then
      THEME_APPLIED="true"
    fi
  fi
fi

if [ "$DEEP" = "true" ]; then
  CODEX_APP=""
  for candidate in /Applications/ChatGPT.app /Applications/Codex.app "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app"; do
    if [ -d "$candidate" ]; then CODEX_APP="$candidate"; break; fi
  done
  if [ -z "$CODEX_APP" ]; then
    APP_INTEGRITY_OK="false"
    APP_INTEGRITY_MESSAGE="未找到官方 Codex 应用"
  elif ! /usr/bin/codesign --verify --deep --strict "$CODEX_APP" >/dev/null 2>&1; then
    APP_INTEGRITY_OK="false"
    APP_INTEGRITY_MESSAGE="官方 Codex 应用签名无效，请从官方来源重新安装"
  fi
fi

label="Skin"
case "$SESSION" in
  active) label="Skin ON" ;;
  paused) label="Skin 暂停" ;;
  stale|unknown) label="Skin ?" ;;
  *) label="Skin 关" ;;
esac

if [ "$SHORT" = "true" ]; then
  printf '%s\n' "$label"
  exit 0
fi

if [ "$JSON" = "true" ]; then
  /usr/bin/python3 - "$SESSION" "$PORT" "$INJECTOR_ALIVE" "$CDP_OK" "$CODEX_RUNNING" "$THEME_NAME" "$THEME_ID" "$DESIRED_THEME_ID" "$LIVE_THEME_ID" "$THEME_APPLIED" "$APP_INTEGRITY_OK" "$APP_INTEGRITY_MESSAGE" <<'PY'
import json, sys
print(json.dumps({
    "session": sys.argv[1],
    "port": int(sys.argv[2]) if str(sys.argv[2]).isdigit() else sys.argv[2],
    "injectorAlive": sys.argv[3] == "true",
    "cdpOk": sys.argv[4] == "true",
    "codexRunning": sys.argv[5] == "true",
    "themeName": sys.argv[6] or "",
    "themeId": sys.argv[7] or "",
    "desiredThemeId": sys.argv[8] or "",
    "liveThemeId": sys.argv[9] or "",
    "themeApplied": sys.argv[10] == "true",
    "appIntegrityOk": sys.argv[11] == "true",
    "appIntegrityMessage": sys.argv[12] or "",
}))
PY
  exit 0
fi

printf 'session=%s\n' "$SESSION"
printf 'port=%s\n' "$PORT"
printf 'injector=%s\n' "$INJECTOR_ALIVE"
printf 'cdp=%s\n' "$CDP_OK"
printf 'codex=%s\n' "$CODEX_RUNNING"
printf 'theme=%s\n' "${THEME_NAME:-}"
printf 'themeId=%s\n' "${THEME_ID:-}"
