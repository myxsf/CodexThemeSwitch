#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
REPO="$(cd "$ROOT/.." && pwd -P)"
NODE="${NODE:-$(command -v node)}"
[ -x "$NODE" ] || { printf 'Node.js 20+ is required for static tests.\n' >&2; exit 1; }

"$NODE" --check "$ROOT/scripts/injector.mjs"
"$NODE" --check "$ROOT/assets/renderer-inject.js"
resize_self_test="$($NODE "$ROOT/scripts/injector.mjs" --resize-self-test)"
"$NODE" -e 'const value=JSON.parse(process.argv[1]);if(!value.pass||value.cases.length<10)process.exit(1)' "$resize_self_test"
[ -f "$REPO/themes/catalog.json" ]

ids="$($NODE -e 'const c=require(process.argv[1]); if(c.schemaVersion!==1||!Array.isArray(c.themes))process.exit(1); console.log(c.themes.filter(t=>t.enabled!==false&&(!t.platforms||t.platforms.includes("win32")||t.platforms.includes("windows")||t.platforms.includes("all"))).map(t=>t.id).join("\n"))' "$REPO/themes/catalog.json")"
while IFS= read -r id; do
  [ -n "$id" ] || continue
  payload="$($NODE "$ROOT/scripts/injector.mjs" --check-payload --catalog "$REPO/themes/catalog.json" --theme-id "$id")"
  "$NODE" -e 'const v=JSON.parse(process.argv[1]);if(!v.pass||v.themeId!==process.argv[2])process.exit(1)' "$payload" "$id"
done <<< "$ids"

visual_fixture="$(mktemp -d)"
trap 'rm -rf "$visual_fixture"' EXIT
"$NODE" -e '
const fs=require("fs");
const dir=process.argv[1];
fs.writeFileSync(`${dir}/theme.json`, JSON.stringify({
  schemaVersion:1,id:"visual-fixture",profile:"inspiration-universe",appearance:"light",
  visual:{
    layoutVariant:"miku",
    sidebar:{brand:"Miku Studio",subtitle:"Cyan Music Edition",footerText:"翔仔正在工作ing"},
    cards:[
      {icon:"01",title:"探索并理解代码",detail:"梳理结构",action:"prompt",prompt:"请探索并理解当前代码库"},
      {icon:"02",title:"构建新功能",detail:"创建工具",action:"prompt",prompt:"x".repeat(300)},
      {icon:"03",title:"审查代码",detail:"提出建议",action:"prompt",prompt:"请审查代码"},
      {icon:"04",title:"插件与工具",detail:"打开真实入口",action:"plugins"},
      {icon:"05",title:"不得保留",detail:"超过四张",action:"invalid"}
    ],
    note:{title:"今日舞台",lines:["保持节奏","先验证再交付","第三行","第四行","不得保留"]},
    chrome:{sparkles:false,ribbon:false,polaroid:false}
  }
}));
' "$visual_fixture"
visual_payload="$($NODE "$ROOT/scripts/injector.mjs" --check-payload --theme-dir "$visual_fixture")"
"$NODE" -e '
const value=JSON.parse(process.argv[1]);
const visual=value.visual;
if(!value.pass||visual.layoutVariant!=="miku")process.exit(1);
if(visual.cards.length!==4||visual.cards[1].prompt.length!==240)process.exit(1);
if(visual.cards.some(card=>!["prompt","plugins"].includes(card.action)))process.exit(1);
if(visual.note.lines.length!==4)process.exit(1);
if(visual.chrome.sparkles||visual.chrome.ribbon||visual.chrome.polaroid)process.exit(1);
' "$visual_payload"

grep -q -- '--remote-debugging-address=127.0.0.1' "$ROOT/scripts/start-dream-skin.ps1"
grep -q 'validatedDebuggerUrl' "$ROOT/scripts/injector.mjs"
grep -q 'probeSession' "$ROOT/scripts/injector.mjs"
grep -q 'Runtime.addBinding' "$ROOT/scripts/injector.mjs"
grep -q 'Browser.setWindowBounds' "$ROOT/scripts/injector.mjs"
grep -q 'const MIN_WINDOW_WIDTH = 760' "$ROOT/scripts/injector.mjs"
grep -q 'const MIN_WINDOW_HEIGHT = 560' "$ROOT/scripts/injector.mjs"
grep -q 'geometryMatches(restored.bounds, baseline' "$ROOT/scripts/injector.mjs"
grep -q 'data-dream-theme' "$ROOT/assets/renderer-inject.js"
grep -q 'data-dream-theme-id' "$ROOT/assets/renderer-inject.js"
grep -q 'data-dream-palette' "$ROOT/assets/renderer-inject.js"
grep -q 'configuredAppearance' "$ROOT/assets/renderer-inject.js"
grep -q 'data-dream-layout' "$ROOT/assets/renderer-inject.js"
grep -q 'hasThemeVisualCards ? card.title' "$ROOT/assets/renderer-inject.js"
grep -q 'fillComposerPrompt' "$ROOT/assets/renderer-inject.js"
grep -q 'openPlugins' "$ROOT/assets/renderer-inject.js"
grep -q 'visualChrome.sparkles ?' "$ROOT/assets/renderer-inject.js"
grep -q 'visualChrome.ribbon ?' "$ROOT/assets/renderer-inject.js"
grep -q 'visualChrome.polaroid ?' "$ROOT/assets/renderer-inject.js"
! grep -q '<div class="dream-sparkles".*<div class="dream-ribbon".*<div class="dream-polaroid"' "$ROOT/assets/renderer-inject.js"
grep -q -- '--dream-art-position' "$ROOT/assets/renderer-inject.js"
! grep -q 'setInterval(ensure, 5000)' "$ROOT/assets/renderer-inject.js"
grep -q 'profile === "qq2007" ? null' "$ROOT/assets/renderer-inject.js"
grep -q "!button.closest('#dream-extra-card')" "$ROOT/assets/renderer-inject.js"
grep -q 'Local\\CodexDreamSkinThemeSwitch' "$ROOT/scripts/switch-theme-windows.ps1"
grep -q 'INSTALLER=%~dp0windows\\scripts\\install-dream-skin.ps1' "$ROOT/Install Codex Theme Wardrobe.cmd"
grep -q 'if not exist "%INSTALLER%"' "$ROOT/Install Codex Theme Wardrobe.cmd"
! grep -q 'docs\\images\\gallery' "$ROOT/scripts/install-dream-skin.ps1"
grep -q 'function Resolve-UserDesktopPath' "$ROOT/scripts/common-windows.ps1"
grep -q "Join-Path \$env:USERPROFILE 'Desktop'" "$ROOT/scripts/common-windows.ps1"
grep -q '\$desktop = Resolve-UserDesktopPath' "$ROOT/scripts/install-dream-skin.ps1"
grep -q '\$desktop = Resolve-UserDesktopPath' "$ROOT/scripts/restore-dream-skin.ps1"
grep -q 'PanningMode.HorizontalOnly' "$ROOT/switcher/ThemeWardrobe.cs"
grep -q 'PreviewMouseWheel' "$ROOT/switcher/ThemeWardrobe.cs"
grep -q '作者 myxsf' "$ROOT/switcher/ThemeWardrobe.cs"
grep -q 'data-dream-palette="light"' "$ROOT/assets/dream-skin.css"
grep -q 'justify-content: flex-start !important' "$ROOT/assets/dream-skin.css"
grep -q 'container-name: dream-main' "$ROOT/assets/dream-skin.css"
grep -q 'container-type: inline-size' "$ROOT/assets/dream-skin.css"
grep -q -- '--thread-content-max-width: min(1180px, calc(100% - 44px))' "$ROOT/assets/dream-skin.css"
grep -q '@container dream-main (max-width: 920px)' "$ROOT/assets/dream-skin.css"
grep -q 'data-dream-layout="enfp"' "$ROOT/assets/dream-skin.css"
grep -q 'data-dream-layout="purple-night"' "$ROOT/assets/dream-skin.css"
grep -q 'data-dream-layout="miku"' "$ROOT/assets/dream-skin.css"
grep -q '> div:has(.composer-surface-chrome)' "$ROOT/assets/dream-skin.css"
grep -q -- '--ds-gallery-hero-ratio: 0.34686' "$ROOT/assets/dream-skin.css"
grep -q '@media (max-height: 820px)' "$ROOT/assets/dream-skin.css"
! grep -A6 'group\\/project-selector' "$ROOT/assets/dream-skin.css" | grep -q 'display: none !important'
grep -q 'data-dream-layout="purple-night".*main.main-surface' "$ROOT/assets/dream-skin.css"
grep -q 'data-dream-layout="purple-night".*color-scheme: light' "$ROOT/assets/dream-skin.css"
grep -q 'background: #f5f3ff !important' "$ROOT/assets/dream-skin.css"
grep -q 'data-app-action-sidebar-thread-row' "$ROOT/assets/dream-skin.css"
grep -q 'padding-right: 58px !important' "$ROOT/assets/dream-skin.css"
grep -q 'margin-top: 0 !important' "$ROOT/assets/dream-skin.css"
grep -q 'transform: none !important' "$ROOT/assets/dream-skin.css"
grep -q 'group\\/project-selector > button:not(:disabled)' "$ROOT/assets/dream-skin.css"
grep -q 'background-size: 100% auto !important' "$ROOT/assets/dream-skin.css"
grep -q '禁止开源转卖与盗版' "$ROOT/assets/dream-skin.css"
grep -q 'dream-card-visual' "$ROOT/assets/renderer-inject.js"
grep -q 'dream-plugin-card' "$ROOT/assets/renderer-inject.js"
grep -q 'let visual = chrome.querySelector' "$ROOT/assets/renderer-inject.js"
grep -q 'aside.app-shell-left-panel \[class\*="text-"\]' "$ROOT/assets/qq2007.css"
grep -q 'new ResizeObserver' "$ROOT/assets/renderer-inject.js"
grep -q 'qqSidebarRatio' "$ROOT/assets/renderer-inject.js"
grep -q 'previous?.version === version' "$ROOT/assets/renderer-inject.js"
grep -q 'previous?.profile === "qq2007"' "$ROOT/assets/renderer-inject.js"
grep -q 'aside.style.width = `${referenceWidth}px`' "$ROOT/assets/renderer-inject.js"
grep -q 'qqShouldResetSidebarWidth = false' "$ROOT/assets/renderer-inject.js"
grep -q 'qqSidebarResetTimer = setTimeout' "$ROOT/assets/renderer-inject.js"
grep -q 'previous?.qqSidebarInitializing !== true' "$ROOT/assets/renderer-inject.js"
grep -q 'qqSidebarInitializing: qqShouldResetSidebarWidth' "$ROOT/assets/renderer-inject.js"
grep -q 'previous?.qqSidebarResetTimer' "$ROOT/assets/renderer-inject.js"
grep -q 'clearTimeout(qqSidebarResetTimer)' "$ROOT/assets/renderer-inject.js"
grep -q 'qqSidebarInteractionController = new AbortController()' "$ROOT/assets/renderer-inject.js"
grep -q 'qqUserResizeGraceUntil = performance.now() + 650' "$ROOT/assets/renderer-inject.js"
grep -q 'sidebar-resize-handle-line' "$ROOT/assets/qq2007.css"
grep -A5 '> \.max-w-full\.overflow-hidden' "$ROOT/assets/qq2007.css" | grep -q 'min-width: 0 !important'
grep -q 'data-pip-anchor-host="codex-main-thread"' "$ROOT/assets/qq2007.css"
grep -q -- '--thread-wide-block-inline-shift: 0px !important' "$ROOT/assets/qq2007.css"
! grep -q 'data-dream-qq-splitter' "$ROOT/assets/renderer-inject.js"
grep -q '\["n", "s", "e", "w", "ne", "nw", "se", "sw"\]' "$ROOT/assets/renderer-inject.js"
for direction in n s e w ne nw se sw; do
  grep -q "data-dream-resize-direction=\\\"${direction}\\\"" "$ROOT/assets/qq2007.css"
done
grep -q 'webkitAppRegion === "no-drag"' "$ROOT/scripts/injector.mjs"
grep -q 'handles.length === 8' "$ROOT/scripts/injector.mjs"
grep -q ':has(.composer-surface-chrome)' "$ROOT/assets/dream-skin.css"
grep -q 'Unified eight-theme home flow' "$ROOT/assets/dream-skin.css"
grep -q -- '--ds-home-composer-slot-h: 168px' "$ROOT/assets/dream-skin.css"
grep -q 'data-dream-theme-id="skin-08".*composer-surface-chrome' "$ROOT/assets/dream-skin.css"
grep -q -- '-webkit-text-fill-color: #f3ebdd' "$ROOT/assets/dream-skin.css"
grep -q 'data-dream-theme-id="skin-01".*data-dream-theme-id="skin-03"' "$ROOT/assets/dream-skin.css"
grep -q 'dream-home \[data-feature="game-source"\]' "$ROOT/assets/dream-skin.css"
grep -q -- '-webkit-text-fill-color: var(--dream-hero-copy)' "$ROOT/assets/dream-skin.css"
grep -q 'layoutResizeObserver = new ResizeObserver' "$ROOT/assets/renderer-inject.js"
grep -q 'scheduleLayoutSync' "$ROOT/assets/renderer-inject.js"
grep -q 'style.textContent !== cssText' "$ROOT/assets/renderer-inject.js"
grep -q 'instanceToken' "$ROOT/assets/renderer-inject.js"
grep -q 'div.z-50' "$ROOT/assets/renderer-inject.js"
grep -q -- '--ds-tall-hero-ratio: 0.37461' "$ROOT/assets/dream-skin.css"
grep -q -- '--ds-home-card-h: clamp(262px, 25vh, 278px)' "$ROOT/assets/dream-skin.css"
grep -A2 'data-dream-theme-id="skin-08".*dream-home' "$ROOT/assets/dream-skin.css" | grep -q -- '--ds-home-card-h: 298px'
! grep -R -n -E '(Set-Content|Copy-Item|Move-Item|Remove-Item).*app\.asar' "$ROOT/scripts" >/dev/null

printf 'PASS: Windows dynamic catalog payloads, original mode, CDP hardening, window bridge, carousel markers, and mutation guard.\n'
