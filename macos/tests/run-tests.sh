#!/bin/bash

set -euo pipefail
trap 'status=$?; printf "FAIL: macOS static test line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$status" >&2' ERR
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
NODE="${NODE:-/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node}"
[ -x "$NODE" ] || { printf 'Codex bundled Node.js was not found: %s\n' "$NODE" >&2; exit 1; }

while IFS= read -r file; do /bin/bash -n "$file"; done < <(
  /usr/bin/find "$ROOT" -type f \( -name '*.sh' -o -name '*.command' \) \
    ! -path '*/release/*' -print
)
while IFS= read -r file; do "$NODE" --check "$file" >/dev/null; done < <(
  /usr/bin/find "$ROOT/scripts" "$ROOT/assets" "$ROOT/tests" -type f \( -name '*.mjs' -o -name '*.js' \) -print
)
[ -f "$ROOT/tests/sidebar-resize-live.mjs" ]
[ -f "$ROOT/tests/contrast-audit-live.mjs" ]

if /usr/bin/grep -R -n -E 'dream-skin-skin|DREAM_SKIN_SKIN|1\.0\.0-rc2' \
  "$ROOT/scripts" "$ROOT/assets" >/dev/null; then
  printf 'Legacy release-candidate identifiers remain in runtime files.\n' >&2
  exit 1
fi
if /usr/bin/grep -R -n -E '(writeFile|rename|copyFile|rm).*app\.asar' "$ROOT/scripts" >/dev/null; then
  printf 'A runtime script appears to mutate app.asar.\n' >&2
  exit 1
fi

"$NODE" "$ROOT/scripts/injector.mjs" --check-payload >/dev/null

CATALOG="$ROOT/../themes/catalog.json"
[ -f "$CATALOG" ] || { printf 'Shared theme catalog is missing.\n' >&2; exit 1; }
while IFS=$'\t' read -r theme_id expected_profile expected_appearance; do
  [ -n "$theme_id" ] || continue
  theme_dir="$ROOT/themes/$theme_id"
  [ -f "$theme_dir/theme.json" ] || {
    printf 'Bundled theme is missing: %s\n' "$theme_id" >&2
    exit 1
  }
  THEME_PAYLOAD_JSON="$("$NODE" "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$theme_dir")"
  "$NODE" -e '
    const value = JSON.parse(process.argv[1]);
    const expected = process.argv[2];
    const appearance = process.argv[3];
    const themeId = process.argv[4];
    if (!value.pass || value.profile !== expected || value.appearance !== appearance ||
        !value.art || !value.art.position || !value.art.size || value.payloadBytes < 1 || value.imageBytes < 0) process.exit(1);
    const variants = {"skin-05":"enfp", "skin-06":"purple-night", "skin-07":"miku"};
    if (variants[themeId]) {
      if (value.visual?.layoutVariant !== variants[themeId] || value.visual?.cards?.length !== 4) process.exit(1);
      if (value.visual.cards.some((card) => !["prompt", "plugins"].includes(card.action) || card.prompt.length > 240)) process.exit(1);
      if (!value.visual.sidebar?.brand || value.visual.sidebar.footerText !== "翔仔正在工作ing") process.exit(1);
    }
  ' "$THEME_PAYLOAD_JSON" "$expected_profile" "$expected_appearance" "$theme_id"
done < <("$NODE" -e '
  const fs = require("fs");
  const catalog = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (catalog.schemaVersion !== 1 || !Array.isArray(catalog.themes)) process.exit(1);
  const original = catalog.themes.find((theme) => theme.id === "original");
  if (!original || original.kind !== "original" || original.profile !== "off") process.exit(1);
  for (const theme of catalog.themes) {
    if (theme.id === "original" || theme.enabled === false || !(theme.platforms || []).includes("darwin")) continue;
    process.stdout.write(`${theme.id}\t${theme.profile}\t${theme.appearance}\n`);
  }
' "$CATALOG")

for hero in \
  "$ROOT/themes/skin-05/inspiration-universe-hero.jpg" \
  "$ROOT/themes/skin-06/purple-night-hero.png" \
  "$ROOT/themes/skin-07/miku-hero.png"; do
  [ "$(/usr/bin/sips -g pixelWidth "$hero" | /usr/bin/awk '/pixelWidth/ {print $2}')" = "2168" ]
  [ "$(/usr/bin/sips -g pixelHeight "$hero" | /usr/bin/awk '/pixelHeight/ {print $2}')" = "752" ]
done

/usr/bin/grep -q 'data-dream-theme' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'data-dream-theme-id' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'data-dream-palette' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'qq2007-shell' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'html\[data-dream-theme="qq2007"\]' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'launchctl bootstrap' "$ROOT/scripts/common-macos.sh"
/usr/bin/grep -q 'KeepAlive' "$ROOT/scripts/common-macos.sh"
! /usr/bin/grep -q 'console\.error(`\[dream-skin\] rejected non-Codex' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q -- '-webkit-app-region: drag' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q -- '-webkit-app-region: drag' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'qq2007-window-buttons.*aria-hidden="true"' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'dreamChromeSchema' "$ROOT/assets/renderer-inject.js"
! /usr/bin/grep -q 'data-dream-window-action' "$ROOT/assets/renderer-inject.js"
! /usr/bin/grep -q 'Runtime.addBinding' "$ROOT/scripts/injector.mjs"
! /usr/bin/grep -q 'enableWindowActions' "$ROOT/scripts/injector.mjs"
! /usr/bin/grep -q 'AXZoomWindow' "$ROOT/scripts/injector.mjs"
! /usr/bin/grep -q 'Browser.setWindowBounds' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'dragRegionAppRegion' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'qqResponsivePass' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q -- '--window-smoke' "$ROOT/scripts/injector.mjs"
! /usr/bin/grep -q '@media (max-width: 900px)' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'referenceWidth = 1440' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'referenceHeight = 1080' "$ROOT/assets/renderer-inject.js"
"$NODE" - "$ROOT/assets/renderer-inject.js" "$ROOT/assets/qq2007.css" <<'NODE'
const fs = require("fs");
const rendererPath = process.argv[2];
const qqCssPath = process.argv[3];
const renderer = fs.readFileSync(rendererPath, "utf8");
const qqCss = fs.readFileSync(qqCssPath, "utf8");
const fail = (message) => {
  process.stderr.write(`QQ2007 renderer regression: ${message}\n`);
  process.exit(1);
};

if (/\bconst\s+QQ_CARD_SET\b/.test(renderer)) {
  fail("QQ-specific synthetic suggestion cards must not be defined");
}
const extraCardCreation = renderer.indexOf("extraCard = document.createElement");
if (extraCardCreation < 0) fail("the native plugin-card compatibility path disappeared");
const extraCardGuard = renderer.slice(Math.max(0, extraCardCreation - 500), extraCardCreation);
if (!/THEME_PROFILE\s*!==\s*["']qq2007["']/.test(extraCardGuard)) {
  fail("QQ2007 must be explicitly excluded before creating dream-skin-extra-card");
}
if (!renderer.includes("!button.closest('#dream-skin-extra-card')")) {
  fail("synthetic extra card must not count as a native suggestion card");
}
for (const fakeCopy of ["Codex 工作台 · 选择真实操作开始", "快捷操作"]) {
  if (renderer.includes(fakeCopy) || qqCss.includes(fakeCopy)) {
    fail(`synthetic copy remains: ${fakeCopy}`);
  }
}
if (/setInterval\s*\(\s*ensure\s*,\s*4000\s*\)/.test(renderer)) {
  fail("the unconditional four-second ensure timer remains");
}

const observerNames = [...renderer.matchAll(
  /\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*new\s+MutationObserver\s*\(/g,
)].map((match) => match[1]);
if (observerNames.length < 1) fail("MutationObserver lifecycle guard disappeared");
let observedConfigurationCount = 0;
for (const name of observerNames) {
  const observePattern = new RegExp(
    `${name}\\.observe\\s*\\([\\s\\S]*?,\\s*\\{([\\s\\S]*?)\\}\\s*\\);`,
    "g",
  );
  for (const match of renderer.matchAll(observePattern)) {
    observedConfigurationCount += 1;
    const options = match[1];
    if (/\bsubtree\s*:\s*true\b/.test(options) && /\battributes\s*:\s*true\b/.test(options)) {
      fail(`${name} observes attributes across the full document subtree`);
    }
  }
}
if (observedConfigurationCount < 1) fail("MutationObserver options could not be audited");
if (renderer.includes("getComputedStyle(root).colorScheme")) fail("Shell detection must not read skin-overridden colorScheme");
if (renderer.includes("const samples = [")) fail("Shell detection must not vote from skin-overridden surfaces");
if (!renderer.includes('previous?.version === VERSION') || !renderer.includes('previous?.profile === "qq2007"')) {
  fail("QQ sidebar width may only survive a same-version QQ reinjection");
}
if (!renderer.includes('aside.style.width = `${qqExpectedSidebarWidth}px`')) {
  fail("a fresh QQ injection must restore the reference sidebar width once");
}
if (!renderer.includes('qqShouldResetSidebarWidth = false')) {
  fail("the reference-width reset must not prevent later native splitter drags");
}
if (!renderer.includes('qqSidebarResetTimer = setTimeout') || !renderer.includes('}, 2400)')) {
  fail("late Codex sidebar restoration must be contained during initialization");
}
if (!renderer.includes('previous?.qqSidebarInitializing !== true') ||
    !renderer.includes('qqSidebarInitializing: qqShouldResetSidebarWidth')) {
  fail("reinjection during QQ initialization must continue the reference-width guard");
}
if (!renderer.includes('previous?.qqSidebarResetTimer') || !renderer.includes('clearTimeout(qqSidebarResetTimer)')) {
  fail("QQ sidebar initialization timers must be cleaned up across reinjection");
}
if (!renderer.includes('qqSidebarInteractionController = new AbortController()') ||
    !renderer.includes('qqUserResizeGraceUntil = performance.now() + 650') ||
    !renderer.includes('aside.style.width = `${qqExpectedSidebarWidth}px`')) {
  fail("only real native-separator input may change the persisted QQ sidebar ratio");
}
NODE

TMP="$(/usr/bin/mktemp -d /tmp/codex-dream-skin-tests.XXXXXX)"
trap '/bin/rm -rf "$TMP"' EXIT
/bin/mkdir -p "$TMP/theme"
/bin/cp "$ROOT/assets/portal-hero.png" "$TMP/theme/background.png"
"$NODE" "$ROOT/scripts/write-theme.mjs" custom --output-dir "$TMP/theme" \
  --image background.png --name '测试主题' --tagline '测试口号' --quote 'TEST' \
  --accent '#11aa55' --secondary '#22bbcc' --highlight '#663399' >/dev/null
PAYLOAD_JSON="$("$NODE" "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$TMP/theme")"
"$NODE" -e '
  const value = JSON.parse(process.argv[1]);
  if (!value.pass || value.themeName !== "测试主题" || value.imageBytes < 1) process.exit(1);
' "$PAYLOAD_JSON"
"$NODE" -e '
  const fs = require("fs");
  const file = process.argv[1];
  const value = JSON.parse(fs.readFileSync(file, "utf8"));
  value.id = "palette-only";
  value.name = "纯配色主题";
  value.image = null;
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
' "$TMP/theme/theme.json"
PALETTE_PAYLOAD_JSON="$("$NODE" "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$TMP/theme")"
"$NODE" -e '
  const value = JSON.parse(process.argv[1]);
  if (!value.pass || value.imageBytes !== 0 || value.payloadBytes < 1) process.exit(1);
' "$PALETTE_PAYLOAD_JSON"
"$NODE" "$ROOT/scripts/write-theme.mjs" reset-demo --output-dir "$TMP/theme" >/dev/null
[ ! -e "$TMP/theme" ]

CONFIG="$TMP/config.toml"
BACKUP="$TMP/theme-backup.json"
/usr/bin/printf '%s\n' \
  'model = "gpt-5"' \
  '' \
  '[desktop]' \
  'appearanceTheme = "system"' \
  'appearanceDarkCodeThemeId = "vscode-dark"' \
  'keepMe = true' > "$CONFIG"
/bin/cp "$CONFIG" "$TMP/original.toml"
"$NODE" "$ROOT/scripts/theme-config.mjs" install "$CONFIG" "$BACKUP" >/dev/null
/usr/bin/cmp -s "$CONFIG" "$TMP/original.toml"
"$NODE" "$ROOT/scripts/theme-config.mjs" restore "$CONFIG" "$BACKUP" >/dev/null
/usr/bin/cmp -s "$CONFIG" "$TMP/original.toml"

/usr/bin/plutil -lint "$ROOT/switcher/Info.plist" >/dev/null
[ -s "$ROOT/switcher/ThemeSwitcherApp.swift" ]
/usr/bin/grep -q 'start-dream-skin-macos.sh' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q -- '--restart-existing' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'activate_codex_window' "$ROOT/scripts/common-macos.sh"
/usr/bin/grep -q 'codex_bundle_from_node' "$ROOT/scripts/common-macos.sh"
/usr/bin/grep -q 'set_codex_bundle_metadata' "$ROOT/scripts/common-macos.sh"
! /usr/bin/grep -A8 '^activate_codex_window()' "$ROOT/scripts/common-macos.sh" | /usr/bin/grep -q 'fail '
! /usr/bin/grep -A50 '^ensure_node_runtime()' "$ROOT/scripts/common-macos.sh" | /usr/bin/grep -q ': "${CODEX_BUNDLE:=/Applications/Codex.app}"'
/usr/bin/grep -q '^activate_codex_window$' "$ROOT/scripts/start-dream-skin-macos.sh"
/usr/bin/grep -A2 'if hot_reapply_theme' "$ROOT/scripts/switch-theme-macos.sh" | /usr/bin/grep -q 'activate_codex_window'
/usr/bin/grep -q 'verifyOpenedCodex' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'bundledEngineDiffers' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '\.engine-manifest\.sha256' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '\.engine-manifest\.sha256' "$ROOT/scripts/build-theme-switcher-macos.sh"
/usr/bin/grep -q 'resolvedThemeId' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'hasThemeMismatch' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'DispatchQueue.global(qos: \.utility)' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'cancelActiveTask' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'compactTaskError' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'confirmAppliedTheme' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'lineLimit(2)' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'wardrobe-error.log' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'effectiveStatusScript' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '\["--verify", "--deep", "--strict", appURL.path\]' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '!store.appIntegrityOk' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'securityIntegrityOk == true && statusIntegrityOk != false' "$ROOT/switcher/ThemeSwitcherApp.swift"
! /usr/bin/grep -q 'status.appIntegrityOk ?? true' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '操作超时' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '取消并检测' "$ROOT/switcher/ThemeSwitcherApp.swift"
! /usr/bin/grep -A12 'self.message = "主题引擎已更新到' "$ROOT/switcher/ThemeSwitcherApp.swift" | /usr/bin/grep -q 'self.refresh()'
/usr/bin/grep -q 'ThemeCatalog' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'ScrollView(.horizontal' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'colorScheme' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'accessibleForeground' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'ViewThatFits' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '@Binding var index' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '当前正在使用' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '主题素材预览' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'Codex 未运行' "$ROOT/switcher/ThemeSwitcherApp.swift"
! /usr/bin/grep -q 'Codex 已启动' "$ROOT/switcher/ThemeSwitcherApp.swift"
! /usr/bin/grep -q '\.scaleEffect' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '作者 myxsf' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '禁止开源转卖与盗版' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-palette="light"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--color-token-main-surface-primary: var(--ds-panel)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--color-token-text-secondary: color-mix' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--ds-on-accent:' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'from-token-main-surface-primary' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'composerDarkLayers' "$ROOT/tests/contrast-audit-live.mjs"
/usr/bin/grep -q 'sendContrast' "$ROOT/tests/contrast-audit-live.mjs"
/usr/bin/grep -q 'dream-skin-card-visual' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'data-dream-layout' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'data-dream-card-index' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'fillComposerPrompt' "$ROOT/assets/renderer-inject.js"
! /usr/bin/grep -q 'const nativeLines' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'CARD_SET_BY_THEME' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'dream-skin-plugin-card' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'let visual = chrome.querySelector' "$ROOT/assets/renderer-inject.js"
! /usr/bin/grep -q 'chrome.querySelectorAll(".dream-skin-card-visual").forEach((node) => node.remove());$' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'aside.app-shell-left-panel :where(span, p, a, strong, small, label)' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'data-dream-page="home"' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'position: relative !important' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'data-dream-palette="dark"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-palette="light".*main.main-surface:not(.dream-skin-home-shell)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-palette="dark".*main.main-surface:not(.dream-skin-home-shell)' "$ROOT/assets/dream-skin.css"
! /usr/bin/grep -q '^html.codex-dream-skin\[data-dream-shell="light"\].*灵感脑暴' "$ROOT/assets/dream-skin.css"
! /usr/bin/grep -q '^html.codex-dream-skin \*,' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'justify-content: flex-start !important' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'container-name: dream-main' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'container-type: inline-size' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--thread-content-max-width: min(1180px, calc(100% - 44px))' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q '@container dream-main (max-width: 920px)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'margin-top: 0 !important' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'transform: none !important' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'group\\/project-selector > button:not(:disabled)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'background-size: 100% auto !important' "$ROOT/assets/dream-skin.css"
! /usr/bin/grep -q '^html\[data-dream-theme="qq2007"\] \*,' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'border: 1px solid #6f98b8' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'new ResizeObserver' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'qqSidebarRatio' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'sidebar-resize-handle-line' "$ROOT/assets/qq2007.css"
! /usr/bin/grep -q 'data-dream-qq-splitter' "$ROOT/assets/renderer-inject.js"
! /usr/bin/grep -q 'pointer-events: none.*qq-splitter' "$ROOT/assets/qq2007.css"
! /usr/bin/grep -q 'min-width: var(--qq-left) !important' "$ROOT/assets/qq2007.css"
! /usr/bin/grep -q 'max-width: var(--qq-left) !important' "$ROOT/assets/qq2007.css"
/usr/bin/grep -A12 '> \.max-w-full\.overflow-hidden' "$ROOT/assets/qq2007.css" | /usr/bin/grep -q 'min-width: 0 !important'
/usr/bin/grep -q 'data-pip-anchor-host="codex-main-thread"' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q -- '--thread-wide-block-inline-shift: 0px !important' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q '作者 myxsf · 禁止开源转卖与盗版' "$ROOT/assets/qq2007.css"
/usr/bin/grep -q 'const MAX_ART_BYTES = 16 \* 1024 \* 1024' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'Unsupported trusted theme profile' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'result.suggestions.y + result.suggestions.height <= result.composer.y' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'const qqSuggestionsPass = !result.suggestions' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'result.qqCanvas?.main?.visible' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'qqSidebarWidthSynced' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'app-shell-main-content-viewport' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'thread-scroll-container' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'LAST_VERIFY_JSON' "$ROOT/scripts/start-dream-skin-macos.sh"
/usr/bin/grep -q 'LAST_VERIFY_ERROR_LOG' "$ROOT/scripts/start-dream-skin-macos.sh"
! /usr/bin/grep -q 'Injection verification failed. The injector was stopped' "$ROOT/scripts/start-dream-skin-macos.sh"
/usr/bin/grep -q '(!result.sidebar || result.sidebar.x >= result.qqCanvas.left)' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'markers.shell && markers.main && (markers.composer || markers.sidebar)' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q ':has(.composer-surface-chrome)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-layout="enfp"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-layout="purple-night"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-layout="miku"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--ds-gallery-hero-ratio: 0.34686' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q '@media (max-height: 820px)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-layout="purple-night".*main.main-surface' "$ROOT/assets/dream-skin.css"
! /usr/bin/grep -A6 'group\\/project-selector' "$ROOT/assets/dream-skin.css" | /usr/bin/grep -q 'display: none !important'
/usr/bin/grep -q 'data-app-action-sidebar-thread-row' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'padding-right: 58px !important' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'gap: 8px !important' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'padding-top: 0 !important' "$ROOT/assets/dream-skin.css"
! /usr/bin/grep -q 'background-size: 100% 100% !important' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'Unified eight-theme home flow' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--ds-home-composer-slot-h: 168px' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-theme-id="skin-08".*composer-surface-chrome' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '-webkit-text-fill-color: #f3ebdd' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'data-dream-theme-id="skin-01".*data-dream-theme-id="skin-03"' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'dream-skin-home \[data-feature="game-source"\]' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '-webkit-text-fill-color: var(--ds-hero-copy)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q 'galleryFlowPass' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'cardProjectGap >= 8' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'cardProjectGap <= 72' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'projectComposerGap >= 6' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'trailingWhitespaceRatio' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'trailingWhitespaceRatio <= 0.12' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'layoutResizeObserver = new ResizeObserver' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'scheduleLayoutSync' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'style.textContent !== cssText' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'instanceToken: INSTANCE_TOKEN' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'div.z-50' "$ROOT/assets/renderer-inject.js"
/usr/bin/grep -q 'index($0, "--once")' "$ROOT/scripts/common-macos.sh"
/usr/bin/grep -q 'for attempt in 1 2 3 4 5' "$ROOT/scripts/common-macos.sh"
/usr/bin/grep -q -- '--ds-tall-hero-ratio: 0.37461' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -q -- '--ds-home-card-h: clamp(262px, 25vh, 278px)' "$ROOT/assets/dream-skin.css"
/usr/bin/grep -A2 'data-dream-theme-id="skin-08".*dream-skin-home' "$ROOT/assets/dream-skin.css" | /usr/bin/grep -q -- '--ds-home-card-h: 298px'
/usr/bin/grep -q 'result.composer.height <= 132' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'result.projectButton?.visible' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'result.projectButton.y + result.projectButton.height <= result.composer.y - 6' "$ROOT/scripts/injector.mjs"
/usr/bin/grep -q 'func refresh(deep: Bool = true)' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'refresh(deep: false)' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/awk '/if \[ "\$DEEP" = "true" \]/{exit} /json\/version/{found=1} END{exit !found}' "$ROOT/scripts/status-dream-skin-macos.sh"
/usr/bin/grep -q 'LIVE_THEME_ID' "$ROOT/scripts/status-dream-skin-macos.sh"
/usr/bin/grep -q 'desiredThemeId' "$ROOT/scripts/status-dream-skin-macos.sh"
/usr/bin/grep -q 'liveThemeId' "$ROOT/scripts/status-dream-skin-macos.sh"
/usr/bin/grep -q 'themeApplied' "$ROOT/scripts/status-dream-skin-macos.sh"
/usr/bin/grep -q 'for attempt in 1 2' "$ROOT/scripts/status-dream-skin-macos.sh"
/usr/bin/grep -q 'private var catalogCandidates' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'engineNeedsUpdate ? \[bundled, installed\]' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'deferBusyStateReset' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'refreshIfIdle' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'NSApplication.didBecomeActiveNotification' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'Timer.publish(every: 5' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q '衣橱.*引擎' "$ROOT/switcher/ThemeSwitcherApp.swift"
/usr/bin/grep -q 'application id.*com.xiangzai.codex-theme-switcher.*quit' "$ROOT/scripts/build-theme-switcher-macos.sh"
[ -x "$ROOT/scripts/switch-theme-macos.sh" ]
for theme_id in skin-01 skin-02 skin-03 skin-04 skin-05 skin-06 skin-07 skin-08; do
  "$NODE" -e '
    const fs = require("fs");
    const pack = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (typeof pack.image !== "string" || !pack.image) process.exit(1);
    if (!fs.existsSync(`${process.argv[2]}/${pack.image}`)) process.exit(1);
  ' "$ROOT/themes/$theme_id/theme.json" "$ROOT/themes/$theme_id"
done
! /usr/bin/grep -q 'PrincePreview\|QQPreview' "$ROOT/switcher/ThemeSwitcherApp.swift"
[ ! -e "$ROOT/themes/skin-02/fortune-developer-hero.png" ]
/usr/bin/grep -q 'original|off|none|stock' "$ROOT/scripts/theme-macos.sh"
/usr/bin/grep -A2 'prince|little-prince|inspiration-universe' "$ROOT/scripts/switch-theme-macos.sh" | /usr/bin/grep -q 'skin-05'
/usr/bin/grep -A2 'prince|little-prince|inspiration-universe|小王子' "$ROOT/scripts/theme-macos.sh" | /usr/bin/grep -q 'skin-05'
/usr/bin/env -u HOME /bin/bash -c '. "$1/scripts/common-macos.sh"; [ -n "$HOME" ] && [ "$SKIN_VERSION" = "2.2.10" ]' _ "$ROOT"
DOCTOR_LABEL="doctor"
if [ "${SKIP_LIVE_DOCTOR:-false}" != "true" ]; then
  "$ROOT/scripts/doctor-macos.sh" >/dev/null
else
  DOCTOR_LABEL="doctor-skipped"
fi

printf 'PASS: syntax, catalog themes, original mode, responsive QQ, custom themes, config round-trip, HOME recovery, signature, and %s checks.\n' "$DOCTOR_LABEL"
