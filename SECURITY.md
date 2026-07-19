# Security policy

## Supported release

Security fixes target the latest release, currently `2.2.10`.

## Reporting a vulnerability

Open a private GitHub Security Advisory for vulnerabilities. Do not publish
credentials, private chats, local paths, or proof-of-concept code that exposes
another user's machine in a public issue.

Include the operating system, Codex version, Dream Skin version, reproduction
steps, and whether the official application has been modified.

## Trust boundary

- The debugger endpoint must bind to `127.0.0.1` only.
- Theme packs are data and CSS; they must not execute untrusted JavaScript.
- The project does not modify the official Codex application bundle or code
  signature.
- The project does not read or rewrite API keys or provider configuration.
- Restoring the original appearance must stop the injector and remove the
  themed renderer state.
