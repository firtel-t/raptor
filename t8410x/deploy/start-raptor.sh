#!/bin/sh
#
# /etc/init.d/S31raptor - Raptor Streaming System init script
#
# Starts RVD first (creates ring buffers), then consumers.

CONF="/etc/raptor.conf"

start() {
    echo "Starting Raptor Streaming System..."

    # RVD must start first - it creates the shared memory ring buffers
    if [ -x /usr/bin/rvd ]; then
        start-stop-daemon -S -b -x /usr/bin/rvd -- -c "$CONF"
        sleep 1
    fi

    # Audio daemon
    if [ -x /usr/bin/rad ]; then
        start-stop-daemon -S -b -x /usr/bin/rad -- -c "$CONF"
    fi

    # RTSP server
    if [ -x /usr/bin/rsd ]; then
        start-stop-daemon -S -b -x /usr/bin/rsd -- -c "$CONF"
    fi

    # WebRTC server (low latency)
    if [ -x /usr/bin/rwd ]; then
        start-stop-daemon -S -b -x /usr/bin/rwd -- -c "$CONF"
    fi

    # HTTP snapshots / MJPEG
    if [ -x /usr/bin/rhd ]; then
        start-stop-daemon -S -b -x /usr/bin/rhd -- -c "$CONF"
    fi

    # OSD renderer
    if [ -x /usr/bin/rod ]; then
        start-stop-daemon -S -b -x /usr/bin/rod -- -c "$CONF"
    fi

    # IR-Cut controller
    if [ -x /usr/bin/ric ]; then
        start-stop-daemon -S -b -x /usr/bin/ric -- -c "$CONF"
    fi

    # Motion detection
    if [ -x /usr/bin/rmd ]; then
        start-stop-daemon -S -b -x /usr/bin/rmd -- -c "$CONF"
    fi

    echo "Raptor started."
}

stop() {
    echo "Stopping Raptor Streaming System..."
    for daemon in rmd ric rod rhd rwd rsd rad rvd; do
        if pidof "$daemon" >/dev/null 2>&1; then
            killall "$daemon" 2>/dev/null
        fi
    done
    sleep 1
    echo "Raptor stopped."
}

restart() {
    stop
    sleep 1
    start
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
