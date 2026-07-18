---
name: codex-theme-wardrobe-windows
description: Install, browse, switch, verify, repair, package, or restore dynamic Codex Desktop themes on Windows without modifying WindowsApps or app.asar.
---

# Codex Theme Wardrobe — Windows

Use the official Store-installed Codex executable with loopback-only CDP. Never replace, patch, take ownership of, or write into `WindowsApps`.

## Workflow

1. Run `scripts/install-dream-skin.ps1`. It deploys a stable engine and builds the WPF wardrobe with Windows' built-in .NET Framework.
2. Browse themes in **Codex Theme Wardrobe.exe** by touch, drag, horizontal wheel, or navigation buttons. Browsing is preview-only; applying is explicit.
3. CLI equivalent: `scripts/theme-windows.ps1 list`, then `theme-windows.ps1 switch <id> -RestartExisting`.
4. Use `original` to stop the watcher and fully remove live CSS/DOM while keeping the debug-enabled Codex session available for later hot switching.
5. Run `scripts/verify-dream-skin.ps1 -ExpectedTheme <id> -ScreenshotPath <path>` after visual changes.
6. Run `tests/run-tests.ps1`, then exercise every theme and original twice on a real Windows 11 Codex installation before release.

## Guardrails

- Theme metadata comes from the shared `themes/catalog.json`; only trusted built-in profile names are accepted.
- Composite gallery files are previews only. Runtime artwork must come from the declared theme pack.
- The launcher binds CDP to `127.0.0.1`, validates returned WebSocket URLs, and probes Codex DOM markers before injecting.
- Only the exact Codex package executable may be restarted. Never stop every process named `ChatGPT`.
- Only a watcher whose command line contains this installation's exact `injector.mjs --watch` may be stopped.
- Original mode must verify root class, theme attribute, style node, chrome node, and renderer state are all absent.
- Keep remote/customer theme bundles data-only. Do not add executable JavaScript or unrestricted CSS ingestion.

## Resources

- `scripts/common-windows.ps1`: package/runtime/process/state discovery.
- `scripts/injector.mjs`: manifest validation, CDP injection, exact verification, screenshots, and window actions.
- `scripts/switch-theme-windows.ps1`: serialized hot switch and rollback.
- `switcher/ThemeWardrobe.cs`: dependency-free WPF carousel.
- `scripts/build-release.ps1`: tested ZIP and SHA-256 packaging.
- `references/qa-inventory.md`: Windows functional and visual signoff.
