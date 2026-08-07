# Hilum

**Structural truth for AI coding agents — not guesses.**

Your coding agent starts every session by re-reading half your repository to work out where things are. Hilum is the layer that already knows: it answers structure, references, history and retrieval over MCP, so the agent works from what the code actually is instead of guessing — with far fewer tokens.

One binary. One entry in your MCP client. Every tool.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/hilum-tools/hilum/main/install.sh | sh
```

Windows:

```powershell
irm https://raw.githubusercontent.com/hilum-tools/hilum/main/install.ps1 | iex
```

The installer detects your platform, downloads the matching release, **verifies its checksum before installing**, and places the binary on your PATH. Re-running it is how you upgrade.

Prefer to look first? The script is right here in this repository — read it before you pipe it into a shell. That is good practice with any installer, including this one.

## Verify what you downloaded

Every release carries a checksum beside each archive and one aggregate `SHA256SUMS`. The installer checks it for you and refuses to install if it does not match. To check by hand:

```sh
shasum -a 256 -c hilum-<version>-SHA256SUMS
```

## Supported platforms

| System | Architectures |
|---|---|
| macOS | Apple Silicon, Intel |
| Linux | x86_64, arm64 — glibc 2.35 or newer |
| Windows | x86_64, arm64 |

Linux builds link against glibc and will not run on Alpine or another musl-based distribution. If you need one, open an issue and say so.

## First run

The binary is self-contained, but the embedding model is not inside it — it is downloaded to a local cache the first time it is needed, so the first run wants a network connection.

## What this repository is

The download surface: binaries, installers, changelog. The source is not public. The agent kit — portable rules, skills and workflows — is Apache-2.0 and lives in [hilum-kit](https://github.com/hilum-tools/hilum-kit).

- Documentation: [docs.hilum.tools](https://docs.hilum.tools)
- Site: [hilum.tools](https://hilum.tools)

## Licence

The binaries are distributed under an end-user licence agreement; see `LICENSE` in this repository once the first release ships.

Built by [Aleksandr Ivannikov](https://github.com/ivannikov-pro).
