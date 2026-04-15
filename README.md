# CUPS + Canon LBP7110Cw Docker Setup

A self-contained Docker CUPS print server for the **Canon LBP7110Cw** colour
laser, using Canon's official **UFRII LT driver v5.00** installed via the
driver's own **`install.sh`** at image build time.

Based on **[ManuelKlaer/docker-cups-canon](https://github.com/ManuelKlaer/docker-cups-canon)**
(itself forked from ydkn → olbat/cupsd), extended with the Canon UFRII LT
driver and automatic printer registration at container startup.

---

## Supported Architectures

> [!IMPORTANT]
> This image is **AMD64 only** (Standard PC).
>
> The Canon UFRII LT driver is a proprietary binary provided by Canon in `x86_64` (amd64) and `i386` formats. It does **not** support ARMv8 (arm64), so it will not run on a Raspberry Pi or Apple Silicon (M1/M2/M3) without x86 emulation.

---

## Using the Pre-built Image (Packages)

Instead of downloading the driver and building the image locally, you can use the pre-built image from the **GitHub Container Registry**.

**Benefits:**
- **No Build Required**: Skip Step 1 and Step 3 (the driver is already installed).
- **Faster Setup**: Pulling the image is much faster than running the Canon installer at build time.
- **Always Ready**: Perfect for CI/CD or quick deployments.

### Pull the image

```bash
docker pull ghcr.io/zr0aces/cups-canon-lbp7110cw:latest
```

### Update your `docker-compose.yml`

Simply replace the `build: .` line with the `image` name:

```yaml
services:
  cups:
    image: ghcr.io/zr0aces/cups-canon-lbp7110cw:latest
    container_name: cups-canon-lbp7110cw
    # ... rest of your environment/volumes ...
```

---

## File overview

| File | Purpose |
|---|---|
| `download-driver.sh` | **Run first.** Downloads and SHA256-verifies Canon driver tarball |
| `Dockerfile` | Builds the image; runs `install.sh` at build time |
| `docker-entrypoint.sh` | Starts CUPS, sets admin password, registers printer |
| `docker-compose.yml` | Orchestrates the server (+ optional example client via `--profile example`) |
| `.env-example` | Template for required secrets — copy to `.env` and edit |
| `README.md` | This file |

---

## Quick start

### Step 1 — Download the Canon driver (once)

The driver tarball (~21 MB) will be downloaded into a dedicated `download/`
folder. Docker copies it from there during the build process. The script also
verifies the SHA256 checksum to ensure integrity.

```bash
chmod +x download-driver.sh
./download-driver.sh
```

Expected output:

```
✓ File size    : 21942231 bytes
✓ gzip test    : OK
✓ SHA256       : 46888140016bc1096694a0fd6fd3f6ad393970b8153756373a382dc82390f259
✓ install.sh   : found inside tarball

Top-level contents:
linux-UFRIILT-drv-v500-uken/
linux-UFRIILT-drv-v500-uken/install.sh
linux-UFRIILT-drv-v500-uken/64-bit_Driver/
linux-UFRIILT-drv-v500-uken/32-bit_Driver/
linux-UFRIILT-drv-v500-uken/Documents/
...

Ready to build!
```

> **No curl/wget?** Manually download the file from:
> `https://gdlp01.c-wss.com/gds/0/0100005950/10/linux-UFRIILT-drv-v500-uken-18.tar.gz`
> and place it in the **`download/`** folder.

---

### Step 2 — Configure your environment

Copy the example file and edit it with your printer's IP and a secure password:

```bash
cp .env-example .env
nano .env
```

```bash
# .env
PRINTER_IP=192.168.1.100    # ← your printer's actual IP
ADMIN_PASSWORD=changeme      # ← change to a strong password
```

**Finding your printer's IP:** Press the WiFi button on the printer to print a
network status page, or check your router's DHCP leases table.

> [!IMPORTANT]
> Never commit your `.env` file to version control — it contains your admin
> password. The `.gitignore` already excludes it.

---

### Step 3 — Build and start

```bash
docker compose up -d --build
```

**What to look for in the build log** (confirms `install.sh` ran correctly):

```
=== install.sh: /tmp/canon-driver/linux-UFRIILT-drv-v500-uken/install.sh ===
=== temporary cupsd ready ===
Installing cnrdrvcups-common ... done
Installing cnrdrvcups-ufr2lt-uk ... done
Installation is complete. Do you want to register the printer now? [Y/n]: N
=== Installed Canon PPDs ===
/usr/share/cups/model/CNRCUPSLBP7110CZNK.ppd
```

> The `N` to "register printer now?" is intentional. The printer is registered
> at container startup by `docker-entrypoint.sh` using `PRINTER_IP`, so you
> can change the printer's IP without rebuilding the image.

---

### Step 4 — Verify

```bash
# Container status
docker compose ps

# Printer queue (should show socket://YOUR_IP:9100)
docker exec cups-canon-lbp7110cw lpstat -v

# CUPS Web UI — open in browser
open http://localhost:631
```

---

### Step 5 — Healthcheck and Monitoring

The `cups` container includes a built-in healthcheck. You can monitor its status
with:

```bash
docker compose ps
```

The status will change from `(health: starting)` to `(healthy)` once the CUPS
daemon is up and the printer has been registered. This status is used to
coordinate dependent services like the `print-client` example.

The entrypoint also monitors and **automatically restarts** `cupsd`,
`avahi-daemon`, and `dbus-daemon` if any of them exit unexpectedly.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ADMIN_PASSWORD` | `admin` | CUPS Web UI + admin password — **set in `.env`** |
| `PRINTER_NAME` | `Canon_LBP7110Cw` | CUPS queue name |
| `PRINTER_IP` | `192.168.1.100` | **Set in `.env`** — your printer's actual IP |
| `PRINTER_PPD` | `CNRCUPSLBP7110CZNK.ppd` | PPD installed by Canon driver |
| `CUPS_LOGLEVEL` | `warn` | `error` / `warn` / `info` / `debug` |
| `CUPS_ENV_DEBUG` | `no` | `yes` = full `bash -x` trace in logs |

No rebuild is required when changing these — they are applied at container
startup.

> [!IMPORTANT]
> `ADMIN_PASSWORD` and `PRINTER_IP` should be set in your `.env` file, not
> hardcoded in `docker-compose.yml`. This keeps secrets out of version control.

---

## Printing from another container

Any container on `print-network` can send jobs without installing a driver.

### Option A — `lp` via cups-client

```bash
# In your other container:
apt-get install -y cups-client

# Point it at the CUPS server
echo 'ServerName cups' > /etc/cups/client.conf

# Print a PDF
lp -d Canon_LBP7110Cw /path/to/file.pdf

# Print plain text
echo "Hello Printer" | lp -d Canon_LBP7110Cw
```

### Option B — IPP URI (built into many apps)

```
ipp://cups:631/printers/Canon_LBP7110Cw
```

### Option C — Environment variable

```bash
export CUPS_SERVER=cups
lp -d Canon_LBP7110Cw myfile.pdf
```

### Connecting an existing compose service to the print network

Add this to your app's `docker-compose.yml`:

```yaml
services:
  myapp:
    # ... your existing config ...
    networks:
      - cups-canon_print-network   # join the CUPS network

networks:
  cups-canon_print-network:
    external: true                 # references the already-running network
```

### Running the bundled example print client

The root `docker-compose.yml` includes an optional print-client that installs
`cups-client` and sends a test page. It is disabled by default and only runs
when you pass `--profile example`:

```bash
docker compose --profile example up
```

---

## CUPS Web UI

| URL | Purpose |
|---|---|
| `http://localhost:631/` | Printer list |
| `http://localhost:631/admin` | Administration (requires login) |
| `http://localhost:631/jobs` | Job queue |
| `http://localhost:631/printers/Canon_LBP7110Cw` | Printer status & test page |

Login: **admin** / value of `ADMIN_PASSWORD`.

> [!NOTE]
> The admin endpoints (`/admin`, `/admin/conf`, `/admin/log`) require
> authentication. The printer submission endpoint (`/`) is open to all
> containers on `print-network`, which is the correct behaviour for a shared
> print server.

---

## Driver details

| Item | Value |
|---|---|
| Tarball | `linux-UFRIILT-drv-v500-uken-18.tar.gz` |
| SHA256 | `46888140016bc1096694a0fd6fd3f6ad393970b8153756373a382dc82390f259` |
| Installer | `install.sh` (Canon's official script, run at build time) |
| Packages | `cnrdrvcups-common` + `cnrdrvcups-ufr2lt-uk` |
| PPD | `CNRCUPSLBP7110CZNK.ppd` |
| Protocol | UFRII LT over raw TCP port 9100 |

---

## Troubleshooting

```bash
# ── Logs ──────────────────────────────────────────────────────────────────────
docker logs cups-canon-lbp7110cw
docker exec cups-canon-lbp7110cw tail -f /var/log/cups/error_log

# ── Enable debug logging (no rebuild needed) ──────────────────────────────────
# In .env set:  CUPS_ENV_DEBUG=yes  and  CUPS_LOGLEVEL=debug
docker compose up -d

# ── Printer paused / stopped ──────────────────────────────────────────────────
docker exec cups-canon-lbp7110cw cupsenable Canon_LBP7110Cw
docker exec cups-canon-lbp7110cw cupsaccept Canon_LBP7110Cw

# ── Re-register with a different IP (no rebuild) ──────────────────────────────
docker exec cups-canon-lbp7110cw lpadmin -x Canon_LBP7110Cw
docker exec cups-canon-lbp7110cw lpadmin \
    -p Canon_LBP7110Cw -E \
    -v socket://192.168.1.50:9100 \
    -P /usr/share/cups/model/CNRCUPSLBP7110CZNK.ppd \
    -o printer-is-shared=true

# ── List installed Canon PPDs ─────────────────────────────────────────────────
docker exec cups-canon-lbp7110cw \
    find /usr/share/cups/model -name "*.ppd" | grep -i canon

# ── Test raw TCP connectivity to the printer ──────────────────────────────────
docker exec cups-canon-lbp7110cw \
    bash -c "echo '' | timeout 3 curl -v telnet://192.168.1.100:9100 2>&1 | head -10"

# ── Inspect the print queue ───────────────────────────────────────────────────
docker exec cups-canon-lbp7110cw lpstat -o
docker exec cups-canon-lbp7110cw lpq -P Canon_LBP7110Cw
```

---

## Production checklist

- [x] Set `ADMIN_PASSWORD` in `.env` (not in `docker-compose.yml`)
- [ ] Change `ADMIN_PASSWORD` from the default — use a strong password
- [x] Admin endpoints (`/admin*`) require authentication
- [ ] Assign a **static IP** to the printer (DHCP reservation on your router)
- [ ] Restrict port 631 to your LAN only (firewall / Docker network policy)
- [ ] Pin the base image to a digest: `FROM ubuntu:22.04@sha256:<digest>`
      Get the current digest: `docker pull ubuntu:22.04 && docker inspect ubuntu:22.04 --format '{{index .RepoDigests 0}}'`
- [ ] Set up log rotation for the `cups-logs` volume
