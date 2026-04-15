#!/usr/bin/env bash
# =============================================================================
# docker-entrypoint.sh  v1.1.0
# Based on ManuelKlaer/docker-cups-canon (which forks ydkn / olbat cupsd).
# Extended to auto-register the Canon LBP7110Cw via its UFRII LT PPD.
#
# Environment variables
#   ADMIN_PASSWORD   CUPS admin password          (default: admin)
#   CUPS_LOGLEVEL    CUPS log level               (default: warn)
#   CUPS_ENV_DEBUG   set 'yes' for bash -x trace  (default: no)
#   PRINTER_NAME     CUPS queue name              (default: Canon_LBP7110Cw)
#   PRINTER_IP       Printer IP address           (default: 192.168.1.100)
#   PRINTER_PPD      PPD filename from driver     (default: CNRCUPSLBP7110CZNK.ppd)
# =============================================================================

# NOTE: Do NOT add -e to the set flags at the top level — the monitoring loop
# uses pgrep which returns exit 1 when no process is found, and we want to
# handle that ourselves rather than abort the whole script. (#18)
set -uo pipefail   # intentionally no -e: pgrep exit-1 must not kill the script

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[CUPS]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR ]${NC} $*" >&2; }

# ── Read environment (mirrors ManuelKlaer variable names) ─────────────────────
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
CUPS_LOGLEVEL="${CUPS_LOGLEVEL:-warn}"
CUPS_ENV_DEBUG="${CUPS_ENV_DEBUG:-no}"
PRINTER_NAME="${PRINTER_NAME:-Canon_LBP7110Cw}"
PRINTER_IP="${PRINTER_IP:-192.168.1.100}"
PRINTER_PPD="${PRINTER_PPD:-CNRCUPSLBP7110CZNK.ppd}"

if [ "$CUPS_ENV_DEBUG" = "yes" ]; then
    set -x
    CUPS_LOGLEVEL="debug"
fi

log "======================================================="
log "  CUPS + Canon LBP7110Cw  (UFRII LT driver v5.00)"
log "======================================================="
log "  PRINTER_NAME  : $PRINTER_NAME"
log "  PRINTER_IP    : $PRINTER_IP"
log "  PRINTER_PPD   : $PRINTER_PPD"
log "  CUPS_LOGLEVEL : $CUPS_LOGLEVEL"
log "======================================================="

# ── 1. Admin user  (ManuelKlaer pattern: account named 'admin') ───────────────
# Use a regular (non-system) account so chpasswd works reliably.
log "Configuring admin user..."
if ! id admin &>/dev/null 2>&1; then
    useradd --create-home --shell /usr/sbin/nologin \
            --groups lpadmin,sudo admin
    ok "User 'admin' created."
fi
# Validate password: chpasswd parses 'user:password' — a colon in the value
# is treated as a field separator and silently sets the wrong password. (#6)
if [[ "${ADMIN_PASSWORD}" == *:* ]]; then
    err "ADMIN_PASSWORD must not contain a colon (:). Update your .env file."
    exit 1
fi
printf 'admin:%s\n' "${ADMIN_PASSWORD}" | chpasswd
ok "Admin password configured."

# ── 2. Required directories ───────────────────────────────────────────────────
mkdir -p /var/spool/cups/tmp /var/log/cups /run/cups
chown root:lp /var/spool/cups 2>/dev/null || true
chmod 710     /var/spool/cups 2>/dev/null || true

# ── 3. Apply runtime log level to cupsd.conf ──────────────────────────────────
if grep -q "^LogLevel" /etc/cups/cupsd.conf 2>/dev/null; then
    sed -i "s|^LogLevel.*|LogLevel ${CUPS_LOGLEVEL}|" /etc/cups/cupsd.conf
else
    echo "LogLevel ${CUPS_LOGLEVEL}" >> /etc/cups/cupsd.conf
fi

# ── 4. DBus (required by avahi-daemon and some CUPS backends) ─────────────────
mkdir -p /run/dbus
if ! pgrep -x dbus-daemon > /dev/null 2>&1; then
    dbus-daemon --system --fork 2>/dev/null \
        && ok "dbus-daemon started." \
        || warn "dbus-daemon failed to start (non-fatal)."
    sleep 1
fi

# ── 5. Avahi – mDNS/Bonjour so the printer appears on the LAN ────────────────
if command -v avahi-daemon &>/dev/null; then
    if ! pgrep -x avahi-daemon > /dev/null 2>&1; then
        avahi-daemon --daemonize --no-chroot 2>/dev/null \
            && ok "avahi-daemon started." \
            || warn "avahi-daemon failed (non-fatal; usually needs host network)."
    fi
fi

# ── 6. Start cupsd ────────────────────────────────────────────────────────────
log "Starting cupsd..."
/usr/sbin/cupsd

# Poll until CUPS is answering on port 631 (up to 30 s) (#10 fixed timing)
log "Waiting for CUPS..."
CUPS_READY=0
for i in $(seq 0 29); do
    sleep 1
    if curl -sf --max-time 3 http://localhost:631/ >/dev/null 2>&1; then
        ok "CUPS is ready (after $((i + 1))s)."
        CUPS_READY=1
        break
    fi
done

if [ "$CUPS_READY" -eq 0 ]; then
    err "CUPS did not start within 30 seconds."
    err "Check /var/log/cups/error_log for details."
    exit 1
fi

# ── 7. Locate the Canon PPD installed by install.sh ──────────────────────────
find_ppd() {
    local candidates=(
        "/usr/share/cups/model/${PRINTER_PPD}"
        "/usr/share/cups/model/Canon/${PRINTER_PPD}"
        "/usr/local/share/cups/model/${PRINTER_PPD}"
        "/usr/share/ppd/canon/${PRINTER_PPD}"
    )
    local p
    for p in "${candidates[@]}"; do
        [ -f "$p" ] && echo "$p" && return 0
    done
    # Scoped fallback — only search known PPD locations, limited depth (#14)
    find /usr/share/cups /usr/local/share/cups /usr/share/ppd \
        -maxdepth 5 -name "${PRINTER_PPD}" 2>/dev/null | head -1
}

PPD_PATH="$(find_ppd)"
if [ -n "$PPD_PATH" ]; then
    ok "PPD found: $PPD_PATH"
else
    warn "PPD '${PRINTER_PPD}' not found — will register in raw mode."
    warn "Verify the driver installed correctly during docker build."
fi

# ── 8. Register the Canon LBP7110Cw in CUPS ──────────────────────────────────
PRINTER_URI="socket://${PRINTER_IP}:9100"

# Idempotent: remove any stale queue first (#11 — log the output)
if lpstat -v 2>/dev/null | grep -q "device for ${PRINTER_NAME}:"; then
    log "Removing existing queue '${PRINTER_NAME}'..."
    lpadmin -x "${PRINTER_NAME}" 2>&1 | while IFS= read -r line; do log "$line"; done || true
fi

log "Registering '${PRINTER_NAME}' → ${PRINTER_URI}"

if [ -n "$PPD_PATH" ]; then
    lpadmin \
        -p "${PRINTER_NAME}" \
        -E \
        -v "${PRINTER_URI}" \
        -P "${PPD_PATH}" \
        -D "Canon LBP7110Cw Color Laser" \
        -L "Network Printer" \
        -o printer-is-shared=true \
    && ok "Printer registered with Canon PPD."
else
    # Raw fallback — still usable for PostScript directly
    lpadmin \
        -p "${PRINTER_NAME}" \
        -E \
        -v "${PRINTER_URI}" \
        -m raw \
        -D "Canon LBP7110Cw (raw – no PPD)" \
        -L "Network Printer" \
        -o printer-is-shared=true \
    && warn "Printer registered in raw mode (no PPD)."
fi

cupsenable  "${PRINTER_NAME}"
cupsaccept  "${PRINTER_NAME}"
lpoptions -d "${PRINTER_NAME}"
ok "'${PRINTER_NAME}' is the default queue."

# ── 9. Print a startup summary (#19 — password masked) ───────────────────────
PW_STARS="$(printf '%*s' "${#ADMIN_PASSWORD}" '' | tr ' ' '*')"
log ""
log "  ┌─ CUPS ready ──────────────────────────────────────────┐"
log "  │  Web UI   : http://<host-ip>:631                      │"
log "  │  Login    : admin / ${PW_STARS}                            │"
log "  │  IPP URI  : ipp://<host-ip>:631/printers/${PRINTER_NAME} │"
log "  ├─ Printing from another container ──────────────────── │"
log "  │  echo 'ServerName cups' > /etc/cups/client.conf       │"
log "  │  lp -d ${PRINTER_NAME} myfile.pdf              │"
log "  └───────────────────────────────────────────────────────┘"
log ""
lpstat -v 2>/dev/null || true
log ""

# ── Graceful shutdown handler (#2) ───────────────────────────────────────────
# Invoked by the trap below when Docker sends SIGTERM/SIGINT to PID 1.
# Without this, Docker waits the stop grace period then SIGKILL-s cupsd
# mid-job, risking spool file corruption and lost print jobs.
_shutdown() {
    log "Shutdown signal received — stopping services gracefully..."
    pkill -TERM cupsd        2>/dev/null || true
    pkill -TERM avahi-daemon 2>/dev/null || true
    pkill -TERM dbus-daemon  2>/dev/null || true
    # Wait up to 10 s for cupsd to flush and exit cleanly
    timeout 10 bash -c 'while pgrep -x cupsd >/dev/null 2>&1; do sleep 0.5; done' || true
    ok "Shutdown complete."
    exit 0
}
trap _shutdown SIGTERM SIGINT SIGQUIT

# ── 10. Keep the container alive; restart services if they crash ──────────────
log "Container running. Monitoring services every 10 s..."
while true; do
    # Run sleep in the background and wait — this allows SIGTERM delivered to
    # PID 1 to interrupt the wait and invoke the trap handler above. (#2)
    sleep 10 &
    wait $!

    # ── cupsd ──────────────────────────────────────────────────────────────
    if ! pgrep -x cupsd > /dev/null 2>&1; then
        warn "cupsd is not running — restarting..."
        /usr/sbin/cupsd \
            && ok  "cupsd restarted." \
            || err "cupsd failed to restart!"
        sleep 5
    fi

    # ── avahi-daemon (non-fatal; may not be available in all environments) ──
    if command -v avahi-daemon &>/dev/null; then
        if ! pgrep -x avahi-daemon > /dev/null 2>&1; then
            warn "avahi-daemon is not running — restarting..."
            avahi-daemon --daemonize --no-chroot 2>/dev/null \
                && ok  "avahi-daemon restarted." \
                || warn "avahi-daemon failed to restart (non-fatal)."
        fi
    fi

    # ── dbus-daemon ────────────────────────────────────────────────────────
    if ! pgrep -x dbus-daemon > /dev/null 2>&1; then
        warn "dbus-daemon is not running — restarting..."
        dbus-daemon --system --fork 2>/dev/null \
            && ok  "dbus-daemon restarted." \
            || warn "dbus-daemon failed to restart (non-fatal)."
    fi
done
