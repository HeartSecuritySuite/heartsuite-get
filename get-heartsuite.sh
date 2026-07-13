#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Copyright (C) 2026 Heart Security Suite, LLC
# HeartSuite installer bootstrap
#
# Fetches the versioned install bundle from the official distribution site,
# verifies its SHA-256 hash, then runs it.
#
# Recommended (download + verify before run):
#
#   1. curl -fsSL https://get.heartsecsuite.com -o get-heartsuite.sh
#   2. less get-heartsuite.sh     # inspect
#   3. (optional) bash get-heartsuite.sh --help
#   4. sudo bash get-heartsuite.sh
#
# Or pin a release:
#   sudo bash get-heartsuite.sh --version 1.6.7
#   # or: HS_VERSION=1.6.7 sudo -E bash get-heartsuite.sh
#
# Or direct on the bundle (replace vX.Y.Z with the desired version):
#   curl -o heartsuite-install.sh https://heartsecsuite.com/releases/vX.Y.Z/heartsuite-install.sh
#   curl -o heartsuite-install.sh.sha256 https://heartsecsuite.com/releases/vX.Y.Z/heartsuite-install.sh.sha256
#   sha256sum -c heartsuite-install.sh.sha256
#   bash heartsuite-install.sh
#
# GPG (when .sha256.asc published) is behind HS_GPG_VERIFY=1 (default: off).
# This gates the verify path until signing keys + .asc actually ship (per DD-066
# and SHA-256-only decision). Without a flag, clean machines would hard-fail.
# Future: bundle supports --check / makeself inspection (documented in INSTALLER_CHANGES).

set -Eeuo pipefail
trap 'echo "[ERR] line $LINENO: $BASH_COMMAND" >&2' ERR

# Default stamped by build-test-bundle.py; override with --version or HS_VERSION.
DEFAULT_VERSION="1.6.9"
VERSION="${HS_VERSION:-$DEFAULT_VERSION}"

# Bundles are hosted on the official HeartSuite website (your original domain).
# Upload the built heartsuite-install.sh and .sha256 to the corresponding path.
BUNDLE="heartsuite-install.sh"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { printf '\n[heartsuite] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[heartsuite] %s\n' "$*"; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

usage() {
    cat <<EOF
HeartSuite bootstrap — download, verify (SHA-256), run the install bundle.

Usage:
  sudo bash get-heartsuite.sh [options]

Options:
  --version <X.Y.Z>   Install bundle version (default: ${DEFAULT_VERSION};
                      env HS_VERSION also works)
  --help, -h          Show this help and exit

Recommended (inspect before run):
  1. curl -fsSL https://get.heartsecsuite.com -o get-heartsuite.sh
  2. less get-heartsuite.sh
  3. bash get-heartsuite.sh --help
  4. sudo bash get-heartsuite.sh

Direct bundle path:
  curl -o heartsuite-install.sh https://heartsecsuite.com/releases/vX.Y.Z/heartsuite-install.sh
  curl -o heartsuite-install.sh.sha256 \\
    https://heartsecsuite.com/releases/vX.Y.Z/heartsuite-install.sh.sha256
  sha256sum -c heartsuite-install.sh.sha256
  sudo bash heartsuite-install.sh

Optional: HS_GPG_VERIFY=1 enables .sha256.asc check when published (DD-066: off by default).
EOF
}

fetch() {
    # $1 = URL, $2 = destination path
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -O "$2" "$1"
    else
        die "curl or wget is required"
    fi
}

# All the code below is wrapped in main() and invoked at the very end so a
# truncated/partial download (e.g. curl | sh cut off early) does not execute
# any logic (partial-download guard: body only runs after full parse).

main() {
# ── args (before network / root) ──────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --version)
            [ $# -ge 2 ] || die "--version requires a value (e.g. --version 1.6.7)"
            VERSION="${2#v}"
            shift
            ;;
        --*)
            die "unknown option: $1 (try --help)"
            ;;
        *)
            die "unexpected argument: $1 (try --help)"
            ;;
    esac
    shift
done

# Env wins only if --version not used after env; re-read: CLI already set VERSION.
# If user set HS_VERSION and no --version, VERSION already from DEFAULT/HS at top.
# Re-apply HS_VERSION only when still at default and env is set — already done.
RELEASES_BASE="https://heartsecsuite.com/releases/v${VERSION}"
BUNDLE_URL="${RELEASES_BASE}/${BUNDLE}"
SHA256_URL="${RELEASES_BASE}/${BUNDLE}.sha256"

# ── preflight ─────────────────────────────────────────────────────────────────

need_cmd python3
need_cmd sha256sum

if [ "$(id -u)" -ne 0 ]; then
    die "please run as root (sudo bash get-heartsuite.sh)"
fi

# ── download ──────────────────────────────────────────────────────────────────

TMPDIR_HS="$(mktemp -d /tmp/heartsuite-install.XXXXXX)"
trap 'rm -rf "$TMPDIR_HS"' EXIT INT TERM

BUNDLE_PATH="${TMPDIR_HS}/${BUNDLE}"
SHA256_PATH="${TMPDIR_HS}/${BUNDLE}.sha256"

info "Downloading HeartSuite ${VERSION} …"
fetch "$BUNDLE_URL"  "$BUNDLE_PATH"
fetch "$SHA256_URL"  "$SHA256_PATH"

# ── verify ────────────────────────────────────────────────────────────────────

info "Verifying SHA-256 …"

# The .sha256 file stores the hash with the original filename; rewrite the
# path component so sha256sum -c can find the file in TMPDIR_HS.
EXPECTED_HASH="$(awk '{print $1}' "$SHA256_PATH")"
printf '%s  %s\n' "$EXPECTED_HASH" "$BUNDLE_PATH" | sha256sum -c - >/dev/null \
    || die "SHA-256 mismatch — download may be corrupt or tampered"

info "Checksum OK."

# ── optional GPG signature verification (gated behind HS_GPG_VERIFY) ─────────
# Gated until .asc + pinned key handling ship. On clean keyring, gpg --verify
# would fail with "no public key" and die. Set HS_GPG_VERIFY=1 to enable.
if [ "${HS_GPG_VERIFY:-0}" = "1" ]; then
    ASC_URL="${SHA256_URL}.asc"
    ASC_PATH="${TMPDIR_HS}/${BUNDLE}.sha256.asc"
    if fetch "$ASC_URL" "$ASC_PATH"; then
        if command -v gpg >/dev/null 2>&1; then
            gpg --verify "$ASC_PATH" "$SHA256_PATH" || die "GPG signature verification failed"
        else
            info "gpg not found — skipping signature verification (see release notes for manual GPG setup)"
        fi
    fi
fi

# ── run ───────────────────────────────────────────────────────────────────────

chmod +x "$BUNDLE_PATH"
info "Running installer …"
exec "$BUNDLE_PATH"
}

main "$@"
