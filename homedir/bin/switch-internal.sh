#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

# Accept IGPU_ID as first argument (e.g., 1002:1638)
IGPU_ID="$1"
[ -z "$IGPU_ID" ] && { echo "Usage: $0 <IGPU_PCI_ID> (e.g., 1002:1638)"; exit 1; }

# Resolve the primary user (first user with UID 1000)
USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)
[ -z "$USER_NAME" ] && { echo "Could not find user with UID 1000"; exit 1; }

systemctl stop display-manager
echo "System uptime is $uptime_seconds seconds"
systemctl --machine="${USER_NAME}@.host" --user stop sunshine
pkill sunshine


sudo "$USER_HOME/bin/all-ways-egpu" set-compositor-primary internal
systemctl --machine="${USER_NAME}@.host" --user set-environment MESA_VK_DEVICE_SELECT="$IGPU_ID"
sudo -i -u "$USER_NAME" cardwire debug refresh-gpu
systemctl restart display-manager
echo 30000 | sudo tee /sys/class/backlight/*/brightness

#SETTINGS - CHANGE THIS PATH
sudo -i -u "$USER_NAME" "$USER_HOME/bin/egpudocksettings/docksettings.sh" -g igpu

sleep 15
systemctl --machine="${USER_NAME}@.host" --user start sunshine
