# heartsuite-get

Public distribution surface for HeartSuite.

This thin repository hosts:

- `get-heartsuite.sh` — the recommended bootstrap (`curl -fsSL https://get.heartsuite.io ...`)
- Release assets for the self-extracting installer bundle (`heartsuite-install.sh` + `.sha256`)

## Quick install (end users)

```bash
curl -fsSL https://get.heartsuite.io -o get-heartsuite.sh
less get-heartsuite.sh   # inspect
sudo bash get-heartsuite.sh
```

Or the direct pattern:

```bash
curl -o heartsuite-install.sh https://github.com/HeartSecuritySuite/heartsuite-get/releases/download/vX.Y.Z/heartsuite-install.sh
curl -o heartsuite-install.sh.sha256 .../.sha256
sha256sum -c heartsuite-install.sh.sha256
sudo bash heartsuite-install.sh
```

## For operators / provisioning

See the full documentation and Ansible examples at https://heartsecsuite.com and in the main (private) development repository.

The installer bundle contains the UI overlay + core logic (Python sources are shipped inside and installed to `/opt/heartsuite/src`).

## Releases

Versioned `heartsuite-install.sh` bundles (with matching `.sha256`) are published here under tags `vX.Y.Z`.

The bootstrap script `get-heartsuite.sh` is kept in this repo (update `VERSION` inside it when cutting a new public release).

## License

Business Source License 1.1 — see [LICENSE](LICENSE). Converts to AGPL-3.0 on the Change Date.

Full development sources for the overlay are not published in this repository.
