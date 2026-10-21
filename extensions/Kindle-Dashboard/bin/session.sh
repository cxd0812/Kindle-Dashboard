#!/bin/sh
# Owns the display session. Worker and input monitor never restore the UI.
BASE_DIR="/mnt/us/extensions/Kindle-Dashboard"
LOG="/tmp/dashboard.log"
STATE="/tmp/kindle-dashboard-session"
SAFETY_LOCK="/mnt/us/STOP_DASH"
WORKER_PID=
TOUCH_PID=
RESTORE_UI=0

trap '' HUP
if ! mkdir "$STATE" 2>/dev/null; then
    echo "[Session] Session directory already exists; refusing duplicate start: $STATE" >> "$LOG"
    exit 1
fi
echo $$ > "$STATE/pid"
cleanup() {
    trap '' INT TERM
    echo "[Session] Stopping Dashboard..." >> "$LOG"
    # Only our own process group: includes curl, ping, DHCP and sleep.
    if [ -n "$WORKER_PID" ]; then
        kill -KILL "-$WORKER_PID" 2>/dev/null
        wait "$WORKER_PID" 2>/dev/null
    fi
    if [ -n "$TOUCH_PID" ]; then
        kill -TERM "$TOUCH_PID" 2>/dev/null
        wait "$TOUCH_PID" 2>/dev/null
    fi
    if [ "$RESTORE_UI" = 1 ]; then
        case "$OLD_ROTATE" in 0|1|2|3) echo "$OLD_ROTATE" > /sys/class/graphics/fb0/rotate ;; esac
        case "$OLD_WIFI" in on|off) iw wlan0 set power_save "$OLD_WIFI" >> "$LOG" 2>&1 ;; esac
        lipc-set-prop com.lab126.powerd preventScreenSaver "$OLD_SAVER" >> "$LOG" 2>&1
        if start framework >> "$LOG" 2>&1; then
            echo "[Session] Native framework restarted." >> "$LOG"
        else
            echo "[Session] ERROR: start framework failed; inspect this log over SSH." >> "$LOG"
        fi
    fi
    rm -f "$STATE/pid" "$STATE/ready" "$STATE/exit"
    rmdir "$STATE" 2>/dev/null
}
trap cleanup 0
trap 'exit 0' INT TERM

# Do all preflight checks before taking down the reading interface.
if [ -f "$SAFETY_LOCK" ]; then
    echo "[Session] Remove $SAFETY_LOCK before starting Dashboard." >> "$LOG"
    exit 1
fi
for cmd in setsid stop start lipc-set-prop lipc-get-prop; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[Session] Missing command: $cmd; leaving native UI running." >> "$LOG"
        exit 1
    fi
done
chmod +x "$BASE_DIR/bin/touch_exit"
"$BASE_DIR/bin/touch_exit" "$STATE/ready" "$STATE/exit" >> "$LOG" 2>&1 &
TOUCH_PID=$!
attempt=0
while [ ! -f "$STATE/ready" ]; do
    if ! kill -0 "$TOUCH_PID" 2>/dev/null || [ "$attempt" -ge 5 ]; then
        echo "[Session] Touch monitor failed; leaving native UI running." >> "$LOG"
        exit 1
    fi
    sleep 1
    attempt=$((attempt + 1))
done
OLD_ROTATE=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
OLD_SAVER=$(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)
case "$OLD_SAVER" in 0|1) ;; *) OLD_SAVER=0 ;; esac
OLD_WIFI=$(iw wlan0 get power_save 2>/dev/null | awk '/Power save:/ {print $3}')
RESTORE_UI=1
if ! stop framework >> "$LOG" 2>&1; then
    echo "[Session] Failed to stop framework; restoring." >> "$LOG"
    exit 1
fi
if [ -f "$STATE/exit" ] || ! kill -0 "$TOUCH_PID" 2>/dev/null; then exit 0; fi
setsid /bin/sh "$BASE_DIR/bin/run_daemon.sh" >> "$LOG" 2>&1 &
WORKER_PID=$!
echo "[Session] Ready: hold one finger still for 3 seconds, then release to return to Kindle." >> "$LOG"
while :; do
    if [ -f "$STATE/exit" ] || [ -f "$SAFETY_LOCK" ]; then exit 0; fi
    if ! kill -0 "$TOUCH_PID" 2>/dev/null || ! kill -0 "$WORKER_PID" 2>/dev/null; then
        echo "[Session] A child exited; restoring native UI." >> "$LOG"
        exit 1
    fi
    sleep 1
done
