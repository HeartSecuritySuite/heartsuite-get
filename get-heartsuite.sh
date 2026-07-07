#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Copyright (C) 2026 Heart Security Suite, LLC
# HeartSuite installer bootstrap
#
# Fetches the versioned install bundle from GitHub Releases, verifies its
# SHA-256 hash, then runs it.
#
# Recommended (download + verify before run; see also curl -o && sha && bash):
#
#   curl -fsSL https://get.heartsuite.io -o get-heartsuite.sh
#   less get-heartsuite.sh     # read it
#   bash get-heartsuite.sh
#
# Or direct on the bundle (after obtaining heartsuite-install.sh + .sha256):
#   curl -o heartsuite-install.sh <URL>
#   sha256sum -c heartsuite-install.sh.sha256
#   bash heartsuite-install.sh
#
# GPG (when .sha256.asc published) is behind HS_GPG_VERIFY=1 (default: off).
# This gates the verify path until signing keys + .asc actually ship (per DD-066
# and SHA-256-only decision). Without a flag, clean machines would hard-fail.
# Future: bundle supports --check / makeself inspection (documented in INSTALLER_CHANGES).

set -Eeuo pipefail
trap 'echo "[ERR] line $LINENO: $BASH_COMMAND" >&2' ERR

VERSION="1.6.7"
RELEASES_BASE="https://github.com/HeartSecuritySuite/heartsuite-get/releases/download/v${VERSION}"
BUNDLE="heartsuite-install.sh"
BUNDLE_URL="${RELEASES_BASE}/${BUNDLE}"
SHA256_URL="${RELEASES_BASE}/${BUNDLE}.sha256"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { printf '\n[heartsuite] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[heartsuite] %s\n' "$*"; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
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
# any logic. (Tailscale pattern for partial-download guard)

main() {
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
