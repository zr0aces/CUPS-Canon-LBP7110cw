FROM ubuntu:22.04
# Tip (#20): Pin to a digest in production:
#   FROM ubuntu:22.04@sha256:<digest>
# Get the current digest with:
#   docker pull ubuntu:22.04 && docker inspect ubuntu:22.04 --format '{{index .RepoDigests 0}}'

LABEL maintainer="cups-canon-lbp7110cw"
LABEL description="CUPS print server for Canon LBP7110Cw – based on ManuelKlaer/docker-cups-canon, driver installed via Canon's official install.sh"
LABEL org.opencontainers.image.version="1.1.0"
LABEL org.opencontainers.image.source="https://github.com/zr0aces/CUPS-Canon-LBP7110cw"

ENV DEBIAN_FRONTEND=noninteractive

# ── Runtime defaults (all overridable via -e / environment: in compose) ────────
# NOTE: ADMIN_PASSWORD is intentionally omitted from ENV — storing a default
# password here permanently embeds it in the image layer history visible via
# `docker history`. The entrypoint applies the bash fallback at runtime. (#4)
ENV CUPS_LOGLEVEL=warn \
    CUPS_ENV_DEBUG=no \
    PRINTER_NAME=Canon_LBP7110Cw \
    PRINTER_IP=192.168.1.100 \
    PRINTER_PPD=CNRCUPSLBP7110CZNK.ppd

# ── Build argument: driver tarball filename (#16) ──────────────────────────────
# Override with --build-arg DRIVER_FILE=... to support future driver versions.
ARG DRIVER_FILE=linux-UFRIILT-drv-v500-uken-18.tar.gz

# ── 1. Base system packages ───────────────────────────────────────────────────
#    Matches the ManuelKlaer/docker-cups-canon package set, plus Canon driver
#    runtime dependencies (libxml2, libpng16-16, ghostscript, poppler-utils).
RUN apt-get update && apt-get install -y --no-install-recommends \
        # CUPS printing stack
        cups \
        cups-client \
        cups-bsd \
        cups-filters \
        # PPD / driver databases (same as ManuelKlaer)
        foomatic-db-engine \
        foomatic-db-compressed-ppds \
        printer-driver-all \
        printer-driver-cups-pdf \
        openprinting-ppds \
        hpijs-ppds \
        hp-ppd \
        # Network / utilities (same as ManuelKlaer)
        sudo \
        whois \
        usbutils \
        smbclient \
        avahi-utils \
        avahi-daemon \
        dbus \
        # Canon UFRII LT driver runtime dependencies
        libcups2 \
        libcupsimage2 \
        libxml2 \
        libpng16-16 \
        ghostscript \
        poppler-utils \
        # Build-step tools
        curl \
        tar \
        procps \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Copy the pre-downloaded Canon UFRII LT v5.00 driver tarball ────────────
#    Run  ./download-driver.sh  first so this file exists in the build context.
#    The Dockerfile intentionally uses COPY (not RUN wget) so the build works
#    in air-gapped / network-restricted environments.
COPY download/${DRIVER_FILE} /tmp/canon-driver.tar.gz

# ── 3. Extract tarball, run Canon's installer, configure CUPS, and clean up ───
#
#    install.sh asks exactly two Y/N questions:
#      Q1 "proceed with installation? [Y/n]" → Y  (install the packages)
#      Q2 "register printer now?      [Y/n]" → N  (skip – done at runtime
#                                                   by docker-entrypoint.sh
#                                                   so PRINTER_IP is flexible)
#
#    install.sh requires cupsd running before it executes because it calls
#    `service cups restart` after dpkg. We start cupsd temporarily, run the
#    installer, then wait for it to exit cleanly (#8).
#
#    CUPS config and usermod are merged here to minimise image layers (#13).
RUN set -eux \
    # ── Extract ──────────────────────────────────────────────────────────────
    && mkdir -p /tmp/canon-driver \
    && tar -xzf /tmp/canon-driver.tar.gz -C /tmp/canon-driver \
    && echo "=== Extracted driver layout ===" \
    && find /tmp/canon-driver -maxdepth 5 \
    \
    # ── Locate install.sh ────────────────────────────────────────────────────
    && INSTALL_SH=$(find /tmp/canon-driver -maxdepth 3 -name "install.sh" | head -1) \
    && [ -n "$INSTALL_SH" ] \
        || { echo "ERROR: install.sh not found in tarball"; exit 1; } \
    && echo "=== install.sh: $INSTALL_SH ===" \
    && chmod +x "$INSTALL_SH" \
    \
    # ── Start temporary cupsd for the installer ───────────────────────────────
    && mkdir -p /run/cups /var/spool/cups/tmp /var/log/cups \
    && /usr/sbin/cupsd \
    && for i in $(seq 1 15); do \
           curl -sf http://localhost:631/ >/dev/null 2>&1 && break; \
           sleep 1; \
       done \
    && echo "=== temporary cupsd ready ===" \
    \
    # ── Run installer: Y=install, N=skip printer GUI ──────────────────────────
    && INSTALL_DIR="$(dirname "$INSTALL_SH")" \
    && cd "$INSTALL_DIR" \
    && printf 'Y\nN\n' | bash install.sh \
    \
    # ── Stop temporary cupsd cleanly (#8) ────────────────────────────────────
    && pkill cupsd 2>/dev/null || true \
    && timeout 15 bash -c 'while pgrep -x cupsd >/dev/null 2>&1; do sleep 0.5; done' \
        || echo "WARNING: cupsd did not exit cleanly; continuing anyway" \
    \
    # ── Verify ───────────────────────────────────────────────────────────────
    && echo "=== Installed Canon PPDs ===" \
    && { find /usr/share/cups/model -name "*.ppd" 2>/dev/null | grep -i canon \
         || echo "WARNING: No Canon PPDs found in /usr/share/cups/model — check install.sh output above"; } \
    && echo "=== Canon CUPS filters/backends ==="  \
    && find /usr/lib/cups /usr/local/lib/cups \
         \( -name "cnpdfdrv*" -o -name "cnrdrv*" -o -name "cnjbig*" \
            -o -name "rastertoufr2*" \) 2>/dev/null || true \
    \
    # ── Allow root to manage printers without sudo (#13 – merged here) ────────
    && usermod -aG lpadmin root 2>/dev/null || true \
    \
    # ── Cleanup ───────────────────────────────────────────────────────────────
    && rm -rf /tmp/canon-driver /tmp/canon-driver.tar.gz \
    \
    # ── Configure CUPS for Docker / inter-container networking (#2, #13) ─────
    #    - Listen on all interfaces (not just loopback)
    #    - No TLS: plain HTTP for container-to-container printing
    #      (DefaultEncryption Never is safe on a private Docker network;
    #       add a TLS-terminating reverse proxy if external access is needed)
    #    - /           Allow all  — needed so any container can submit print jobs
    #    - /admin*     Require authentication (#2) — protects config changes
    && sed -i \
        -e 's|^Listen localhost:631|Port 631|g' \
        -e 's|^Listen 127\.0\.0\.1:631|Port 631|g' \
        /etc/cups/cupsd.conf \
    && cat >> /etc/cups/cupsd.conf << 'CUPSCFG'

# ── Docker / network settings (added by Dockerfile) ──────────────────────
DefaultEncryption Never
WebInterface Yes
ServerAlias *

# ── Log rotation (prevent unbounded growth in cups-logs volume) (#8) ─────
MaxLogSize 10m
PreserveJobHistory No
PreserveJobFiles No

<Location />
  Order allow,deny
  Allow all
</Location>

<Location /admin>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow all
</Location>

<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow all
</Location>

<Location /admin/log>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow all
</Location>
CUPSCFG

# ── 4. Entrypoint ─────────────────────────────────────────────────────────────
# --chmod=755 sets permissions at copy time — no separate RUN layer needed (#9)
COPY --chmod=755 docker-entrypoint.sh /docker-entrypoint.sh

EXPOSE 631

# Persist printer configuration across container restarts (same as ManuelKlaer)
VOLUME ["/etc/cups"]

# Healthcheck — canonical definition lives in docker-compose.yml (#15).
# This fallback is used when running the container directly without compose.
HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
  CMD curl -sf --max-time 8 http://localhost:631/ || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
