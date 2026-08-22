#!/bin/sh
#
# deploy.sh - Deploy Raptor to Eufy T8410X (Thingino)
#
# Usage: ./deploy.sh <camera_ip> [user]
#   camera_ip: IP address of the camera
#   user: SSH user (default: root)
#
# Prerequisites:
#   - Camera is running Thingino firmware
#   - SSH access is enabled
#   - This script is run from the extracted release package directory

set -e

CAMERA_IP="${1:?Usage: $0 <camera_ip> [user]}"
CAMERA_USER="${2:-root}"
REMOTE_DIR="/usr/bin"
REMOTE_LIB="/usr/lib"
REMOTE_CONF="/etc"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Raptor Deploy to T8410X ==="
echo "Target: ${CAMERA_USER}@${CAMERA_IP}"
echo ""

# Check SSH connectivity
echo "[1/6] Checking SSH connectivity..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${CAMERA_USER}@${CAMERA_IP}" "echo ok" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to ${CAMERA_USER}@${CAMERA_IP}"
    echo "Make sure SSH is enabled and key-based auth is configured."
    echo ""
    echo "To set up SSH key:"
    echo "  ssh-copy-id ${CAMERA_USER}@${CAMERA_IP}"
    exit 1
fi

# Stop prudynt (existing streamer)
echo "[2/6] Stopping prudynt..."
ssh "${CAMERA_USER}@${CAMERA_IP}" '
    if pidof prudynt >/dev/null 2>&1; then
        /etc/init.d/S95prudynt stop 2>/dev/null || killall prudynt 2>/dev/null || true
        sleep 1
        echo "  prudynt stopped"
    else
        echo "  prudynt not running"
    fi
'

# Transfer binaries
echo "[3/6] Transferring Raptor binaries..."
BINARIES="rvd rsd rad rhd rod ric rmr rmd rwc rwd rsp rsr raptorctl ringdump rac"
for bin in $BINARIES; do
    if [ -f "${SCRIPT_DIR}/${bin}" ]; then
        scp -q "${SCRIPT_DIR}/${bin}" "${CAMERA_USER}@${CAMERA_IP}:${REMOTE_DIR}/${bin}"
    fi
done
echo "  Binaries transferred"

# Transfer shared libraries (if present)
if [ -d "${SCRIPT_DIR}/lib" ]; then
    echo "[4/6] Transferring shared libraries..."
    scp -q "${SCRIPT_DIR}/lib/"* "${CAMERA_USER}@${CAMERA_IP}:${REMOTE_LIB}/"
    ssh "${CAMERA_USER}@${CAMERA_IP}" "ldconfig 2>/dev/null || true"
    echo "  Libraries transferred"
else
    echo "[4/6] No shared libraries (static build)"
fi

# Transfer config
echo "[5/6] Transferring raptor.conf..."
if [ -f "${SCRIPT_DIR}/raptor.conf" ]; then
    scp -q "${SCRIPT_DIR}/raptor.conf" "${CAMERA_USER}@${CAMERA_IP}:${REMOTE_CONF}/raptor.conf"
    echo "  Config transferred"
else
    echo "  WARNING: raptor.conf not found, using camera default"
fi

# Transfer and install start script
echo "[6/6] Installing start script and launching Raptor..."
scp -q "${SCRIPT_DIR}/start-raptor.sh" "${CAMERA_USER}@${CAMERA_IP}:/tmp/start-raptor.sh"
ssh "${CAMERA_USER}@${CAMERA_IP}" '
    chmod +x /tmp/start-raptor.sh
    mv /tmp/start-raptor.sh /etc/init.d/S31raptor
    chmod +x /usr/bin/rvd /usr/bin/rsd /usr/bin/rwd 2>/dev/null || true

    # Disable prudynt autostart
    if [ -f /etc/init.d/S95prudynt ]; then
        chmod -x /etc/init.d/S95prudynt
        echo "  Disabled prudynt autostart"
    fi

    # Start Raptor
    /etc/init.d/S31raptor start
    sleep 2

    # Verify
    if pidof rvd >/dev/null 2>&1; then
        echo ""
        echo "=== Raptor is running ==="
        echo "  RTSP:   rtsp://'"${CAMERA_IP}"'/stream0"
        echo "  WebRTC: http://'"${CAMERA_IP}"'/webrtc"
        echo ""
    else
        echo ""
        echo "WARNING: rvd does not appear to be running."
        echo "Check logs: ssh '"${CAMERA_USER}@${CAMERA_IP}"' logread"
    fi
'

echo "Done."
