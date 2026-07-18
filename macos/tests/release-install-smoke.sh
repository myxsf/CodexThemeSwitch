#!/bin/bash

set -euo pipefail
trap 'status=$?; printf "FAIL: macOS release smoke line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2' ERR

ARCHIVE="${1:?Usage: release-install-smoke.sh <macos-release.zip>}"
[ -f "$ARCHIVE" ] || { printf 'Release archive not found: %s\n' "$ARCHIVE" >&2; exit 1; }

WORK="$(/usr/bin/mktemp -d /private/tmp/codex-theme-release-smoke.XXXXXX)"
trap '/bin/rm -rf "$WORK"' EXIT
/usr/bin/ditto -x -k "$ARCHIVE" "$WORK/archive"
APP="$WORK/archive/Codex 主题衣橱.app"
[ -d "$APP" ] || { printf 'Wardrobe app missing from archive.\n' >&2; exit 1; }

/usr/bin/codesign --verify --deep --strict "$APP"
ARCHS="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/CodexThemeSwitcher")"
case " $ARCHS " in *' arm64 '*) ;; *) printf 'arm64 slice missing: %s\n' "$ARCHS" >&2; exit 1 ;; esac
case " $ARCHS " in *' x86_64 '*) ;; *) printf 'x86_64 slice missing: %s\n' "$ARCHS" >&2; exit 1 ;; esac

ENGINE="$APP/Contents/Resources/Engine"
NODE="${CODEX_NODE:-/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node}"
[ -x "$NODE" ] || { printf 'Signed Codex Node was not found: %s\n' "$NODE" >&2; exit 1; }
HOME_DIR="$WORK/home"
/bin/mkdir -p "$HOME_DIR/.codex"
/usr/bin/printf '%s\n' \
  'model = "gpt-5"' \
  '' \
  '[desktop]' \
  'appearanceTheme = "system"' \
  'keepMe = true' > "$HOME_DIR/.codex/config.toml"
/bin/cp "$HOME_DIR/.codex/config.toml" "$WORK/original-config.toml"

HOME="$HOME_DIR" "$ENGINE/scripts/install-dream-skin-macos.sh" --port 19431 --no-launchers --no-launch
INSTALLED="$HOME_DIR/.codex/codex-dream-skin-studio"
STATE="$HOME_DIR/Library/Application Support/CodexDreamSkinStudio"
[ -x "$INSTALLED/scripts/theme-macos.sh" ]
[ -s "$INSTALLED/.engine-manifest.sha256" ]
/usr/bin/cmp -s "$ENGINE/.engine-manifest.sha256" "$INSTALLED/.engine-manifest.sha256"

for id in skin-01 skin-02 skin-03 skin-04 skin-05 skin-06 skin-07 skin-08 qq2007; do
  [ -f "$STATE/themes/$id/theme.json" ]
done

HOME="$HOME_DIR" "$INSTALLED/scripts/theme-macos.sh" list > "$WORK/themes.txt"
for id in skin-01 skin-02 skin-03 skin-04 skin-05 skin-06 skin-07 skin-08 qq2007; do
  /usr/bin/grep -q "^$id" "$WORK/themes.txt"
done

HOME="$HOME_DIR" "$INSTALLED/scripts/switch-theme-macos.sh" --id skin-08 --no-apply
[ "$(/usr/bin/tr -d '[:space:]' < "$STATE/active-theme-id")" = "skin-08" ]
/usr/bin/python3 - "$STATE/theme/theme.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    assert json.load(handle)["id"] == "skin-08"
PY

HOME="$HOME_DIR" "$NODE" "$INSTALLED/scripts/theme-config.mjs" restore \
  "$HOME_DIR/.codex/config.toml" "$STATE/theme-backup.json" >/dev/null
/usr/bin/cmp -s "$HOME_DIR/.codex/config.toml" "$WORK/original-config.toml"

printf 'PASS: macOS release archive, Universal signature, isolated install, all themes, staged switch, and config restore.\n'
