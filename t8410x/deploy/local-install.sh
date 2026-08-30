#!/bin/sh
#
# local-install.sh - Install Raptor locally on Thingino
#
# Run this directly on the camera after copying the extracted
# release package to it (e.g. via scp or SD card).
#
# Usage (on camera):
#   cd /path/to/extracted/package
#   sh local-install.sh
#

set -e

# カレントディレクトリをソースディレクトリとする
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_DIR="/usr/bin"
REMOTE_LIB="/usr/lib"
REMOTE_CONF="/etc"
CERT_DIR="/etc/raptor"

echo "=== Local Raptor Installation on T8410X ==="
echo ""

# 0. 前提チェック
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: must run as root"
    exit 1
fi

# 1. 既存のストリーマー（prudynt）の停止
echo "[1/6] Stopping prudynt..."
if pidof prudynt >/dev/null 2>&1; then
    /etc/init.d/S95prudynt stop 2>/dev/null || killall prudynt 2>/dev/null || true
    sleep 1
    echo "  prudynt stopped"
else
    echo "  prudynt not running"
fi

# 2. バイナリの配置
echo "[2/6] Installing Raptor binaries to ${REMOTE_DIR}..."
BINARIES="rvd rsd rad rhd rod ric rmr rmd rwc rwd rsp rsr raptorctl ringdump rac"
for bin in $BINARIES; do
    if [ -f "${SCRIPT_DIR}/${bin}" ]; then
        cp "${SCRIPT_DIR}/${bin}" "${REMOTE_DIR}/${bin}"
        chmod +x "${REMOTE_DIR}/${bin}"
    fi
done
echo "  Binaries installed"

# 3. 共有ライブラリの配置（存在する場合）
if [ -d "${SCRIPT_DIR}/lib" ]; then
    echo "[3/6] Installing shared libraries to ${REMOTE_LIB}..."
    cp -f "${SCRIPT_DIR}/lib/"* "${REMOTE_LIB}/"
    ldconfig 2>/dev/null || true
    echo "  Libraries installed"
else
    echo "[3/6] No shared libraries to install"
fi

# 4. 設定ファイルの配置
echo "[4/6] Installing raptor.conf..."
if [ -f "${SCRIPT_DIR}/raptor.conf" ]; then
    if [ -f "${REMOTE_CONF}/raptor.conf" ]; then
        cp -f "${REMOTE_CONF}/raptor.conf" "${REMOTE_CONF}/raptor.conf.bak"
        echo "  Backed up existing config to raptor.conf.bak"
    fi
    cp "${SCRIPT_DIR}/raptor.conf" "${REMOTE_CONF}/raptor.conf"
    echo "  Config installed"
else
    echo "  WARNING: raptor.conf not found"
fi

# 5. TLS証明書の配置（WebRTC用）
echo "[5/6] Installing TLS certificate for WebRTC..."
mkdir -p "${CERT_DIR}"
if [ -f "${CERT_DIR}/tls_cert.pem" ] && [ -f "${CERT_DIR}/tls_key.pem" ]; then
    echo "  TLS certificate already exists, skipping"
elif [ -d "${SCRIPT_DIR}/certs" ]; then
    cp -f "${SCRIPT_DIR}/certs/tls_cert.pem" "${CERT_DIR}/tls_cert.pem"
    cp -f "${SCRIPT_DIR}/certs/tls_key.pem" "${CERT_DIR}/tls_key.pem"
    chmod 600 "${CERT_DIR}/tls_key.pem"
    chmod 644 "${CERT_DIR}/tls_cert.pem"
    echo "  TLS certificate installed"
else
    echo "  WARNING: No certs/ directory found. WebRTC may not work."
fi

# 6. 初期化スクリプトの設定と起動
echo "[6/6] Installing init script and launching Raptor..."
if [ -f "${SCRIPT_DIR}/start-raptor.sh" ]; then
    cp "${SCRIPT_DIR}/start-raptor.sh" /etc/init.d/S31raptor
    chmod +x /etc/init.d/S31raptor
fi

# prudyntの自動起動無効化
if [ -f /etc/init.d/S95prudynt ]; then
    chmod -x /etc/init.d/S95prudynt
    echo "  Disabled prudynt autostart"
fi

# Raptorの起動
if [ -x /etc/init.d/S31raptor ]; then
    /etc/init.d/S31raptor start
else
    # 万が一スクリプトがない場合は直接rvdを起動
    export LD_LIBRARY_PATH="${REMOTE_LIB}"
    /usr/bin/rvd -c "${REMOTE_CONF}/raptor.conf" &
    sleep 1
    for daemon in rad rsd rwd rhd rod ric rmd; do
        [ -x "${REMOTE_DIR}/${daemon}" ] && "${REMOTE_DIR}/${daemon}" -c "${REMOTE_CONF}/raptor.conf" &
    done
fi

sleep 2

# 稼働確認
if pidof rvd >/dev/null 2>&1; then
    IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}' | head -1)
    [ -z "$IP" ] && IP="<camera_ip>"
    echo ""
    echo "=== Raptor is running successfully! ==="
    echo ""
    echo "  WebRTC (lowest latency): http://${IP}/webrtc"
    echo "  RTSP:                    rtsp://${IP}/stream0"
    echo "  MJPEG:                   http://${IP}/mjpeg"
    echo ""
    echo "  Uninstall:"
    echo "    /etc/init.d/S31raptor stop"
    echo "    rm /etc/init.d/S31raptor"
    echo "    chmod +x /etc/init.d/S95prudynt"
    echo "    /etc/init.d/S95prudynt start"
    echo ""
else
    echo ""
    echo "WARNING: rvd does not appear to be running. Check 'logread'."
fi

echo "Done."
