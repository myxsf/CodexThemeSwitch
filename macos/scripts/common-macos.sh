#!/bin/bash

set -euo pipefail

if [ -z "${HOME:-}" ]; then
  CURRENT_USER="$(/usr/bin/id -un)"
  HOME="$(/usr/bin/dscl . -read "/Users/$CURRENT_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}' || true)"
  if [ -z "$HOME" ] && [ -x /usr/bin/python3 ]; then
    HOME="$(/usr/bin/python3 -c 'import pwd,sys; print(pwd.getpwnam(sys.argv[1]).pw_dir)' "$CURRENT_USER" 2>/dev/null || true)"
  fi
  [ -n "$HOME" ] || { printf 'Codex Dream Skin Studio: could not resolve the current macOS home directory.\n' >&2; exit 1; }
  export HOME
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INJECTOR="$SCRIPT_DIR/injector.mjs"
INSTALL_ROOT="$HOME/.codex/codex-dream-skin-studio"
STATE_ROOT="$HOME/Library/Application Support/CodexDreamSkinStudio"
STATE_PATH="$STATE_ROOT/state.json"
THEME_BACKUP_PATH="$STATE_ROOT/theme-backup.json"
THEME_DIR="$STATE_ROOT/theme"
THEMES_ROOT="$STATE_ROOT/themes"
ACTIVE_THEME_ID_PATH="$STATE_ROOT/active-theme-id"
CONFIG_PATH="$HOME/.codex/config.toml"
INJECTOR_LOG="$STATE_ROOT/injector.log"
INJECTOR_ERROR_LOG="$STATE_ROOT/injector-error.log"
APP_LOG="$STATE_ROOT/codex-launch.log"
APP_ERROR_LOG="$STATE_ROOT/codex-launch-error.log"
START_ERROR_LOG="$STATE_ROOT/start-error.log"
LAST_VERIFY_JSON="$STATE_ROOT/last-verify.json"
LAST_VERIFY_ERROR_LOG="$STATE_ROOT/last-verify-error.log"
CODEX_APP_JOB_LABEL="com.openai.codex-dream-skin-studio.app"
INJECTOR_JOB_LABEL="com.openai.codex-dream-skin-studio.injector"
INJECTOR_JOB_PLIST="$STATE_ROOT/$INJECTOR_JOB_LABEL.plist"
EXPECTED_CODEX_TEAM_ID="${CODEX_EXPECTED_TEAM_ID:-2DC432GLL2}"
SKIN_VERSION="2.2.10"

fail() {
  local message="$*"
  if [ -n "${START_ERROR_LOG:-}" ] && [ -n "${STATE_ROOT:-}" ]; then
    /bin/mkdir -p "$STATE_ROOT" 2>/dev/null || true
    printf '%s %s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" "$message" >> "$START_ERROR_LOG" 2>/dev/null || true
  fi
  printf 'Codex Dream Skin Studio: %s\n' "$message" >&2
  exit 1
}

ensure_state_root() {
  /bin/mkdir -p "$STATE_ROOT" "$THEMES_ROOT"
  /bin/chmod 700 "$STATE_ROOT"
}

active_theme_id() {
  if [ -f "$ACTIVE_THEME_ID_PATH" ]; then
    /usr/bin/tr -d '\r\n[:space:]' < "$ACTIVE_THEME_ID_PATH"
  fi
}

codex_bundle_from_node() {
  local node_path="$1"
  case "$node_path" in
    */Contents/Resources/cua_node/bin/node)
      printf '%s\n' "${node_path%/Contents/Resources/cua_node/bin/node}"
      ;;
  esac
}

set_codex_bundle_metadata() {
  local bundle="$1"
  local identifier=""
  local executable_name=""
  [ -f "$bundle/Contents/Info.plist" ] || return 1
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)"
  [ "$identifier" = "com.openai.codex" ] || return 1
  executable_name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)"
  [ -n "$executable_name" ] || return 1
  [ -x "$bundle/Contents/MacOS/$executable_name" ] || return 1
  CODEX_BUNDLE="$bundle"
  CODEX_EXE="$bundle/Contents/MacOS/$executable_name"
  CODEX_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)"
  CODEX_TEAM_ID="$(codesign_team_id "$bundle" 2>/dev/null || true)"
  export CODEX_BUNDLE CODEX_EXE CODEX_VERSION CODEX_TEAM_ID
  return 0
}

discover_codex_app() {
  local candidate=""
  local identifier=""
  local executable_name=""
  local configured="${CODEX_APP_BUNDLE:-}"

  for candidate in "$configured" "/Applications/ChatGPT.app" "$HOME/Applications/ChatGPT.app"; do
    [ -n "$candidate" ] || continue
    [ -f "$candidate/Contents/Info.plist" ] || continue
    identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$identifier" = "com.openai.codex" ]; then
      CODEX_BUNDLE="$candidate"
      break
    fi
  done

  if [ -z "${CODEX_BUNDLE:-}" ]; then
    candidate="$(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "com.openai.codex"' | /usr/bin/head -n 1)"
    if [ -n "$candidate" ] && [ -f "$candidate/Contents/Info.plist" ]; then
      identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$candidate/Contents/Info.plist" 2>/dev/null || true)"
      [ "$identifier" = "com.openai.codex" ] && CODEX_BUNDLE="$candidate"
    fi
  fi

  [ -n "${CODEX_BUNDLE:-}" ] || fail "Could not find the official Codex app bundle (com.openai.codex)."
  executable_name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$CODEX_BUNDLE/Contents/Info.plist")"
  CODEX_EXE="$CODEX_BUNDLE/Contents/MacOS/$executable_name"
  CODEX_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$CODEX_BUNDLE/Contents/Info.plist")"
  [ -x "$CODEX_EXE" ] || fail "Codex executable is missing: $CODEX_EXE"
  export CODEX_BUNDLE CODEX_EXE CODEX_VERSION
}

codesign_team_id() {
  /usr/bin/codesign -dv --verbose=4 "$1" 2>&1 \
    | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}'
}

require_macos_runtime() {
  [ "$(/usr/bin/uname -s)" = "Darwin" ] || fail "This launcher requires macOS."
  [ -n "${CODEX_BUNDLE:-}" ] || fail "Discover the Codex app before validating its runtime."

  RUNTIME_NODE="$CODEX_BUNDLE/Contents/Resources/cua_node/bin/node"
  [ -x "$RUNTIME_NODE" ] || fail "The signed Node.js runtime bundled with Codex was not found: $RUNTIME_NODE"
  /usr/bin/codesign --verify --deep --strict "$CODEX_BUNDLE" >/dev/null 2>&1 \
    || fail "The Codex app signature is not valid. Restore or reinstall the official app before continuing."
  /usr/bin/codesign --verify --strict "$RUNTIME_NODE" >/dev/null 2>&1 \
    || fail "The Node.js runtime bundled with Codex failed code-signature validation."

  CODEX_TEAM_ID="$(codesign_team_id "$CODEX_BUNDLE")"
  NODE_TEAM_ID="$(codesign_team_id "$RUNTIME_NODE")"
  [ "$CODEX_TEAM_ID" = "$EXPECTED_CODEX_TEAM_ID" ] \
    || fail "Unexpected Codex signing team: ${CODEX_TEAM_ID:-missing}."
  [ "$NODE_TEAM_ID" = "$CODEX_TEAM_ID" ] \
    || fail "The bundled Node.js signer does not match the Codex app signer."

  local machine_arch
  local node_major
  machine_arch="$(/usr/bin/uname -m)"
  /usr/bin/file "$RUNTIME_NODE" | /usr/bin/grep -q "$machine_arch" \
    || fail "The Codex Node.js runtime does not match this Mac architecture ($machine_arch)."
  NODE_VERSION="$($RUNTIME_NODE --version)"
  node_major="${NODE_VERSION#v}"
  node_major="${node_major%%.*}"
  case "$node_major" in ''|*[!0-9]*) fail "Could not parse bundled Node.js version: $NODE_VERSION" ;; esac
  [ "$node_major" -ge 20 ] || fail "Codex bundled Node.js $NODE_VERSION is too old; version 20 or newer is required."

  NODE="$RUNTIME_NODE"
  export NODE RUNTIME_NODE NODE_VERSION CODEX_TEAM_ID NODE_TEAM_ID
}

codex_main_pids() {
  local pid
  local command_line
  while read -r pid command_line; do
    [ -n "$pid" ] || continue
    case "$command_line" in
      "$CODEX_EXE"*) printf '%s\n' "$pid" ;;
    esac
  done < <(/bin/ps -axo pid=,command=)
}

codex_is_running() {
  [ -n "$(codex_main_pids)" ]
}

activate_codex_window() {
  [ -n "${CODEX_BUNDLE:-}" ] || discover_codex_app
  /usr/bin/open "$CODEX_BUNDLE" >/dev/null 2>&1 && return 0
  /usr/bin/osascript -e 'tell application id "com.openai.codex" to activate' >/dev/null 2>&1 && return 0
  printf 'Codex Dream Skin Studio: theme is active, but the Codex window could not be brought forward automatically.\n' >&2
  return 0
}

process_started_at() {
  /bin/ps -p "$1" -o lstart= 2>/dev/null | /usr/bin/awk '{$1=$1; print}'
}

stop_codex() {
  local allow_force="${1:-false}"
  local deadline
  local pid

  release_codex_launchd_job
  codex_is_running || return 0
  /usr/bin/osascript -e 'tell application id "com.openai.codex" to quit' >/dev/null 2>&1 || true
  deadline=$((SECONDS + 15))
  while codex_is_running && [ "$SECONDS" -lt "$deadline" ]; do /bin/sleep 0.25; done
  codex_is_running || return 0

  [ "$allow_force" = "true" ] || fail "Codex did not close within 15 seconds; explicit restart authorization is required for a forced stop."
  while IFS= read -r pid; do
    [ -n "$pid" ] && /bin/kill -TERM "$pid" 2>/dev/null || true
  done < <(codex_main_pids)
  deadline=$((SECONDS + 5))
  while codex_is_running && [ "$SECONDS" -lt "$deadline" ]; do /bin/sleep 0.25; done
  if codex_is_running; then
    while IFS= read -r pid; do
      [ -n "$pid" ] && /bin/kill -KILL "$pid" 2>/dev/null || true
    done < <(codex_main_pids)
  fi
  /bin/sleep 0.5
  codex_is_running && fail "Codex could not be stopped safely."
  return 0
}

listener_pids() {
  /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | /usr/bin/sort -u || true
}

port_is_available() {
  [ -z "$(listener_pids "$1")" ]
}

pid_is_codex_descendant() {
  local current="$1"
  local command_line=""
  local parent=""
  local depth=0
  while [ "$current" -gt 1 ] 2>/dev/null && [ "$depth" -lt 32 ]; do
    command_line="$(/bin/ps -p "$current" -o command= 2>/dev/null || true)"
    case "$command_line" in "$CODEX_EXE"*) return 0 ;; esac
    parent="$(/bin/ps -p "$current" -o ppid= 2>/dev/null | /usr/bin/awk '{$1=$1; print}')"
    case "$parent" in ''|*[!0-9]*) return 1 ;; esac
    [ "$parent" -ne "$current" ] || return 1
    current="$parent"
    depth=$((depth + 1))
  done
  return 1
}

port_belongs_to_codex() {
  local port="$1"
  local found_direct="false"
  local pid
  local command_line
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    command_line="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
    case "$command_line" in
      "$CODEX_EXE"*) found_direct="true" ;;
      *) pid_is_codex_descendant "$pid" || return 1 ;;
    esac
  done < <(listener_pids "$port")
  [ "$found_direct" = "true" ]
}

# Cheap: can we talk to a loopback DevTools HTTP endpoint?
cdp_http_ready() {
  local port="$1"
  /usr/bin/curl --noproxy '*' --silent --fail --max-time 1 \
    "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1
}

verified_cdp_endpoint() {
  local port="$1"
  # Prefer identity check, but accept loopback CDP if HTTP is healthy and a
  # ChatGPT/Codex process is listening (path case / helper PIDs can fail belongs).
  if port_belongs_to_codex "$port"; then
    cdp_http_ready "$port" || return 1
    return 0
  fi
  cdp_http_ready "$port" || return 1
  # Fallback: listener must still be ChatGPT-related.
  local pid command_line
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    command_line="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
    case "$command_line" in
      *ChatGPT*|*Codex*|*codex*) return 0 ;;
    esac
  done < <(listener_pids "$port")
  return 1
}

select_available_port() {
  local preferred="$1"
  local candidate="$preferred"
  local last=$((preferred + 100))
  [ "$last" -le 65535 ] || last=65535
  while [ "$candidate" -le "$last" ]; do
    if port_is_available "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate=$((candidate + 1))
  done
  fail "No free loopback port was found between $preferred and $last."
}

wait_for_cdp() {
  local port="$1"
  local deadline=$((SECONDS + 45))
  local last_note=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    # Fast path: HTTP up is enough to proceed once process identity is soft-ok.
    if cdp_http_ready "$port"; then
      if verified_cdp_endpoint "$port" || cdp_http_ready "$port"; then
        # If HTTP is up and ChatGPT is running, accept.
        if codex_is_running || verified_cdp_endpoint "$port"; then
          return 0
        fi
      fi
    fi
    if [ $((SECONDS - last_note)) -ge 8 ]; then
      last_note=$SECONDS
      printf 'Waiting for Codex debug port %s… (%ss)\n' "$port" "$SECONDS" >&2
    fi
    /bin/sleep 0.35
  done
  return 1
}

state_field() {
  local key="$1"
  "$NODE" -e '
    const fs = require("node:fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))[process.argv[2]];
    if (value !== undefined && value !== null) process.stdout.write(String(value));
  ' "$STATE_PATH" "$key"
}

write_state() {
  local port="$1"
  local injector_pid="$2"
  local injector_started_at="$3"
  local codex_pid="$4"
  local node_ver="${NODE_VERSION:-unknown}"
  local bundle="${CODEX_BUNDLE:-}"
  local exe="${CODEX_EXE:-}"
  local app_ver="${CODEX_VERSION:-}"
  local team="${CODEX_TEAM_ID:-}"
  local active_id=""
  active_id="$(active_theme_id 2>/dev/null || true)"
  "$NODE" -e '
    const fs = require("node:fs");
    const [file, version, port, pid, startedAt, injector, node, nodeVersion, bundle, exe, appVersion, teamId, root, themeDir, codexPid, arch, activeThemeId] = process.argv.slice(1);
    const state = {
      schemaVersion: 5,
      platform: `darwin-${arch}`,
      skinVersion: version,
      port: Number(port),
      injectorPid: Number(pid),
      injectorStartedAt: startedAt,
      injectorPath: injector,
      nodePath: node,
      nodeVersion,
      codexBundle: bundle,
      codexExe: exe,
      codexVersion: appVersion,
      codexTeamId: teamId,
      codexPid: Number(codexPid || 0),
      projectRoot: root,
      themeDir,
      activeThemeId: activeThemeId || null,
      createdAt: new Date().toISOString()
    };
    const temporary = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporary, file);
  ' "$STATE_PATH" "$SKIN_VERSION" "$port" "$injector_pid" "$injector_started_at" "$INJECTOR" "$NODE" "$node_ver" "$bundle" "$exe" "$app_ver" "$team" "$PROJECT_ROOT" "$THEME_DIR" "$codex_pid" "$(/usr/bin/uname -m)" "$active_id"
}

remove_injector_job() {
  local domain="gui/$(/usr/bin/id -u)"
  local deadline
  /bin/launchctl bootout "$domain/$INJECTOR_JOB_LABEL" >/dev/null 2>&1 || true
  /bin/launchctl remove "$INJECTOR_JOB_LABEL" >/dev/null 2>&1 || true
  deadline=$((SECONDS + 4))
  while /bin/launchctl print "$domain/$INJECTOR_JOB_LABEL" >/dev/null 2>&1 && [ "$SECONDS" -lt "$deadline" ]; do
    /bin/sleep 0.1
  done
}

write_injector_job_plist() {
  local port="$1"
  /usr/bin/python3 - "$INJECTOR_JOB_PLIST" "$INJECTOR_JOB_LABEL" "$NODE" "$INJECTOR" "$port" "$THEME_DIR" "$INJECTOR_LOG" "$INJECTOR_ERROR_LOG" "$PROJECT_ROOT" "$HOME" <<'PY'
import os, plistlib, sys
path, label, node, injector, port, theme_dir, out_log, err_log, working_dir, home = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": [node, injector, "--watch", "--port", port, "--theme-dir", theme_dir],
    "WorkingDirectory": working_dir,
    "EnvironmentVariables": {"HOME": home},
    "RunAtLoad": True,
    "KeepAlive": True,
    "ProcessType": "Interactive",
    "ThrottleInterval": 2,
    "StandardOutPath": out_log,
    "StandardErrorPath": err_log,
}
temporary = f"{path}.{os.getpid()}.tmp"
with open(temporary, "wb") as handle:
    plistlib.dump(payload, handle, fmt=plistlib.FMT_XML, sort_keys=False)
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
}

stop_recorded_injector() {
  remove_injector_job
  /bin/rm -f "$INJECTOR_JOB_PLIST" 2>/dev/null || true
  [ -f "$STATE_PATH" ] || return 0
  local pid
  local saved_start
  local saved_node
  local saved_injector
  local actual_start
  local command_line
  pid="$(state_field injectorPid 2>/dev/null || true)"
  # Already paused / no daemon
  if [ -z "${pid:-}" ] || [ "$pid" = "0" ]; then
    return 0
  fi
  /bin/kill -0 "$pid" 2>/dev/null || {
    return 0
  }
  saved_start="$(state_field injectorStartedAt 2>/dev/null || true)"
  saved_node="$(state_field nodePath 2>/dev/null || true)"
  saved_injector="$(state_field injectorPath 2>/dev/null || true)"
  # Soft identity check (macOS path case: /Users/Fei vs /Users/fei)
  local node_ok="true" inj_ok="true"
  if [ -n "$saved_node" ] && [ -n "${NODE:-}" ]; then
    [ "$(printf '%s' "$saved_node" | /usr/bin/tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$NODE" | /usr/bin/tr '[:upper:]' '[:lower:]')" ] || node_ok="false"
  fi
  if [ -n "$saved_injector" ] && [ -n "${INJECTOR:-}" ]; then
    [ "$(printf '%s' "$saved_injector" | /usr/bin/tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$INJECTOR" | /usr/bin/tr '[:upper:]' '[:lower:]')" ] || inj_ok="false"
  fi
  # If identity clearly wrong but process looks like our injector, still stop by cmdline.
  command_line="$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$command_line" in
    *injector.mjs*--watch*) ;;
    *)
      if [ "$node_ok" = "true" ] && [ "$inj_ok" = "true" ]; then
        :
      else
        # Stale PID that is not our injector — ignore
        return 0
      fi
      ;;
  esac
  if [ -n "$saved_start" ]; then
    actual_start="$(process_started_at "$pid")"
    if [ -n "$actual_start" ] && [ "$actual_start" != "$saved_start" ]; then
      # PID recycled — do not kill stranger
      return 0
    fi
  fi
  /bin/kill -TERM "$pid" 2>/dev/null || true
  local deadline=$((SECONDS + 6))
  while /bin/kill -0 "$pid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do /bin/sleep 0.2; done
  /bin/kill -KILL "$pid" 2>/dev/null || true
  return 0
}

launch_injector_daemon() {
  local port="$1"
  local pid=""
  local deadline
  local domain="gui/$(/usr/bin/id -u)"
  local bootstrap_error="$STATE_ROOT/launchctl-bootstrap.log"
  : > "$INJECTOR_LOG"
  : > "$INJECTOR_ERROR_LOG"
  remove_injector_job
  write_injector_job_plist "$port"
  : > "$bootstrap_error"

  # Bootstrap a session-scoped LaunchAgent from StateRoot. It persists after
  # this shell exits but is not placed in ~/Library/LaunchAgents, so it cannot
  # start at login or launch Codex on its own.
  if /bin/launchctl bootstrap "$domain" "$INJECTOR_JOB_PLIST" 2>"$bootstrap_error"; then
    /bin/launchctl kickstart -k "$domain/$INJECTOR_JOB_LABEL" >/dev/null 2>&1 || true
    deadline=$((SECONDS + 8))
    while [ "$SECONDS" -lt "$deadline" ]; do
      pid="$(/bin/launchctl print "$domain/$INJECTOR_JOB_LABEL" 2>/dev/null \
        | /usr/bin/awk '/^[[:space:]]*pid = [0-9]+/{print $3; exit}')"
      if [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null; then
        printf '%s\n' "$pid"
        return 0
      fi
      /bin/sleep 0.2
    done
  fi

  # Do not report success with a short-lived child process. A failed bootstrap
  # leaves the plist and launchctl error available for diagnosis and rollback.
  remove_injector_job
  fail "The injector LaunchAgent did not start. See $bootstrap_error, $INJECTOR_ERROR_LOG, and $INJECTOR_LOG"
}

# Resolve Node quickly: prefer known Codex path, else full runtime check.
ensure_node_runtime() {
  local candidate=""
  local bundle=""
  if [ -n "${NODE:-}" ] && [ -x "${NODE:-}" ]; then
    bundle="$(codex_bundle_from_node "$NODE")"
    if [ -n "$bundle" ] && set_codex_bundle_metadata "$bundle"; then
      NODE_VERSION="$("$NODE" --version 2>/dev/null || echo unknown)"
      RUNTIME_NODE="$NODE"
      export NODE NODE_VERSION RUNTIME_NODE
      return 0
    fi
  fi
  for candidate in \
    "/Applications/Codex.app/Contents/Resources/cua_node/bin/node" \
    "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
    "$HOME/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
    "$HOME/Applications/Codex.app/Contents/Resources/cua_node/bin/node"
  do
    [ -x "$candidate" ] || continue
    bundle="$(codex_bundle_from_node "$candidate")"
    [ -n "$bundle" ] || continue
    set_codex_bundle_metadata "$bundle" || continue
    NODE="$candidate"
    RUNTIME_NODE="$candidate"
    NODE_VERSION="$("$NODE" --version 2>/dev/null || echo unknown)"
    export NODE RUNTIME_NODE NODE_VERSION
    return 0
  done
  discover_codex_app
  require_macos_runtime
}

# Fast path when CDP is already open: restart injector + one-shot inject.
# Returns 0 on success, 1 if CDP is not ready (caller should full-start).
hot_reapply_theme() {
  local port="${1:-9341}"
  local timeout_ms="${2:-8000}"

  local cdp_ready="false"
  local attempt
  for attempt in 1 2 3 4 5; do
    if verified_cdp_endpoint "$port"; then
      cdp_ready="true"
      break
    fi
    /bin/sleep 0.25
  done
  [ "$cdp_ready" = "true" ] || return 1
  ensure_node_runtime || return 1

  stop_recorded_injector 2>/dev/null || true
  # Kill every leftover injector for this path. A late --once from the previous
  # theme can otherwise overwrite the new stylesheet after reporting success.
  local old
  while IFS= read -r old; do
    [ -n "$old" ] || continue
    /bin/kill -TERM "$old" 2>/dev/null || true
  done < <(/bin/ps -axo pid=,command= | /usr/bin/awk -v inj="$INJECTOR" '
    index($0, inj) && (index($0, "--watch") || index($0, "--once") || index($0, "--verify")) { print $1 }
  ')
  /bin/sleep 0.3

  # Apply and fully verify the selected theme before starting the watcher. This
  # makes the success notification describe the live DOM, not only disk state.
  "$NODE" "$INJECTOR" --once --port "$port" --theme-dir "$THEME_DIR" --timeout-ms "$timeout_ms" >/dev/null 2>&1 \
    || return 1

  local inj_pid
  inj_pid="$(launch_injector_daemon "$port")"
  /bin/sleep 0.35
  /bin/kill -0 "$inj_pid" 2>/dev/null || return 1

  local started_at codex_pid
  started_at="$(process_started_at "$inj_pid")"
  codex_pid="$(codex_main_pids 2>/dev/null | /usr/bin/head -n 1)"
  [ -n "$started_at" ] || started_at="$(/bin/date)"
  write_state "$port" "$inj_pid" "$started_at" "${codex_pid:-0}"
  return 0
}

# Always tear down any leftover launchd babysitter for the themed Codex process.
# Older builds used `launchctl submit` which can relaunch Codex after the user quits
# or after SwiftBar exits — that is unexpected and unwanted.
release_codex_launchd_job() {
  /bin/launchctl remove "gui/$(/usr/bin/id -u)/$CODEX_APP_JOB_LABEL" >/dev/null 2>&1 || true
  /bin/launchctl remove "$CODEX_APP_JOB_LABEL" >/dev/null 2>&1 || true
}

launch_codex_with_cdp() {
  local port="$1"
  : > "$APP_LOG"
  : > "$APP_ERROR_LOG"
  release_codex_launchd_job
  # Start as a normal user process (NOT launchctl submit). submit keeps a job
  # that will restart Codex when the window is closed.
  /usr/bin/open -na "$CODEX_BUNDLE" --args \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$port" \
    >>"$APP_LOG" 2>>"$APP_ERROR_LOG" || true
  # `open` returns before the Electron main process is visible. Wait briefly
  # before deciding launch failed; otherwise the fallback starts a duplicate.
  local deadline=$((SECONDS + 5))
  while ! codex_is_running && [ "$SECONDS" -lt "$deadline" ]; do /bin/sleep 0.2; done
  # Fallback only when the normal application launch produced no main process.
  if ! codex_is_running; then
    /usr/bin/nohup "$CODEX_EXE" \
      --remote-debugging-address=127.0.0.1 \
      --remote-debugging-port="$port" \
      >>"$APP_LOG" 2>>"$APP_ERROR_LOG" &
  fi
}

launch_codex_normally() {
  release_codex_launchd_job
  /usr/bin/open -na "$CODEX_BUNDLE"
}
