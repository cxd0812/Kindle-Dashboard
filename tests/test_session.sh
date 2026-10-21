#!/bin/sh
# Run on Linux: sh tests/test_session.sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d /tmp/dashboard-test.XXXXXX)
trap 'rm -rf "$FIXTURE"' 0
mkdir -p "$FIXTURE/bin" "$FIXTURE/app/bin"
export FIXTURE
export PATH="$FIXTURE/bin:$PATH"
cat > "$FIXTURE/bin/stop" <<'EOF'
#!/bin/sh
echo stop >> "$FIXTURE/actions"
EOF
cat > "$FIXTURE/bin/start" <<'EOF'
#!/bin/sh
echo start >> "$FIXTURE/actions"
EOF
cat > "$FIXTURE/bin/lipc-get-prop" <<'EOF'
#!/bin/sh
echo 0
EOF
cat > "$FIXTURE/bin/lipc-set-prop" <<'EOF'
#!/bin/sh
echo "saver $3" >> "$FIXTURE/actions"
EOF
cat > "$FIXTURE/bin/iw" <<'EOF'
#!/bin/sh
if [ "$2" = get ]; then echo 'Power save: on'; else echo "wifi $4" >> "$FIXTURE/actions"; fi
EOF
cat > "$FIXTURE/app/bin/touch_exit" <<'EOF'
#!/bin/sh
if [ "$MODE" = fail ]; then exit 1; fi
touch "$1"
if [ "$MODE" = die ]; then sleep 2; exit 1; fi
if [ "$MODE" = gesture ]; then sleep 2; touch "$2"; exit 0; fi
sleep 600
EOF
cat > "$FIXTURE/app/bin/run_daemon.sh" <<'EOF'
#!/bin/sh
if [ "$MODE" = worker_failure ]; then exit 1; fi
echo 3 > "$FIXTURE/rotate"
(sleep 5; echo orphan > "$FIXTURE/orphan") &
sleep 600
EOF
chmod +x "$FIXTURE/bin/"* "$FIXTURE/app/bin/"*
sed -e "s|^BASE_DIR=.*|BASE_DIR=\"$FIXTURE/app\"|" \
    -e "s|^LOG=.*|LOG=\"$FIXTURE/log\"|" \
    -e "s|^STATE=.*|STATE=\"$FIXTURE/state\"|" \
    -e "s|^SAFETY_LOCK=.*|SAFETY_LOCK=\"$FIXTURE/STOP_DASH\"|" \
    -e "s|/sys/class/graphics/fb0/rotate|$FIXTURE/rotate|g" \
    "$ROOT/extensions/Kindle-Dashboard/bin/session.sh" > "$FIXTURE/session.sh"

for MODE in gesture fail die worker_failure signal safety duplicate; do
    export MODE
    : > "$FIXTURE/actions"
    echo 1 > "$FIXTURE/rotate"
    sh "$FIXTURE/session.sh" &
    pid=$!
    # Bound hangs even when the session fails to clean up.
    (sleep 15; kill "$pid" 2>/dev/null || :) &
    guard=$!
    case "$MODE" in
        signal|safety|duplicate)
            i=0
            until grep -q '^stop$' "$FIXTURE/actions"; do
                sleep 1; i=$((i + 1)); [ "$i" -lt 8 ]
            done
            if [ "$MODE" = signal ]; then kill -TERM "$pid";
            elif [ "$MODE" = safety ]; then touch "$FIXTURE/STOP_DASH";
            else
                if sh "$FIXTURE/session.sh"; then echo 'FAIL: duplicate accepted'; exit 1; fi
                touch "$FIXTURE/state/exit"
            fi
            ;;
    esac
    wait "$pid" || :
    kill "$guard" 2>/dev/null || :
    wait "$guard" 2>/dev/null || :
    [ ! -d "$FIXTURE/state" ]
    [ "$(cat "$FIXTURE/rotate")" = 1 ]
    if [ "$MODE" = fail ]; then
        [ ! -s "$FIXTURE/actions" ]
    else
        [ "$(grep -c '^stop$' "$FIXTURE/actions")" = 1 ]
        [ "$(grep -c '^start$' "$FIXTURE/actions")" = 1 ]
        grep -q '^saver 0$' "$FIXTURE/actions"
        grep -q '^wifi on$' "$FIXTURE/actions"
    fi
    rm -f "$FIXTURE/STOP_DASH"
    echo "PASS: $MODE"
done
sleep 5
[ ! -f "$FIXTURE/orphan" ]
echo 'PASS: no worker descendants survived exit'
