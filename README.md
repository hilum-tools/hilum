# Hilum Tools

**Structural truth for AI coding agents — not guesses.**

Your coding agent starts every session by re-reading half your repository to work out where things are. Hilum Tools is the layer that already knows: it answers structure, references, history and retrieval over MCP, so the agent works from what the code actually is instead of guessing — with far fewer tokens.

One binary. One entry in your MCP client. Every tool.

Hilum Tools is the product. `hilum` is the single binary it ships, and the command you type.

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

Linux builds need glibc 2.35 or newer, which covers Ubuntu 22.04, Debian 12 and RHEL 9. They will not run on Alpine or another musl-based distribution. The floor is the glibc of the oldest image the release builds on. If it rules you out, open an issue and say so.

## First run

The first semantic query downloads two things: the embedding model, and the inference runtime that executes it. Both are cached locally and fetched once. Neither ships inside the binary, which is deliberate — a runtime compiled in has to be compiled against something, and that choice is what decides which Linux distributions the binary will start on. If you never run a semantic query, neither is ever downloaded.

## What this repository is

The download surface: binaries, installers, changelog. The source is not public. The agent kit — portable rules, skills and workflows — is Apache-2.0 and lives in [hilum-kit](https://github.com/hilum-tools/hilum-kit).

- Documentation: [docs.hilum.tools](https://docs.hilum.tools)
- Site: [hilum.tools](https://hilum.tools)

## Licence

The binaries are distributed under an end-user licence agreement; see `LICENSE` in this repository once the first release ships.

Built by [Aleksandr Ivannikov](https://github.com/ivannikov-pro).
