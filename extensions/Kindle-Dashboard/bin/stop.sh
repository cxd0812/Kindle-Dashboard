#!/bin/sh
# Also usable over SSH: sh /mnt/us/extensions/Kindle-Dashboard/bin/stop.sh
STATE="/tmp/kindle-dashboard-session"
if [ -d "$STATE" ]; then
    touch "$STATE/exit"
fi
