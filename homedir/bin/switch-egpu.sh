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
sudo -i -u "$USER_NAME" /run/media/system/GAMES/docksettings/docksettings.sh -g egpu

#HARDWARE SWITCH
systemctl --machine="${USER_NAME}@.host" --user stop sunshine
sudo pkill sunshine
sudo -i -u "$USER_NAME" "$USER_HOME/bin/all-ways-egpu" set-compositor-primary egpu
sleep 3

# for Bazzite
cardwire debug refresh-gpu
sleep 1
sudo -i -u "$USER_NAME" cardwire debug refresh-gpu

sudo systemctl restart display-manager

# audio
sleep 10
sudo -i -u "$USER_NAME" pactl set-default-sink alsa_output.pci-0000_08_00.1.hdmi-stereo-extra3

echo 0 | sudo tee /sys/class/backlight/*/brightness

# sunshine
sleep 30
systemctl --machine="${USER_NAME}@.host" --user start sunshine
