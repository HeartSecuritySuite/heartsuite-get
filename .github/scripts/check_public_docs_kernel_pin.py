#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-HeartSuite-ELA
# Copyright (C) 2026 Heart Security Suite, LLC
"""Fail when public Docsy pages still name an older kernel than the installer.

The customer curl bootstrap (heartsuite-get) only stores a product version.
The kernel build counter and vmlinuz hash live in BUILD_MANIFEST.txt inside
heartsuite-install.sh. This check reads that manifest and requires the Docsy
pages that describe the kernel that ships to name the same counter, the same
vmlinuz hash, and the checker totals printed in the current evidence pack.

Two trees carry this file and the bytes must match. The bundler and the tests
use heartsuite tools/check_public_docs_kernel_pin.py. The public release
workflow uses heartsuite-get .github/scripts/check_public_docs_kernel_pin.py.
heartsuite is private, so that workflow cannot check it out.

It does not rescore CVEs, recount modules, or boot a guest. A page can pass
this gate and still be wrong about a residual score.

Usage::

    python3 tools/check_public_docs_kernel_pin.py \\
        --manifest path/to/BUILD_MANIFEST.txt \\
        --docs path/to/heartsuite-docs

    python3 tools/check_public_docs_kernel_pin.py \\
        --install-sh dist/heartsuite-install.sh \\
        --docs path/to/heartsuite-docs

Exit 0 when the pages match. Exit 1 and print one line per stale page.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

_DOCS = Path("content/en/rootlock/kernel-hardening")
_STATUS = _DOCS / "evidence-status.md"
_PACK = _DOCS / "evidence-pack-6.18.9.txt"
_MATRIX = _DOCS / "kernel-comparison-matrix-6.18.9.md"
_PROCUREMENT = _DOCS / "procurement-brief.md"
_AUDITOR = _DOCS / "auditor-brief.md"
_DISTRO = _DOCS / "distro-compatibility-matrix.md"
_SUPPLY = _DOCS / "supply-chain-and-advisories.md"


def parse_manifest(text: str) -> dict[str, str]:
    """Parse ``key: value`` lines. Values may contain colons."""
    out: dict[str, str] = {}
    for line in text.splitlines():
        key, sep, value = line.partition(":")
        if sep and key.strip() and key == key.lstrip():
            out[key.strip()] = value.strip()
    return out


def read_install_manifest(install_sh: Path) -> str:
    """Return BUILD_MANIFEST.txt from a makeself heartsuite-install.sh."""
    for member in ("./BUILD_MANIFEST.txt", "BUILD_MANIFEST.txt"):
        proc = subprocess.run(
            ["bash", str(install_sh), "--tar", "xOf", member],
            capture_output=True,
            timeout=180,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout.decode("utf-8", errors="replace")
    raise RuntimeError(f"BUILD_MANIFEST.txt is not readable from {install_sh}")


def _read(docs: Path, rel: Path) -> str:
    path = docs / rel
    if not path.is_file():
        raise FileNotFoundError(path)
    return path.read_text(encoding="utf-8")


def _subject(text: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("**Subject:**") or stripped.startswith("Subject:"):
            return stripped
    return ""


def _line_with(text: str, needle: str) -> str:
    for line in text.splitlines():
        if needle in line:
            return line.strip()
    return ""


def _pack_scores(pack: str) -> tuple[str, str, str] | None:
    """Return overall, attack-surface, and exploit-resistance from the pack.

    The first cell of each category row is the kernel that ships. The overall
    count is the ``HS <uname> #<n>`` row in the checker table.
    """
    overall = re.search(
        r"^HS \S+ #\d+\s+\|\s+(\d+)\s+\|\s+\d+\s+\|\s+(\d+)\s+\|\s+([\d.]+)",
        pack,
        re.M,
    )
    attack = re.search(
        r"^cut_attack_surface\s+\|\s+(\d+/\d+ \(\d+\.\d+%\))",
        pack,
        re.M,
    )
    resist = re.search(
        r"^self_protection\s+\|\s+(\d+/\d+ \(\d+\.\d+%\))",
        pack,
        re.M,
    )
    if not (overall and attack and resist):
        return None
    ok, total, pct = overall.group(1), overall.group(2), overall.group(3)
    return f"{ok}/{total} ({pct}%)", attack.group(1), resist.group(1)


def check_docs(docs: Path, manifest: dict[str, str]) -> list[str]:
    """Return human-readable problems. Empty means the pages match."""
    problems: list[str] = []
    counter = manifest.get("kernel_build", "")
    uname = manifest.get("kernel_uname_r", "")
    sha = manifest.get("kernel_sha256", "")
    if not re.fullmatch(r"#\d+", counter):
        problems.append(
            f"BUILD_MANIFEST kernel_build must look like #NN, got {counter!r}"
        )
        return problems
    if not uname:
        problems.append("BUILD_MANIFEST kernel_uname_r is empty")
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        problems.append(
            f"BUILD_MANIFEST kernel_sha256 must be 64 hex chars, got {sha!r}"
        )

    try:
        status = _read(docs, _STATUS)
        pack = _read(docs, _PACK)
        matrix = _read(docs, _MATRIX)
        procurement = _read(docs, _PROCUREMENT)
        auditor = _read(docs, _AUDITOR)
        distro = _read(docs, _DISTRO)
        supply = _read(docs, _SUPPLY)
    except FileNotFoundError as exc:
        problems.append(f"missing docs file: {exc}")
        return problems

    ships = _line_with(status, "Kernel that ships")
    if counter not in ships or (uname and uname not in ships):
        problems.append(
            f"{_STATUS}: 'Kernel that ships' must name {uname} {counter}"
        )

    pack_subject = _subject(pack)
    if counter not in pack_subject:
        problems.append(f"{_PACK}: Subject must name build {counter}")
    if sha and sha not in pack:
        problems.append(f"{_PACK}: missing vmlinuz sha256 {sha}")

    matrix_subject = _subject(matrix)
    if counter not in matrix_subject or (uname and uname not in matrix_subject):
        problems.append(f"{_MATRIX}: Subject must name {uname} {counter}")

    scores = _pack_scores(pack)
    if scores is None:
        problems.append(f"{_PACK}: checker table has no HS {counter} score row")
    else:
        overall, attack, resist = scores
        for label, token in (
            ("overall", overall),
            ("attack-surface", attack),
            ("exploit-resistance", resist),
        ):
            if token not in matrix:
                problems.append(
                    f"{_MATRIX}: missing {label} {token} from the evidence pack"
                )

    for rel, text in ((_PROCUREMENT, procurement), (_AUDITOR, auditor)):
        if counter not in _subject(text):
            problems.append(f"{rel}: Subject must name build {counter}")

    expect = _line_with(distro, "build `")
    if counter not in expect:
        problems.append(f"{_DISTRO}: the build line must name {counter}")

    supply_expect = _line_with(supply, "expect")
    supply_pin = _line_with(supply, "Fielded pin")
    if counter not in supply_expect:
        problems.append(f"{_SUPPLY}: the expect line must name {counter}")
    if counter not in supply_pin:
        problems.append(f"{_SUPPLY}: the fielded-pin line must name {counter}")

    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--manifest", type=Path, help="Staged BUILD_MANIFEST.txt")
    source.add_argument(
        "--install-sh",
        type=Path,
        help="Customer heartsuite-install.sh (makeself)",
    )
    parser.add_argument("--docs", type=Path, required=True, help="heartsuite-docs root")
    args = parser.parse_args(argv)

    if args.manifest is not None:
        manifest_text = args.manifest.read_text(encoding="utf-8")
    else:
        try:
            manifest_text = read_install_manifest(args.install_sh)
        except (OSError, RuntimeError) as exc:
            print(f"public docs pin: {exc}", file=sys.stderr)
            return 1
    problems = check_docs(args.docs, parse_manifest(manifest_text))
    if problems:
        print("public docs do not match this kernel:", file=sys.stderr)
        for item in problems:
            print(f"  {item}", file=sys.stderr)
        return 1
    manifest = parse_manifest(manifest_text)
    print(
        "public docs name "
        f"{manifest.get('kernel_uname_r', '')} {manifest.get('kernel_build', '')}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
