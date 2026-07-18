#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUTPUT="${1:-$HOME/Desktop/Codex 主题衣橱.app}"
BUNDLE_ID="com.xiangzai.codex-theme-switcher"
TMP="$(/usr/bin/mktemp -d /tmp/codex-theme-switcher.XXXXXX)"
APP="$TMP/Codex 主题衣橱.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
trap '/bin/rm -rf "$TMP"' EXIT

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR
SWIFTC="$(/usr/bin/xcrun --find swiftc 2>/dev/null || true)"
XCODE_SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [ -d "$XCODE_SDK" ]; then
  SDKROOT="$XCODE_SDK"
else
  SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
fi
[ -x "$SWIFTC" ] || { printf 'Xcode Swift compiler was not found.\n' >&2; exit 1; }
[ -d "$SDKROOT" ] || { printf 'A matching Xcode macOS SDK was not found.\n' >&2; exit 1; }

if [ -e "$OUTPUT" ]; then
  existing_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$OUTPUT/Contents/Info.plist" 2>/dev/null || true)"
  [ "$existing_id" = "$BUNDLE_ID" ] || { printf 'Refusing to overwrite unrelated app: %s\n' "$OUTPUT" >&2; exit 1; }
fi

RELAUNCH="false"
if /usr/bin/pgrep -f '/Codex 主题衣橱\.app/Contents/MacOS/CodexThemeSwitcher( |$)' >/dev/null 2>&1; then
  RELAUNCH="true"
fi

/bin/mkdir -p "$MACOS" "$RESOURCES"
/bin/cp "$ROOT/switcher/Info.plist" "$CONTENTS/Info.plist"
[ -f "$ROOT/../themes/catalog.json" ] || { printf 'Theme catalog was not found.\n' >&2; exit 1; }
/bin/cp "$ROOT/../themes/catalog.json" "$RESOURCES/ThemeCatalog.json"

# Ship the trusted engine with the wardrobe. The app installs this bundle on
# first use or when VERSION changes, so a new catalog never points at theme
# packs that an older local engine cannot activate.
/bin/mkdir -p "$RESOURCES/Engine"
/usr/bin/rsync -a \
  "$ROOT/assets" \
  "$ROOT/scripts" \
  "$ROOT/themes" \
  "$ROOT/VERSION" \
  "$ROOT/package.json" \
  "$RESOURCES/Engine/"
/bin/cp "$ROOT/../themes/catalog.json" "$RESOURCES/Engine/themes/catalog.json"
/usr/bin/python3 - "$RESOURCES/Engine" <<'PY'
import hashlib, os, sys

root = os.path.realpath(sys.argv[1])
manifest = os.path.join(root, ".engine-manifest.sha256")
entries = []
for directory, names, files in os.walk(root):
    names[:] = sorted(name for name in names if not name.startswith("."))
    for name in sorted(files):
        path = os.path.join(directory, name)
        if path == manifest or name.startswith("."):
            continue
        relative = os.path.relpath(path, root).replace(os.sep, "/")
        digest = hashlib.sha256()
        with open(path, "rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        entries.append(f"{digest.hexdigest()}  {relative}")
with open(manifest, "w", encoding="utf-8", newline="\n") as handle:
    handle.write("\n".join(entries) + "\n")
PY
/bin/chmod 700 "$RESOURCES/Engine/scripts"/*.sh

# The wardrobe preview uses the same validated art payload as the injected
# theme. Gallery composites are intentionally not bundled because they can
# mislead users when official Codex layout constraints differ from a mockup.
/usr/bin/python3 - "$ROOT/.." "$RESOURCES" <<'PY'
import json, os, shutil, sys
repo, resources = map(os.path.realpath, sys.argv[1:])
with open(os.path.join(repo, "themes", "catalog.json"), encoding="utf-8") as handle:
    catalog = json.load(handle)
for theme in catalog.get("themes", []):
    image = theme.get("image")
    if not isinstance(image, str) or image.startswith("builtin://"):
        continue
    source = os.path.normpath(os.path.join(repo, image))
    if os.path.commonpath([repo, source]) != repo or not os.path.isfile(source):
        raise SystemExit(f"Invalid catalog theme art: {image}")
    extension = os.path.splitext(source)[1].lower()
    if extension not in {".jpg", ".jpeg", ".png"}:
        raise SystemExit(f"Unsupported theme art format: {image}")
    target_extension = "jpg" if extension in {".jpg", ".jpeg"} else "png"
    shutil.copy2(source, os.path.join(resources, f"theme-art-{theme['id']}.{target_extension}"))
PY

for arch in arm64 x86_64; do
  CLANG_MODULE_CACHE_PATH="$TMP/ModuleCache-$arch" SWIFT_MODULE_CACHE_PATH="$TMP/ModuleCache-$arch" \
  "$SWIFTC" -swift-version 5 -parse-as-library -O \
    -sdk "$SDKROOT" -target "$arch-apple-macosx13.0" -module-cache-path "$TMP/ModuleCache-$arch" \
    -framework SwiftUI -framework AppKit \
    "$ROOT/switcher/ThemeSwitcherApp.swift" \
    -o "$TMP/CodexThemeSwitcher-$arch"
done
/usr/bin/lipo -create "$TMP/CodexThemeSwitcher-arm64" "$TMP/CodexThemeSwitcher-x86_64" -output "$MACOS/CodexThemeSwitcher"

/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null
/usr/bin/xattr -cr "$APP"
if [ "$RELAUNCH" = "true" ]; then
  /usr/bin/osascript -e 'tell application id "com.xiangzai.codex-theme-switcher" to quit' >/dev/null 2>&1 || true
  for _ in $(/usr/bin/jot 40); do
    /usr/bin/pgrep -f '/Codex 主题衣橱\.app/Contents/MacOS/CodexThemeSwitcher( |$)' >/dev/null 2>&1 || break
    /bin/sleep 0.1
  done
fi
/bin/rm -rf "$OUTPUT"
/bin/mv "$APP" "$OUTPUT"
[ "$RELAUNCH" = "true" ] && /usr/bin/open "$OUTPUT"
printf 'Created %s\n' "$OUTPUT"
