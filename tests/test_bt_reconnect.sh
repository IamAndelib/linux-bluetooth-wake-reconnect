#!/usr/bin/env bash
# Tests bt-reconnect against a fake bluetoothctl. Touches no real devices.
# Run: ./tests/test_bt_reconnect.sh
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

mkdir -p "$WORK/bin" "$WORK/home/.config"
export HOME="$WORK/home"
export FAKE_CALLS="$WORK/calls"
export FAKE_CONNECTED="$WORK/connected"
export BT_RECONNECT_SUSPEND_COUNT="$WORK/suspend_count"
CONFIG="$HOME/.config/bluedevilglobalrc"
MAC=00:11:22:33:44:55
MAC2=00:11:22:33:44:66

# Fake bluetoothctl. FAKE_POWERED: yes, no or missing (no adapter).
# FAKE_CONNECT: ok, fail, or the number of failures before success.
cat > "$WORK/bin/bluetoothctl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CALLS"
case "$1" in
    show)
        [ "$FAKE_POWERED" = missing ] && { echo "No default controller available"; exit 1; }
        printf 'Controller AA\n\tPowered: %s\n' "$FAKE_POWERED"
        ;;
    info)
        if grep -qx "$2" "$FAKE_CONNECTED" 2>/dev/null; then
            printf 'Device %s\n\tConnected: yes\n' "$2"
        else
            printf 'Device %s\n\tConnected: no\n' "$2"
        fi
        ;;
    connect)
        tries=$(grep -c "^connect $2\$" "$FAKE_CALLS")
        case "$FAKE_CONNECT" in
            ok) echo "$2" >> "$FAKE_CONNECTED" ;;
            fail) exit 1 ;;
            *) [ "$tries" -gt "$FAKE_CONNECT" ] && echo "$2" >> "$FAKE_CONNECTED"; exit 0 ;;
        esac
        ;;
esac
EOF
# Skip the real waits.
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/bluetoothctl" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH"

# run NAME EXPECTED_EXIT EXPECTED_CONNECT_CALLS OUTPUT_PATTERN
run() {
    local name="$1" want_rc="$2" want_connects="$3" want_output="$4" output rc connects
    output=$(sh "$ROOT/bt-reconnect" 2>&1); rc=$?
    connects=$(grep -c '^connect ' "$FAKE_CALLS" 2>/dev/null || true)
    if [ "$rc" = "$want_rc" ] && [ "${connects:-0}" = "$want_connects" ] &&
        grep -q "$want_output" <<< "$output"; then
        echo "ok   - $name"
    else
        echo "FAIL - $name: rc=$rc (want $want_rc), connects=$connects (want $want_connects)"
        echo "$output" | sed 's/^/       /'
        fails=$((fails + 1))
    fi
    : > "$FAKE_CALLS"; : > "$FAKE_CONNECTED"; rm -f "$BT_RECONNECT_SUSPEND_COUNT"
}

setup() { # POWERED CONNECT CONFIG_BODY
    export FAKE_POWERED="$1" FAKE_CONNECT="$2"
    printf '%b' "$3" > "$CONFIG"
}

rm -f "$CONFIG"; export FAKE_POWERED=yes FAKE_CONNECT=ok
run "no bluedevil settings: exits cleanly" 0 0 "nothing to do"

setup yes ok '[Devices]\nconnectedDevices=\n'
run "empty list: nothing to do" 0 0 "nothing to do"

setup yes ok "[Devices]\nconnectedDevices=$MAC\n"; echo "$MAC" > "$FAKE_CONNECTED"
run "already connected: doesn't call connect" 0 0 "$MAC connected"

setup yes ok "[Devices]\nconnectedDevices=$MAC\n"
run "disconnected: connects" 0 1 "$MAC connected"

setup yes 2 "[Devices]\nconnectedDevices=$MAC\n"
run "connects after two failed attempts" 0 3 "$MAC connected"

setup yes fail "[Devices]\nconnectedDevices=$MAC\n"
run "never connects: stops after 5 tries and reports failure" 1 5 "could not be reconnected"

setup yes ok "[Devices]\nconnectedDevices=$MAC,$MAC2\n"
run "two devices: connects both" 0 2 "$MAC2 connected"

setup no ok "[Devices]\nconnectedDevices=$MAC\n"
run "Bluetooth off: doesn't connect, not a failure" 0 0 "turned off"

setup missing ok "[Devices]\nconnectedDevices=$MAC\n"
run "adapter never appears: reports failure" 1 0 "no Bluetooth adapter"

setup yes ok "[Devices]\nconnectedDevices=--help,$MAC,not-a-mac\n"
run "invalid entries are ignored" 0 1 "$MAC connected"

setup yes ok "[General]\nlaunchState=Enable\n[Devices]\nconnectedDevices=$MAC\n"; echo 0 > "$BT_RECONNECT_SUSPEND_COUNT"
run "Enable setting, no sleep yet: skips" 0 0 "skipping"

setup yes ok "[General]\nlaunchState=disable\n[Devices]\nconnectedDevices=$MAC\n"
run "Disable setting, sleep count unreadable: skips" 0 0 "skipping"

setup yes ok "[General]\nlaunchState=Enable\n[Devices]\nconnectedDevices=$MAC\n"; echo 2 > "$BT_RECONNECT_SUSPEND_COUNT"
run "Enable setting, after a sleep: connects" 0 1 "$MAC connected"

setup yes ok "[General]\nlaunchState=remember\n[Devices]\nconnectedDevices=$MAC\n"; echo 0 > "$BT_RECONNECT_SUSPEND_COUNT"
run "Remember setting at login: connects" 0 1 "$MAC connected"

[ "$fails" = 0 ] && echo "All passed." || { echo "$fails failed."; exit 1; }
