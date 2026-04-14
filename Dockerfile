FROM ubuntu:22.04

LABEL maintainer="cups-canon-lbp7110cw"
LABEL description="CUPS print server for Canon LBP7110Cw – based on ManuelKlaer/docker-cups-canon, driver installed via Canon's official install.sh"

ENV DEBIAN_FRONTEND=noninteractive

# ── Runtime defaults (all overridable via -e / environment: in compose) ────────
ENV ADMIN_PASSWORD=admin \
    CUPS_LOGLEVEL=warn \
    CUPS_ENV_DEBUG=no \
    PRINTER_NAME=Canon_LBP7110Cw \
    PRINTER_IP=192.168.1.100 \
    PRINTER_PPD=CNRCUPSLBP7110CZNK.ppd

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
COPY download/linux-UFRIILT-drv-v500-uken-18.tar.gz /tmp/canon-driver.tar.gz

# ── 3. Extract tarball and run Canon's official install.sh non-interactively ──
#
#    install.sh asks exactly two Y/N questions:
#      Q1 "proceed with installation? [Y/n]" → Y  (install the packages)
#      Q2 "register printer now?      [Y/n]" → N  (skip – done at runtime
#                                                   by docker-entrypoint.sh
#                                                   so PRINTER_IP is flexible)
#
#    install.sh also requires cupsd to be running before it executes,
#    because it calls  `service cups restart`  after dpkg to activate filters.
#    We start cupsd temporarily, run the installer, then stop cupsd cleanly.
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
    # ── Stop temporary cupsd ─────────────────────────────────────────────────
    && pkill cupsd 2>/dev/null || true \
    && sleep 2 \
    \
    # ── Verify ───────────────────────────────────────────────────────────────
    && echo "=== Installed Canon PPDs ===" \
    && find /usr/share/cups/model -name "*.ppd" 2>/dev/null | grep -i canon \
    && echo "=== Canon CUPS filters/backends ===" \
    && find /usr/lib/cups /usr/local/lib/cups \
         \( -name "cnpdfdrv*" -o -name "cnrdrv*" -o -name "cnjbig*" \
            -o -name "rastertoufr2*" \) 2>/dev/null || true \
    \
    # ── Cleanup ───────────────────────────────────────────────────────────────
    && rm -rf /tmp/canon-driver /tmp/canon-driver.tar.gz

# ── 4. Configure CUPS for Docker / inter-container networking ─────────────────
#    Pattern from ManuelKlaer / olbat / ydkn:
#      - Listen on all interfaces (not just loopback)
#      - No TLS encryption so plain HTTP from other containers works
#      - Allow connections from all sources (Docker bridge network)
RUN set -eux \
    && sed -i \
        -e 's|^Listen localhost:631|Port 631|g' \
        -e 's|^Listen 127\.0\.0\.1:631|Port 631|g' \
        /etc/cups/cupsd.conf \
    && cat >> /etc/cups/cupsd.conf << 'CUPSCFG'

# ── Docker / network settings (added by Dockerfile) ──────────────────────
DefaultEncryption Never
WebInterface Yes
ServerAlias *

<Location />
  Order allow,deny
  Allow all
</Location>

<Location /admin>
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

# ── 5. Allow root to manage printers without sudo ─────────────────────────────
RUN usermod -aG lpadmin root 2>/dev/null || true

# ── 6. Entrypoint ─────────────────────────────────────────────────────────────
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 631

# Persist printer configuration across container restarts (same as ManuelKlaer)
VOLUME ["/etc/cups"]

# Healthcheck to monitor CUPS status
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:631/ || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
