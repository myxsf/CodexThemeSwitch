# Windows QA inventory

## Static and build gates

- `tests/run-tests.ps1` parses every PowerShell file, checks every enabled Windows catalog theme, validates JavaScript, and compiles the WPF EXE.
- `tests/run-tests.sh` provides catalog/payload/security checks on macOS CI, but does not replace Windows execution.
- `build-release.ps1` must produce a ZIP and matching SHA-256.

## Functional checks on Windows 11

- Install from a clean ZIP; move/delete the extracted source and confirm the installed shortcut still works.
- Drag the wardrobe left/right, use touch and mouse wheel, verify snap animation, then apply only the final selected card.
- Apply every enabled Windows theme, including image-less color packs. Confirm the displayed active theme matches renderer state.
- Run two full cycles: `original -> all themes -> original`. The themed state has exactly one verified watcher; original has zero.
- Open projects, tasks, menus and composer controls. Decorations must not replace or intercept native controls.
- Navigate and reload. The selected theme returns without duplicate DOM.
- Apply original. Verify class, `data-dream-theme`, style, chrome and renderer state are absent.
- Occupy port 9335 and confirm a free loopback port is selected without touching the unrelated listener.
- Run with both ChatGPT and Codex installed. Restarting Codex must not close the separate ChatGPT app.

## Window regression checks

- At a normal window size, drag the real skin title region, resize every edge/corner, maximize, then restore.
- Confirm restore returns to the previous usable bounds rather than an oversized or off-screen rectangle.
- Repeat maximize/restore after changing display scale and after moving the window to a second monitor.
- QQ buttons must be `no-drag`; title area must be `drag`; native input/sidebar areas must remain interactive.

## Release evidence

- Record Windows build, CPU architecture, Codex version/package source, WPF EXE hash and release ZIP hash.
- Confirm `Get-NetTCPConnection` reports only loopback listener addresses for the chosen CDP port.
- Confirm the listener belongs to the resolved Codex package process.
- Confirm injector error log is empty after all cycles.
- Do not call Windows “verified” based only on macOS static tests or GitHub Actions compilation.
