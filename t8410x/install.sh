#!/bin/sh
#
# Raptor Low-Latency Installer for Eufy T8410X (Thingino)
#
# Usage (on camera via SSH):
#   curl -sSL https://github.com/firtel-t/raptor/releases/latest/download/install.sh | sh
#
# Or with a specific version:
#   curl -sSL https://github.com/firtel-t/raptor/releases/download/build-XX/install.sh | sh
#

set -e

REPO="firtel-t/raptor"
ARCHIVE_NAME="raptor-t31-t8410x.tar.gz"
INSTALL_DIR="/tmp/raptor-install"
BIN_DIR="/usr/bin"
LIB_DIR="/usr/lib"
CONF_DIR="/etc"
INIT_DIR="/etc/init.d"

# ──────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────

info() { echo "[*] $1"; }
error() { echo "[!] $1" >&2; exit 1; }

check_prerequisites() {
    # Must be root
    [ "$(id -u)" = "0" ] || error "This script must be run as root"

    # Must be Thingino (check for Ingenic SoC)
    if [ ! -d /proc/jz ]; then
        error "This does not appear to be a Thingino/Ingenic device"
    fi

    # Check for curl or wget
    if command -v curl >/dev/null 2>&1; then
        DL="curl -sSL -o"
    elif command -v wget >/dev/null 2>&1; then
        DL="wget -q -O"
    else
        error "Neither curl nor wget found"
    fi
}

get_download_url() {
    # Try to get latest release URL
    RELEASE_URL="https://github.com/${REPO}/releases/latest/download/${ARCHIVE_NAME}"
    info "Download URL: ${RELEASE_URL}"
}

download_and_extract() {
    info "Downloading Raptor..."
    rm -rf "${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"

    $DL "${INSTALL_DIR}/${ARCHIVE_NAME}" "${RELEASE_URL}"

    if [ ! -f "${INSTALL_DIR}/${ARCHIVE_NAME}" ]; then
        error "Download failed"
    fi

    info "Extracting..."
    tar xzf "${INSTALL_DIR}/${ARCHIVE_NAME}" -C "${INSTALL_DIR}"
    rm -f "${INSTALL_DIR}/${ARCHIVE_NAME}"
}

stop_prudynt() {
    if pidof prudynt >/dev/null 2>&1; then
        info "Stopping prudynt..."
        ${INIT_DIR}/S95prudynt stop 2>/dev/null || killall prudynt 2>/dev/null || true
        sleep 1
    fi
}

install_binaries() {
    info "Installing binaries..."
    for bin in rvd rsd rad rhd rod ric rmr rmd rwc rwd rsp rsr raptorctl ringdump rac rverify; do
        if [ -f "${INSTALL_DIR}/${bin}" ]; then
            cp -f "${INSTALL_DIR}/${bin}" "${BIN_DIR}/${bin}"
            chmod +x "${BIN_DIR}/${bin}"
        fi
    done
}

install_libraries() {
    if [ -d "${INSTALL_DIR}/lib" ]; then
        info "Installing shared libraries..."
        cp -f "${INSTALL_DIR}/lib/"* "${LIB_DIR}/"
        ldconfig 2>/dev/null || true
    fi
}

install_config() {
    if [ -f "${INSTALL_DIR}/raptor.conf" ]; then
        if [ -f "${CONF_DIR}/raptor.conf" ]; then
            info "Backing up existing config to /etc/raptor.conf.bak"
            cp -f "${CONF_DIR}/raptor.conf" "${CONF_DIR}/raptor.conf.bak"
        fi
        info "Installing raptor.conf..."
        cp -f "${INSTALL_DIR}/raptor.conf" "${CONF_DIR}/raptor.conf"
    fi
}

generate_tls_cert() {
    # WebRTC (RWD) requires a TLS certificate for DTLS-SRTP.
    # Generate a self-signed cert if one doesn't exist.
    local CERT_DIR="/etc/raptor"
    local CERT_FILE="${CERT_DIR}/tls_cert.pem"
    local KEY_FILE="${CERT_DIR}/tls_key.pem"

    if [ -f "${CERT_FILE}" ] && [ -f "${KEY_FILE}" ]; then
        info "TLS certificate already exists, skipping generation"
        return
    fi

    info "Generating self-signed TLS certificate for WebRTC..."
    mkdir -p "${CERT_DIR}"

    # Check if openssl is available (it should be on Thingino)
    if command -v openssl >/dev/null 2>&1; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "${KEY_FILE}" -out "${CERT_FILE}" \
            -days 3650 -nodes -batch \
            -subj "/CN=raptor-cam" 2>/dev/null
    elif command -v certtool >/dev/null 2>&1; then
        # Alternative: GnuTLS certtool (sometimes available on embedded)
        certtool --generate-privkey --ecc --outfile "${KEY_FILE}" 2>/dev/null
        certtool --generate-self-signed --load-privkey "${KEY_FILE}" \
            --outfile "${CERT_FILE}" \
            --template /dev/null 2>/dev/null
    else
        # Last resort: use mbedtls gen_key if shipped with raptor
        # or just create placeholder - RWD may generate its own at runtime
        info "WARNING: No certificate tool found. WebRTC may not work."
        info "Install openssl or generate certs manually:"
        info "  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \\"
        info "    -keyout ${KEY_FILE} -out ${CERT_FILE} -days 3650 -nodes -batch"
        return
    fi

    chmod 600 "${KEY_FILE}"
    chmod 644 "${CERT_FILE}"
    info "TLS certificate generated at ${CERT_DIR}/"
}

install_init_script() {
    info "Installing init script..."
    cat > "${INIT_DIR}/S31raptor" << 'EOF'
#!/bin/sh
CONF="/etc/raptor.conf"

start() {
    echo "Starting Raptor Streaming System..."
    if [ -x /usr/bin/rvd ]; then
        start-stop-daemon -S -b -x /usr/bin/rvd -- -c "$CONF"
        sleep 1
    fi
    for daemon in rad rsd rwd rhd rod ric rmd; do
        if [ -x "/usr/bin/$daemon" ]; then
            start-stop-daemon -S -b -x "/usr/bin/$daemon" -- -c "$CONF"
        fi
    done
    echo "Raptor started."
}

stop() {
    echo "Stopping Raptor Streaming System..."
    for daemon in rmd ric rod rhd rwd rsd rad rvd; do
        pidof "$daemon" >/dev/null 2>&1 && killall "$daemon" 2>/dev/null
    done
    sleep 1
    echo "Raptor stopped."
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    *)       echo "Usage: $0 {start|stop|restart}"; exit 1 ;;
esac
EOF
    chmod +x "${INIT_DIR}/S31raptor"
}

disable_prudynt() {
    if [ -f "${INIT_DIR}/S95prudynt" ]; then
        info "Disabling prudynt autostart..."
        chmod -x "${INIT_DIR}/S95prudynt"
    fi
}

start_raptor() {
    info "Starting Raptor..."
    ${INIT_DIR}/S31raptor start
    sleep 2

    if pidof rvd >/dev/null 2>&1; then
        IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "<camera_ip>")
        echo ""
        echo "========================================="
        echo "  Raptor is running!"
        echo "========================================="
        echo ""
        echo "  WebRTC (lowest latency):"
        echo "    http://${IP}/webrtc"
        echo ""
        echo "  RTSP:"
        echo "    rtsp://${IP}/stream0"
        echo ""
        echo "  MJPEG:"
        echo "    http://${IP}/mjpeg"
        echo ""
        echo "========================================="
        echo ""
        echo "  To uninstall:"
        echo "    /etc/init.d/S31raptor stop"
        echo "    rm /etc/init.d/S31raptor"
        echo "    chmod +x /etc/init.d/S95prudynt"
        echo "    /etc/init.d/S95prudynt start"
        echo ""
    else
        echo ""
        echo "[!] WARNING: rvd does not appear to be running."
        echo "    Check logs: logread | grep -i raptor"
        echo ""
    fi
}

cleanup() {
    rm -rf "${INSTALL_DIR}"
}

# ──────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────

echo ""
echo "  Raptor Low-Latency Installer"
echo "  for Eufy T8410X (Thingino)"
echo ""

check_prerequisites
get_download_url
download_and_extract
stop_prudynt
install_binaries
install_libraries
install_config
generate_tls_cert
install_init_script
disable_prudynt
start_raptor
cleanup

info "Installation complete."
