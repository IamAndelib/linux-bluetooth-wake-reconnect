#!/bin/sh
# Install bt-reconnect for the current user. Needs no root.
set -eu
here=$(cd -- "$(dirname -- "$0")" && pwd)

if [ "$(id -u)" = 0 ]; then
    echo "Run this as your normal user, without sudo: it installs into your home folder." >&2
    exit 1
fi

for tool in bluetoothctl systemctl timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: $tool not found." >&2
        exit 1
    fi
done

if ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "ERROR: can't reach your systemd user session. Run this from a normal login session." >&2
    exit 1
fi

if ! command -v bluedevil-wizard >/dev/null 2>&1; then
    echo "ERROR: bluedevil not found. This fix relies on KDE Plasma's Bluetooth service" >&2
    echo "to record which devices were connected before sleep. See README.md." >&2
    exit 1
fi

install -Dm755 "$here/bt-reconnect" "$HOME/.local/bin/bt-reconnect"
install -Dm644 "$here/bt-reconnect.service" "$HOME/.config/systemd/user/bt-reconnect.service"
systemctl --user daemon-reload
systemctl --user enable bt-reconnect.service

echo
echo "Installed. Test it: connect your device, put the PC to sleep, then wake it."
echo "It should reconnect within a few seconds. To see what happened:"
echo "  journalctl --user -u bt-reconnect -b"
