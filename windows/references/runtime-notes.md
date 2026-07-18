# Windows runtime notes

- The installer deploys to `%LOCALAPPDATA%\Programs\CodexThemeWardrobe`; mutable state and logs use `%LOCALAPPDATA%\CodexDreamSkinStudio`.
- Codex is discovered from the newest `OpenAI.Codex` Appx package. The executable is read from `AppxManifest.xml`, with `app\ChatGPT.exe` only as a compatibility fallback.
- Node.js 20+ is resolved from the official Codex package first, then PATH. The package path must be verified on each supported Windows Codex release.
- Codex is launched with `--remote-debugging-address=127.0.0.1 --remote-debugging-port=<port>`.
- Theme metadata comes from `themes/catalog.json`; paths are repository-root-relative and theme profiles are allowlisted by the engine.
- The watcher loads one validated payload. Switching replaces the verified watcher and immediately performs a one-shot apply; failures restore the previous theme.
- Original mode has no watcher. It removes and verifies the renderer state but keeps the current CDP-enabled Codex process alive for fast future application.
- QQ window buttons call CDP through a `Runtime.addBinding` bridge. Normal bounds are cached before maximize and explicitly restored afterward.
- Public EXEs need an Authenticode certificate to avoid SmartScreen reputation prompts. The source build itself does not provide a commercial certificate.
