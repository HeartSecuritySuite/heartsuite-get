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
# Direct bundle (1.7.0 public curl is the beta channel directory; VERSION stays 1.7.0):
#   curl -o heartsuite-install.sh https://heartsecsuite.com/releases/v1.7.0-beta/heartsuite-install.sh
#   curl -o heartsuite-install.sh.sha256 https://heartsecsuite.com/releases/v1.7.0-beta/heartsuite-install.sh.sha256
#   sha256sum -c heartsuite-install.sh.sha256
#   bash heartsuite-install.sh
#
# Other numbered releases stay under /releases/vX.Y.Z/.
#
# GPG (when .sha256.asc published) is behind HS_GPG_VERIFY=1 (default: off).
# When the flag is on, verify is fail-closed and pinned to HS_GPG_FINGERPRINT
# (DD-066: personal OpenPGP key on Nitrokey 3, Apache/Debian maintainer model).

set -Eeuo pipefail
trap 'echo "[ERR] line $LINENO: $BASH_COMMAND" >&2' ERR

# Default stamped by build-test-bundle.py; override with --version or HS_VERSION.
DEFAULT_VERSION="1.7.0"
VERSION="${HS_VERSION:-$DEFAULT_VERSION}"

# DD-105: public 1.7.0 curl lives under /releases/v1.7.0-beta/. VERSION stays 1.7.0.
channel_dir() {
    case "$1" in
        1.7.0) printf '%s' 'v1.7.0-beta' ;;
        *) printf 'v%s' "$1" ;;
    esac
}

# Bundles are hosted on the official HeartSuite website (your original domain).
# Upload the built heartsuite-install.sh, .sha256, and .sha256.asc (when signing).
BUNDLE="heartsuite-install.sh"

# Personal OpenPGP signing key (DD-066). Signing subkey on Nitrokey 3.
HS_GPG_FINGERPRINT="BD77B174DAE8B425040B46ACDE42D4B3154111BA"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { printf '\n[heartsuite] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[heartsuite] %s\n' "$*"; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

write_pinned_pubkey() {
    # $1 = dest path. Must match dist/KEYS armor (tests/test_installer_gpg.py).
    cat > "$1" <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZpvHsBYJKwYBBAHaRw8BAQdAxHdhLGKoVTKvmYtDjifvWsKMqM1AQ56IT5uD
TSUSJFW0I1JvbiBIZXNzaW5nIDxsaW51eC1sb3ZlQHBvc3Rlby5uZXQ+iJAEExYI
ADgWIQS9d7F02ui0JQQLRqzeQtSzFUERugUCZpvHsAIbAwULCQgHAgYVCgkICwIE
FgIDAQIeAQIXgAAKCRDeQtSzFUERutmjAQDXwV/dBRf+PAHAXj6BWfoCQKLGUgMC
3LfjgbbNsmhoxQEA9SkuCDanD5OgG3IS8zKlYf+pZRexcNr4sB3W2ugLFgG4OARm
m8ewEgorBgEEAZdVAQUBAQdA46a08zPUwErWHq281RSGwLSQwzGs1C0NVVVjxt57
El0DAQgHiHgEGBYIACAWIQS9d7F02ui0JQQLRqzeQtSzFUERugUCZpvHsAIbDAAK
CRDeQtSzFUERugMjAP9Tux2GYUEgD0cE5qli6WNzDdFjSRQE/6KUckdMih55UQD/
XUGwE6v78cmezsDDz24DbSnUiMUQOm3w1F7auQuhdQC4MwRmm8kFFgkrBgEEAdpH
DwEBB0Bwz1sZQh3InxP/GbD4UggYNpBc2XSF1RN9rHNNVEQ4Zoh4BBgWCgAgFiEE
vXexdNrotCUEC0as3kLUsxVBEboFAmabyQUCGyAACgkQ3kLUsxVBEbqZKQEAgHR7
RF7taK4CQs5v77d6modbUj+udu3Esmn5H+VByeIBALuDokj3EDKe+DPN2A+aQTs/
OyYgK0EdiF4H0qSbWYUGuDMEZpv8JxYJKwYBBAHaRw8BAQdAL6h8hc8vNFS2HA9G
ixe0cZgebbY1UWb06UGQ920KSCqI7gQYFggAIBYhBL13sXTa6LQlBAtGrN5C1LMV
QRG6BQJmm/wnAhsCAIEJEN5C1LMVQRG6diAEGRYIAB0WIQQ61v+06UG8+Lvh6ia7
46+qcdjhfQUCZpv8JwAKCRC746+qcdjhfWArAPwOe8530VmnkgIKwjXsgjob1rbU
f6SsFjYdlu8BqQ6ohgEAguCP0lWIckD1wp3o64RUZqWYJGBtsoY/IQVQ+FF0vQlu
dQD4n3MgWGzqwKP+dFh8w36T1BKtJ4VlzwQClXHCp8igXgEA3VM9WUIGnyRDq60j
HWapBPFr19RYQIp9JT14z423ugE=
=0Oql
-----END PGP PUBLIC KEY BLOCK-----
EOF
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

Direct bundle path (1.7.0 public curl: /releases/v1.7.0-beta/):
  curl -o heartsuite-install.sh https://heartsecsuite.com/releases/v1.7.0-beta/heartsuite-install.sh
  curl -o heartsuite-install.sh.sha256 \\
    https://heartsecsuite.com/releases/v1.7.0-beta/heartsuite-install.sh.sha256
  sha256sum -c heartsuite-install.sh.sha256
  sudo bash heartsuite-install.sh

Optional: HS_GPG_VERIFY=1 verifies .sha256.asc against the pinned key
(DD-066: off by default until .asc is published).
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
RELEASES_BASE="https://heartsecsuite.com/releases/$(channel_dir "$VERSION")"
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

if [ "$VERSION" = "1.7.0" ]; then
    info "Downloading HeartSuite ${VERSION} beta …"
else
    info "Downloading HeartSuite ${VERSION} …"
fi
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
# Default off until .sha256.asc is published with the bundle. When on: fail
# closed (missing .asc, missing gpg, bad sig, or wrong key all die).
if [ "${HS_GPG_VERIFY:-0}" = "1" ]; then
    need_cmd gpg
    ASC_URL="${SHA256_URL}.asc"
    ASC_PATH="${TMPDIR_HS}/${BUNDLE}.sha256.asc"
    fetch "$ASC_URL" "$ASC_PATH" || die "GPG signature missing at ${ASC_URL}"
    GPGHOME="$(mktemp -d "${TMPDIR_HS}/gnupg.XXXXXX")"
    chmod 700 "$GPGHOME"
    write_pinned_pubkey "${GPGHOME}/pinned.asc"
    GNUPGHOME="$GPGHOME" gpg --batch --quiet --import "${GPGHOME}/pinned.asc" \
        || die "failed to import pinned signing key"
    STATUS="$(GNUPGHOME="$GPGHOME" gpg --batch --status-fd 1 --verify "$ASC_PATH" "$SHA256_PATH" 2>/dev/null)" \
        || die "GPG signature verification failed"
    printf '%s\n' "$STATUS" | grep -q '^\[GNUPG:\] GOODSIG ' \
        || die "GPG signature verification failed"
    printf '%s\n' "$STATUS" | grep '^\[GNUPG:\] VALIDSIG ' | grep -q "$HS_GPG_FINGERPRINT" \
        || die "GPG signature is not from the pinned key ${HS_GPG_FINGERPRINT}"
    info "GPG signature OK."
fi

# ── run ───────────────────────────────────────────────────────────────────────

chmod +x "$BUNDLE_PATH"
info "Running installer …"
exec "$BUNDLE_PATH"
}

main "$@"
