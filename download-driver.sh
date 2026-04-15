#!/usr/bin/env bash
# =============================================================================
# download-driver.sh  v1.0.1
# Downloads the Canon UFRII LT v5.00 Linux driver tarball from Canon's CDN
# into the Docker build context (same folder as the Dockerfile).
#
# Run this ONCE before:  docker compose up -d --build
#
# The tarball is ~21 MB.  Re-running is safe — it skips the download if the
# file is already present and passes all integrity checks.
# =============================================================================
set -euo pipefail

DRIVER_URL="https://gdlp01.c-wss.com/gds/0/0100005950/10/linux-UFRIILT-drv-v500-uken-18.tar.gz"
DRIVER_FILE="linux-UFRIILT-drv-v500-uken-18.tar.gz"
MIN_BYTES=20000000   # reject anything smaller than ~20 MB

# Known SHA256 of the authentic Canon UFRII LT v5.00 driver (#5)
# Verified from Canon's official CDN: gdlp01.c-wss.com
DRIVER_SHA256="46888140016bc1096694a0fd6fd3f6ad393970b8153756373a382dc82390f259"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${SCRIPT_DIR}/download"
DEST="${DOWNLOAD_DIR}/${DRIVER_FILE}"

# Ensure download directory exists
mkdir -p "$DOWNLOAD_DIR"

echo "══════════════════════════════════════════════════════"
echo "  Canon UFRII LT v5.00 driver — download"
echo "══════════════════════════════════════════════════════"
echo "  URL  → ${DRIVER_URL}"
echo "  Dest → ${DEST}"
echo ""

# ── Already downloaded and valid? ─────────────────────────────────────────────
if [ -f "$DEST" ]; then
    SIZE=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null || echo 0)
    if [ "$SIZE" -ge "$MIN_BYTES" ] && gzip -t "$DEST" 2>/dev/null; then
        # Verify SHA256 of cached file (#5)
        CACHED_SHA256=$(sha256sum "$DEST" | awk '{print $1}')
        if [ "$CACHED_SHA256" = "$DRIVER_SHA256" ]; then
            echo "✓ Driver already present, valid, and SHA256-verified (${SIZE} bytes)."
            echo "  Skipping all steps."
            exit 0
        else
            echo "! Existing file failed SHA256 check — re-downloading."
            rm -f "$DEST"
        fi
    else
        echo "! Existing file is missing, corrupt, or incomplete (${SIZE} bytes)."
        echo "  Deleting and re-downloading..."
        rm -f "$DEST"
    fi
fi

# ── Download ──────────────────────────────────────────────────────────────────
echo "Downloading (~21 MB)..."
if command -v curl &>/dev/null; then
    curl -L --retry 3 --retry-delay 5 --progress-bar \
         -o "$DEST" "$DRIVER_URL"
elif command -v wget &>/dev/null; then
    wget --tries=3 --waitretry=5 --show-progress \
         -O "$DEST" "$DRIVER_URL"
else
    echo "ERROR: neither curl nor wget found. Please install one." >&2
    exit 1
fi

# ── Integrity checks ──────────────────────────────────────────────────────────
echo ""
echo "Verifying download..."

SIZE=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null || echo 0)
if [ "$SIZE" -lt "$MIN_BYTES" ]; then
    echo "ERROR: File is too small (${SIZE} bytes). Download probably failed." >&2
    rm -f "$DEST"
    exit 1
fi

if ! gzip -t "$DEST" 2>/dev/null; then
    echo "ERROR: File is not a valid gzip archive. Download may be truncated." >&2
    rm -f "$DEST"
    exit 1
fi

# ── SHA256 checksum verification (#5) ────────────────────────────────────────
echo "Verifying SHA256 checksum..."
ACTUAL_SHA256=$(sha256sum "$DEST" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$DRIVER_SHA256" ]; then
    echo "ERROR: SHA256 mismatch!" >&2
    echo "  Expected: ${DRIVER_SHA256}" >&2
    echo "  Actual:   ${ACTUAL_SHA256}" >&2
    echo "  The download may be corrupt or tampered. Deleting." >&2
    rm -f "$DEST"
    exit 1
fi

echo "✓ File size    : ${SIZE} bytes"
echo "✓ gzip test    : OK"
echo "✓ SHA256       : ${ACTUAL_SHA256}"

# ── Confirm install.sh is inside the tarball ──────────────────────────────────
if tar -tzf "$DEST" 2>/dev/null | grep -q "install\.sh"; then
    echo "✓ install.sh   : found inside tarball"
else
    echo "WARNING: install.sh not found inside tarball." >&2
    echo "         The Dockerfile RUN step will fail at build time."
fi

# ── Preview contents ──────────────────────────────────────────────────────────
echo ""
echo "Top-level contents:"
tar -tzf "$DEST" | head -30
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Ready to build!"
echo ""
echo "  Next step:"
echo "    cp .env-example .env && nano .env   # set PRINTER_IP and ADMIN_PASSWORD"
echo "    docker compose up -d --build"
echo "══════════════════════════════════════════════════════"
