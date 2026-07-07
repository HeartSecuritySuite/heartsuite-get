#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Copyright (C) 2026 Heart Security Suite, LLC
# HeartSuite installer bootstrap
#
# Fetches the versioned install bundle, verifies SHA-256, then runs it.
#
# The stable user-facing entrypoint is the original:
#   curl -fsSL https://get.heartsuite.io -o get-heartsuite.sh
#   less get-heartsuite.sh
#   sudo bash get-heartsuite.sh
#
# Bundles are hosted on the official site (your original domain).

set -Eeuo pipefail
trap 'echo "[ERR] line $LINENO: $BASH_COMMAND" >&2' ERR

VERSION="1.6.7"

# Stick to original hosting domain for the actual bundles.
# Upload heartsuite-install.sh + .sha256 to this location on your web host.
RELEASES_BASE="https://heartsecsuite.com/releases/v${VERSION}"
BUNDLE="heartsuite-install.sh"
BUNDLE_URL="${RELEASES_BASE}/${BUNDLE}"
SHA256_URL="${RELEASES_BASE}/${BUNDLE}.sha256"

die() { printf '\n[heartsuite] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[heartsuite] %s\n' "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -O "$2" "$1"
    else
        die "curl or wget is required"
    fi
}

main() {
    need_cmd python3
    need_cmd sha256sum

    if [ "$(id -u)" -ne 0 ]; then
        die "please run as root (sudo bash get-heartsuite.sh)"
    fi

    TMPDIR_HS="$(mktemp -d /tmp/heartsuite-install.XXXXXX)"
    trap 'rm -rf "$TMPDIR_HS"' EXIT INT TERM

    BUNDLE_PATH="${TMPDIR_HS}/${BUNDLE}"
    SHA256_PATH="${TMPDIR_HS}/${BUNDLE}.sha256"

    info "Downloading HeartSuite ${VERSION} …"
    fetch "$BUNDLE_URL" "$BUNDLE_PATH"
    fetch "$SHA256_URL" "$SHA256_PATH"

    info "Verifying SHA-256 …"
    EXPECTED_HASH="$(awk '{print $1}' "$SHA256_PATH")"
    printf '%s  %s\n' "$EXPECTED_HASH" "$BUNDLE_PATH" | sha256sum -c - >/dev/null \
        || die "SHA-256 mismatch"

    info "Checksum OK."

    if [ "${HS_GPG_VERIFY:-0}" = "1" ]; then
        ASC_URL="${SHA256_URL}.asc"
        ASC_PATH="${TMPDIR_HS}/${BUNDLE}.sha256.asc"
        if fetch "$ASC_URL" "$ASC_PATH" 2>/dev/null; then
            if command -v gpg >/dev/null 2>&1; then
                gpg --verify "$ASC_PATH" "$SHA256_PATH" || die "GPG failed"
            fi
        fi
    fi

    chmod +x "$BUNDLE_PATH"
    info "Running installer …"
    exec "$BUNDLE_PATH"
}

main "$@"
