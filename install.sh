#!/bin/sh
# Hilum installer — downloads the release build for this platform, verifies it, and puts it on PATH.
#
#   curl -fsSL https://hilum.tools/install.sh | sh
#
# POSIX sh on purpose: this runs under dash, ash and busybox before anything of ours exists, so it
# uses no bashisms. It needs curl or wget, tar, and a sha256 tool — all present on a stock macOS or
# Linux. Windows has a sibling PowerShell installer.
#
# Options (also settable as environment variables):
#   --version <v>     HILUM_VERSION       install this exact version instead of the latest release
#   --to <dir>        HILUM_INSTALL_DIR   install here instead of ~/.local/bin
#   --force                               overwrite an existing binary without asking
#   --help
#
# It never edits a shell profile. A script piped into a shell cannot ask, and silently rewriting a
# profile is not a thing to do without asking — so when the install directory is not on PATH it prints
# the line to add and leaves the decision where it belongs.
#
# Re-running it is how you upgrade: the install is idempotent and replaces whatever is there.

set -eu

REPO="hilum-tools/hilum"
BIN="hilum"
API="https://api.github.com/repos/${REPO}/releases"
DL="https://github.com/${REPO}/releases/download"

VERSION="${HILUM_VERSION:-}"
INSTALL_DIR="${HILUM_INSTALL_DIR:-$HOME/.local/bin}"
FORCE=0

# The release signing public key. Not a secret — distributing it IS its purpose. It is published in
# three places (here, as minisign.pub in the distribution repository, and on the site) precisely so a
# substitution in any one of them is visible against the others. Override only to test against a
# different key.
HILUM_MINISIGN_PUBKEY="${HILUM_MINISIGN_PUBKEY:-RWSnhqZs5W7WgG5w9362G/R4b9pvtmC1VZATfKeBZDxBdVt1j7dj22fP}"

say() { printf '%s\n' "$*"; }
err() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "$1 is required but was not found on PATH"; }

# Print the header comment block and stop at the first line that is not a comment. A hardcoded line
# range would silently start printing the wrong thing the next time the header is edited.
usage() {
	awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
		--version) VERSION="${2:-}"; shift 2 || err "--version needs a value" ;;
		--to) INSTALL_DIR="${2:-}"; shift 2 || err "--to needs a value" ;;
		--force) FORCE=1; shift ;;
		-h|--help) usage ;;
		*) err "unknown option: $1 (try --help)" ;;
	esac
done

# --- platform ----------------------------------------------------------------------------------
# Resolve the target triple of THIS host. On macOS the check is `sysctl hw.optional.arm64` rather than
# `uname -m`, because under a Rosetta-translated shell `uname -m` reports x86_64 on an Apple Silicon
# machine and would hand the user the slow binary.
detect_target() {
	os="$(uname -s)"
	case "$os" in
		Darwin)
			if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
				echo "aarch64-apple-darwin"
			else
				echo "x86_64-apple-darwin"
			fi
			;;
		Linux)
			case "$(uname -m)" in
				aarch64|arm64) echo "aarch64-unknown-linux-gnu" ;;
				x86_64|amd64) echo "x86_64-unknown-linux-gnu" ;;
				*) err "unsupported architecture: $(uname -m)" ;;
			esac
			;;
		*)
			err "unsupported system: $os. Windows has its own installer; see the documentation."
			;;
	esac
}

TARGET="$(detect_target)"

# The Linux builds link against glibc. A musl-based distribution (Alpine and friends) needs a build we
# do not ship yet — say so here rather than let the user discover it from a loader error.
if [ "$(uname -s)" = "Linux" ] && [ ! -e /lib/ld-linux-x86-64.so.2 ] && [ ! -e /lib/ld-linux-aarch64.so.1 ] && ! ldd --version 2>&1 | grep -qi glibc; then
	err "this build needs glibc and this system does not appear to have it (Alpine or another musl distribution). Please open an issue asking for a musl build."
fi

# --- fetch helpers -----------------------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL "$1"; }
	fetch_to() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
	fetch() { wget -qO- "$1"; }
	fetch_to() { wget -qO "$2" "$1"; }
else
	err "either curl or wget is required"
fi

need tar
if command -v sha256sum >/dev/null 2>&1; then
	sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
	sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
	err "a sha256 tool is required (sha256sum or shasum)"
fi

# --- version -----------------------------------------------------------------------------------
# The latest-release endpoint excludes prereleases, so a release candidate is never served here by
# accident. Someone who wants one names it with --version.
if [ -z "$VERSION" ]; then
	VERSION="$(fetch "${API}/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
	[ -n "$VERSION" ] || err "could not determine the latest version. Pass --version <v>, or check that ${REPO} has a published release."
fi
VERSION="${VERSION#v}"

ARCHIVE="${BIN}-${VERSION}-${TARGET}.tar.gz"
SUMS="${BIN}-${VERSION}-SHA256SUMS"

# --- download + verify -------------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

say "hilum ${VERSION} for ${TARGET}"
fetch_to "${DL}/v${VERSION}/${ARCHIVE}" "${TMP}/${ARCHIVE}" \
	|| err "download failed. Is ${VERSION} a published release for ${TARGET}?"

# Verification is not optional. A checksum proves the download arrived intact; the signature, when the
# release carries one, proves it is the file we built. A release without a sums file is a broken
# release, so treat a missing one as a failure rather than a reason to skip the check.
fetch_to "${DL}/v${VERSION}/${SUMS}" "${TMP}/${SUMS}" || err "no checksum file in release v${VERSION} — refusing to install unverified"
EXPECTED="$(grep " ${ARCHIVE}\$" "${TMP}/${SUMS}" | cut -d' ' -f1 | head -n 1)"
[ -n "$EXPECTED" ] || err "${ARCHIVE} is not listed in ${SUMS} — refusing to install unverified"
ACTUAL="$(sha256 "${TMP}/${ARCHIVE}")"
[ "$EXPECTED" = "$ACTUAL" ] || err "checksum mismatch for ${ARCHIVE}: expected ${EXPECTED}, got ${ACTUAL}"
say "checksum ok"

# The signature proves the checksum file is the one we published — the checksum alone only proves the
# download was not corrupted, and both sit in the same place, so whoever can replace one can replace
# both. A FAILED verification always aborts. A verification that cannot be attempted does not, because
# refusing to install over a missing optional tool is a worse default than saying what was skipped.
if fetch_to "${DL}/v${VERSION}/${SUMS}.minisig" "${TMP}/${SUMS}.minisig" 2>/dev/null; then
	if command -v minisign >/dev/null 2>&1; then
		if minisign -V -P "${HILUM_MINISIGN_PUBKEY}" -m "${TMP}/${SUMS}" >/dev/null 2>&1; then
			say "signature ok"
		else
			err "signature verification FAILED for ${SUMS} — do not install this file"
		fi
	else
		say "signature present but not checked — install minisign to verify it"
	fi
fi

# --- install -----------------------------------------------------------------------------------
tar -xzf "${TMP}/${ARCHIVE}" -C "$TMP"
[ -f "${TMP}/${BIN}" ] || err "the archive did not contain a ${BIN} binary"

mkdir -p "$INSTALL_DIR"
DEST="${INSTALL_DIR}/${BIN}"
if [ -e "$DEST" ] && [ "$FORCE" -eq 0 ] && [ ! -w "$DEST" ]; then
	err "${DEST} exists and is not writable. Re-run with --force, or choose another directory with --to."
fi
chmod +x "${TMP}/${BIN}"
# Replace via a move within the same directory so the swap is atomic: a process holding the old inode
# keeps running, and no one ever observes a half-written binary.
mv -f "${TMP}/${BIN}" "$DEST"
say "installed ${DEST}"

# Record how this binary arrived. `hilum daemon update` reads it to pick the right upgrade path —
# replacing a file the package manager owns, or asking the package manager to do it. Written by the
# installer because the installer is the only party that knows the truth.
MARKER_DIR="${HOME}/.hilum/local"
mkdir -p "$MARKER_DIR"
printf '{"channel":"tarball","version":"%s","target":"%s","installed_to":"%s"}\n' \
	"$VERSION" "$TARGET" "$INSTALL_DIR" > "${MARKER_DIR}/install.json"

# --- PATH --------------------------------------------------------------------------------------
case ":${PATH}:" in
	*":${INSTALL_DIR}:"*) ;;
	*)
		say ""
		say "${INSTALL_DIR} is not on your PATH. Add this to your shell profile:"
		say "  export PATH=\"${INSTALL_DIR}:\$PATH\""
		;;
esac

say ""
say "Run '${BIN} --version' to confirm, and '${BIN} --help' to see what it does."
