# heartsuite-get

Thin public distribution surface for the HeartSuite installer bootstrap.

Served at **https://get.heartsecsuite.com** via GitHub Pages (custom domain CNAME).

## Contents

| File | Purpose |
|------|---------|
| `get-heartsuite.sh` | Bootstrap script — downloads and verifies the install bundle |
| `index.html` | Landing page with the one-liner install command |
| `CNAME` | GitHub Pages custom domain (`get.heartsecsuite.com`) |

Install bundles (`heartsuite-install.sh` + `.sha256`) for numbered releases are
hosted at `https://heartsecsuite.com/releases/vX.Y.Z/`. The 1.7.0 public curl is
the **beta** GitHub Release `v1.7.0-beta` on this repo (`VERSION` stays 1.7.0).

## Release workflow

1. Build a release in the main `heartsuite` repo: `python3 dist/build-test-bundle.py`
2. The builder stamps `DEFAULT_VERSION` and copies `get-heartsuite.sh` here (sibling checkout)
3. Attach `heartsuite-install.sh`, `.sha256`, and `.sha256.asc` to GitHub Release `v1.7.0-beta` (1.7.0 public curl), or upload other numbers to `heartsecsuite.com/releases/v${VERSION}/`
4. Commit and push this repo, then verify:

```bash
curl -fsSL https://get.heartsecsuite.com/get-heartsuite.sh | head -5
```

## GitHub Pages setup

In **Settings → Pages** for this repo:

- Source: branch `main`, folder `/ (root)`
- Custom domain: `get.heartsecsuite.com` (DNS CNAME → `heartsecuritysuite.github.io`)
- Enforce HTTPS once the certificate is issued

This repo must be **public** for unauthenticated curl installs.