#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

# Resolve the primary user (first user with UID 1000)
USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)

[ -z "$USER_NAME" ] && { echo "Could not find user with UID 1000"; exit 1; }

sudo systemctl stop display-manager

#SETTINGS (CHANGE THIS PATH TO YOUR DOCKSETTINGS LOCATION)
sudo -i -u "$USER_NAME" /run/media/system/GAMES/docksettings/docksettings.sh -g igpu

#HARDWARE
#systemctl --user set-environment MESA_VK_DEVICE_SELECT=

# Get uptime in seconds
uptime_seconds=$(cut -d. -f1 /proc/uptime)

if [ "$uptime_seconds" -lt 60 ]; then
    echo "System uptime is less than a minute ($uptime_seconds seconds)"
    exit
else
    echo "System uptime is $uptime_seconds seconds"
    systemctl --machine="${USER_NAME}@.host" --user stop sunshine
    sudo pkill sunshine
    wlr-randr --output eDP-1 --on
    sudo -i -u "$USER_NAME" "$USER_HOME/bin/all-ways-egpu" set-compositor-primary internal
    sleep 3
    sudo -i -u "$USER_NAME" cardwire debug refresh-gpu
    sleep 2
    sudo systemctl restart display-manager
    sleep 3
    echo 30000 | sudo tee /sys/class/backlight/*/brightness
    sleep 5
    INTERNAL_SINK=$(sudo -i -u "$USER_NAME" pactl list short sinks | grep analog-stereo | head -1 | cut -f2) [ -n "$INTERNAL_SINK" ]
    sudo -i -u "$USER_NAME" pactl set-default-sink "$INTERNAL_SINK"
fi
