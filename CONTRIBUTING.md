# Contributing

Thank you for improving Codex Dream Skin.

## Before a pull request

1. Keep CDP bound to loopback and never patch the official Codex app, `asar`,
   `WindowsApps`, or application signature.
2. Do not add API keys, tokens, private chat text, local project names, or
   unlicensed artwork.
3. Preserve native Codex controls, including the sidebar, project selector,
   composer, menus, and restore path.
4. Run the relevant checks:

```bash
SKIP_LIVE_DOCTOR=true ./macos/tests/run-tests.sh
./windows/tests/run-tests.sh
```

For macOS visual changes, also run a live verify on every affected theme.
Windows UI changes require a Windows 11 live check before claiming full
platform validation.

## Theme assets

Read `ASSET_RIGHTS.md`. A contributor must have redistribution permission for
new art and should state its source and license in the pull request.
