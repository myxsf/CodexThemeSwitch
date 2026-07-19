# Codex Theme Switch

<p align="center">
  <a href="./README.md">中文</a> · <strong>English</strong>
</p>

<p align="center">
  <strong>Give Codex a face that breathes.</strong><br>
  External themes for the Codex desktop app · Local CDP inject · No official package mutation
</p>

<p align="center">
  One image, one mood · Code with atmosphere
</p>

<p align="center">
  Unofficial. Does not modify <code>.app</code> / <code>app.asar</code> / WindowsApps.
</p>

<p align="center">
  <a href="https://github.com/myxsf/CodexThemeSwitch/actions/workflows/ci.yml"><img src="https://github.com/myxsf/CodexThemeSwitch/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/myxsf/CodexThemeSwitch/releases/tag/v2.2.10"><img src="https://img.shields.io/github/v/release/myxsf/CodexThemeSwitch" alt="Release"></a>
</p>

## Project & sponsorship

<p align="center">
  <strong>Codex Theme Switch</strong><br>
  <sub>Maintained by <a href="https://github.com/myxsf">myxsf</a> · No sponsors yet</sub>
</p>

This project is not sponsored by or affiliated with any API relay, service provider, or other commercial service. Any future sponsor will be disclosed here; unlisted third parties are unrelated to this project.

## Gallery

The first image is a privacy-cropped `2.2.10` live gallery containing only the
Hero and native suggestion-card regions:

<p align="center">
  <img src="docs/images/theme-gallery-safe.png" alt="Codex Theme Wardrobe 2.2.10 live theme gallery" width="1100">
</p>

One image, one mood. The images below are the matching prototype references:

<p align="center">
  <img src="docs/images/gallery/skin-01.jpg" alt="Pink Custom" width="900"><br>
  <sub>Pink Custom</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-02.jpg" alt="God of Wealth" width="900"><br>
  <sub>God of Wealth</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-03.jpg" alt="Red-White Sci-Fi" width="900"><br>
  <sub>Red-White Sci-Fi</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-04.jpg" alt="Clear Custom" width="900"><br>
  <sub>Clear Custom</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-05.jpg" alt="Inspiration" width="900"><br>
  <sub>Inspiration</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-06.jpg" alt="Purple Night" width="900"><br>
  <sub>Purple Night</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-07.jpg" alt="Hatsune Miku" width="900"><br>
  <sub>Hatsune Miku</sub>
</p>

<p align="center">
  <img src="docs/images/gallery/skin-08.jpg" alt="Stage Black-Gold" width="900"><br>
  <sub>Stage Black-Gold</sub>
</p>

## What it does

- **Real UI** — Sidebar, cards, project picker, and input stay native. Not a fake full-window screenshot.
- **Swappable art** — Drop in an image you like and it becomes your theme.
- **Restorable** — One-click restore to the stock look.
- **Safer path** — Local-loopback CDP inject only. No official binary or signature changes.

## What's new in 2.2.10

- Light themes now isolate native Codex tokens from a dark host shell, preventing black headers, dark output cards, and unreadable text.
- Removed the black gradient and dark band around the composer, with stronger contrast for the send button and its icon.
- When Windows blocks direct execution of the Store-packaged Node runtime, the installer copies and validates it in the current user's local runtime directory.

## Quick start

Platform scripts are ready — different plumbing, same goal: theme Codex.

| Platform | Dir | Entry |
|------|------|------|
| Apple Silicon / Intel Mac | [`macos/`](./macos/) | Double-click `Install Codex Dream Skin.command` |
| Windows | [`windows/`](./windows/) | `scripts/install-dream-skin.ps1` → `start-dream-skin.ps1` |

More detail:

- Mac: [`macos/README.md`](./macos/README.md)
- Windows: [`windows/SKILL.md`](./windows/SKILL.md)
- Paths: [`docs/platforms.md`](./docs/platforms.md)
- Project notes: [`docs/PROJECT.md`](./docs/PROJECT.md)
- `2.2.10` cross-platform install validation: [`docs/RELEASE-VALIDATION-v2.2.10.md`](./docs/RELEASE-VALIDATION-v2.2.10.md)

## Feedback & contributions

- **Issues:** Use the [issue templates](./.github/ISSUE_TEMPLATE/) (bug / feature). Blank issues are disabled. Please try Verify / Restore self-checks before filing bugs.
- **PRs:** Follow the [PR template](./.github/pull_request_template.md) — describe the change and tick the self-checks you actually ran (e.g. `macos/tests/run-tests.sh`, verify / restore).

## Safety

- CDP binds `127.0.0.1` only — avoid untrusted local processes while the theme runs.
- Does not touch the official install directory or code signature.
- **Never** rewrites API Key / Base URL; relay and theme stay separate.

## License

- Software source is licensed under [`LICENSE`](./LICENSE) (MIT)
- People, characters, QQ-inspired material, and brand assets are excluded from the code license; read [`ASSET_RIGHTS.md`](./ASSET_RIGHTS.md) before redistribution
- Unofficial; Codex and related rights belong to their owners.
- People / IP art in previews is illustrative only — clear rights before commercial redistribution.

---

Star it, pick a look, and make Codex yours for today.
