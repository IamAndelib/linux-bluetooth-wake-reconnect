#!/bin/sh
# Remove bt-reconnect for the current user. Needs no root.
set -eu

if [ "$(id -u)" = 0 ]; then
    echo "Run this as your normal user, without sudo." >&2
    exit 1
fi

systemctl --user disable bt-reconnect.service 2>/dev/null || true
rm -f "$HOME/.local/bin/bt-reconnect" "$HOME/.config/systemd/user/bt-reconnect.service"
systemctl --user daemon-reload

echo "Removed. Devices will go back to not reconnecting after sleep."
