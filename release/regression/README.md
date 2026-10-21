# Regression checks

Each `*.sh` file here is mounted read-only into the image at
`/release/regression/` and run with `sh`. It must exit 0 only when the issue
it covers is fixed. Add one for every patch in `php72-patches/` and for every
other security fix in the image.

`lib/` holds shared helpers and is not run directly. `lib/fpm.sh` starts a
private php-fpm7.2 master with a single static worker on 127.0.0.1, so
consecutive requests reach the same process, and `lib/fcgi.php` sends
FastCGI requests to it the way nginx does.

| Check | Patch |
| --- | --- |
| `cve-2026-109618-oom.sh` | `0001-CVE-2026-109618-109619.patch` (out-of-memory handling, multipart headers) |
| `cve-2026-109619-state.sh` | `0001-CVE-2026-109618-109619.patch` (state reset, session upload progress) |
| `nginx-auth.sh` | `sources/nginx-site.conf` (PHP scripts require the ruTorrent login) |
