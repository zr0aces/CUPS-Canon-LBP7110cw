# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] — 2026-04-15

### Added
- **Drivers now managed in Git**: The Canon UFRII LT driver tarball is now tracked directly in the repository. This ensures that the build context always has the necessary files, preventing "missing file" errors during local builds or CI/CD pipelines.

### Changed
- **`.gitignore` updated**: Removed exclusion for the `download/` directory to allow tracking the driver tarball.
- **`download-driver.sh` updated**: Script revised (v1.1.0) to primarily verify the integrity of pre-included drivers rather than just downloading them.
- **`README.md` updated**: Refreshed the Quick Start guide to reflect the new driver management policy.

---

## [1.0.2] — 2026-04-15

### Security
- **`ADMIN_PASSWORD` removed from Dockerfile `ENV`** (#4). Storing a default
  password in `ENV` permanently embeds it in the image layer history, visible
  via `docker history`. The entrypoint now applies the bash fallback
  `${ADMIN_PASSWORD:-admin}` at runtime, leaving no trace in the image.
- **`ADMIN_PASSWORD` validated before `chpasswd`** (#6). A colon (`:`) in the
  password value is silently treated as a field separator by `chpasswd`, causing
  a different password to be set. The entrypoint now rejects passwords containing
  a colon with a clear error message before any account change is made.

### Bug Fixes
- **SIGTERM trap added to entrypoint** (#2). The monitoring loop now registers a
  `_shutdown()` handler via `trap … SIGTERM SIGINT SIGQUIT`. `docker stop` and
  `docker compose down` previously waited the full grace period before SIGKILL-ing
  `cupsd` mid-job (risking spool corruption). The handler sends `SIGTERM` to all
  managed processes and waits up to 10 s for `cupsd` to flush and exit cleanly.
  The `sleep` inside the loop was changed to `sleep 10 & wait $!` so that signals
  interrupt the sleep and invoke the trap immediately.
- **Dockerfile PPD verification is now non-fatal** (#3). The `grep -i canon`
  step previously would exit 1 (under `set -eux`) if no Canon PPDs were found in
  `/usr/share/cups/model`, aborting the build with a cryptic error. It now emits
  a `WARNING:` message and continues, allowing the build to produce a useful
  diagnostic instead of a silent failure.
- **Missing `v1.0.1` git tag applied** (#5). The v1.0.1 release commit (`6cff97c`)
  existed on `main` but was never tagged, so the GitHub Actions workflow (which
  triggers on `v*.*.*` tag pushes) would never have built or pushed the v1.0.1
  image to GHCR.

### Performance
- **`.dockerignore` added** (#1). Without it, `docker build` transferred the full
  21 MB Canon driver tarball, the entire `.git/` history, and all runtime state
  directories (cups-config/, cups-logs/, cups-spool/) to the Docker daemon on
  every build. The new `.dockerignore` excludes all non-essential files while
  keeping the driver tarball (required by `COPY`).
- **Resource limits added to `docker-compose.yml`** (#7). A `deploy.resources`
  block capping memory at 512 MB (reserved 128 MB) and a `logging` block limiting
  container JSON logs to 20 MB × 5 files prevent a flood of print jobs from
  exhausting host resources.
- **CUPS log rotation configured** (#8). `MaxLogSize 10m`, `PreserveJobHistory No`,
  and `PreserveJobFiles No` added to the `cupsd.conf` heredoc in the Dockerfile.
  Previously, `access_log`, `error_log`, and `page_log` inside the `cups-logs`
  volume grew without bound.
- **`RUN chmod +x` layer eliminated** (#9). The Dockerfile now uses
  `COPY --chmod=755 docker-entrypoint.sh` instead of a separate `RUN chmod`
  instruction, removing one image layer.

### CI
- **Concurrency guard added to GitHub Actions release workflow** (#10). A
  `concurrency` group prevents two release builds from running simultaneously for
  the same tag (e.g., due to a force-push or rapid succession of tag pushes).

### Added
- **`SECURITY.md`** (#11). Documents the responsible disclosure process, response
  timeline, supported versions, and scope for security reports.
- **`.dockerignore`** (#1). See Performance section above.

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
- **Example print-client retained as standalone configuration** (#22). The `example/docker-compose.yml` file is maintained as an independent configuration block intended solely as a reference configuration for client testing.
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
