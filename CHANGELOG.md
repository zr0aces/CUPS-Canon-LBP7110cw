# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] — 2026-04-15

### Security
- **Admin endpoints now require authentication** (`/admin`, `/admin/conf`,
  `/admin/log` all have `AuthType Default` + `Require user @SYSTEM`). Previously
  these paths used `Allow all` with no auth requirement.
- **Removed hardcoded `ADMIN_PASSWORD` from `docker-compose.yml`**. The admin
  password is now sourced exclusively from `.env`, keeping secrets out of version
  control.
- **SHA256 integrity verification** added to `download-driver.sh`. Both the
  cached copy on disk and every fresh download are verified against the known
  checksum (`46888140016bc1096694a0fd6fd3f6ad393970b8153756373a382dc82390f259`)
  before proceeding.
- **SHA256 verification step in GitHub Actions CI** (`docker-release.yml`).
  The pipeline now verifies the driver tarball hash before building the image,
  preventing a compromised CDN or MITM from injecting a malicious driver.
- **Admin password masked in startup log**. The plaintext password is no longer
  printed to `docker logs`; it is replaced with asterisks.

### Bug Fixes
- **`cupsd` shutdown in Dockerfile build is now reliable** (#8). Replaced the
  hardcoded `sleep 2` after `pkill cupsd` with a `timeout 15` polling loop that
  waits for the process to actually exit.
- **Monitoring loop now restarts `avahi-daemon` and `dbus-daemon`** (#9). If
  either service crashes (common in container environments without systemd),
  the loop will attempt to restart it every 10 seconds.
- **`lpadmin -x` output is now logged** (#11). Removal of stale printer queues
  is no longer silently swallowed — output is routed through the `log()` helper.
- **CUPS ready timing message is now accurate** (#10). The "ready after Ns"
  message now reflects actual elapsed seconds rather than off-by-one counting.
- **`download/` directory is now excluded from Git** (#12). The `download/`
  entry in `.gitignore` was accidentally commented out, risking the 21 MB
  driver tarball being committed.

### Performance
- **Dockerfile layer count reduced** (#13). The CUPS configuration (`cupsd.conf`
  sed patch) and `usermod` were merged into the driver installation `RUN` block,
  removing two unnecessary image layers.
- **`find_ppd()` search scope limited** (#14). The PPD fallback search now uses
  `maxdepth 5` over known PPD directories instead of scanning all of `/usr`.
- **Healthcheck definitions unified** (#15). The `docker-compose.yml` definition
  is now the authoritative healthcheck (with a `10s` timeout and `--max-time 8`
  for `curl`). The `Dockerfile HEALTHCHECK` remains only as a fallback for
  `docker run` without compose.
- **Driver filename parameterised as a build `ARG`** (#16). The tarball filename
  is now `ARG DRIVER_FILE=linux-UFRIILT-drv-v500-uken-18.tar.gz`, making future
  driver version upgrades a one-line change (`--build-arg DRIVER_FILE=...`).

### Changed
- **Example print-client uses Docker Compose profiles** (#22). The `print-client`
  service is now part of the root `docker-compose.yml` under `profiles: [example]`
  and is **off by default**. Run with `docker compose --profile example up` to
  activate it. The `example/docker-compose.yml` file is deprecated.
- **`.env-example` expanded** (#4). Now documents all six supported variables
  (`PRINTER_IP`, `ADMIN_PASSWORD`, `PRINTER_NAME`, `PRINTER_PPD`,
  `CUPS_LOGLEVEL`, `CUPS_ENV_DEBUG`) with descriptions and safe defaults.
- **`.gitignore` improved** (#21). Volume directories use a glob pattern
  (`dir/*`, `!dir/.gitkeep`) to track the empty directories in Git while
  excluding their runtime-generated contents.
- **ARM64 exclusion documented in CI** (#17). The `platforms: linux/amd64`
  line in `docker-release.yml` now has an inline comment explaining why `arm64`
  is excluded (Canon's UFRII LT driver is x86-only).
- **`set -uo pipefail` comment added** (#18). The absence of `-e` in the
  entrypoint's `set` flags is now explained inline, preventing future
  accidental additions that would break the monitoring loop.
- **Base image pinning guidance added** (#20). The `Dockerfile` now includes a
  comment with the exact command to retrieve and pin the `ubuntu:22.04` digest.
  The production checklist in `README.md` includes this step.
- **Image labels added**. The `Dockerfile` now includes
  `org.opencontainers.image.version` and `org.opencontainers.image.source`
  OCI labels for better container registry metadata.

---

## [1.0.0] — 2026-04-14

### Added
- Initial release of CUPS + Canon LBP7110Cw Docker setup.
- Canon UFRII LT driver v5.00 installed via official `install.sh` at build time.
- Automatic printer registration at container startup via `docker-entrypoint.sh`.
- CUPS Web UI accessible on port 631.
- Docker Compose setup with named volumes for persistent configuration, spool,
  and logs.
- Health check to monitor CUPS status and coordinate dependent containers.
- `download-driver.sh` to fetch the Canon driver tarball before building.
- Pre-built image available via GitHub Container Registry (`ghcr.io`).
- Based on ManuelKlaer/docker-cups-canon (forked from ydkn/olbat).
