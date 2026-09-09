#!/bin/bash

# Resolve the primary user (first user with UID 1000)
USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)
USER_UID=1000

[ -z "$USER_NAME" ] && { echo "Could not find user with UID 1000"; exit 1; }

STATE_FILE="/run/user/${USER_UID}/egpu-watcher.state"
#CHANGE THIS TO YOUR EGPU ID. You can find it with:
# lspci -nn | grep -E 'VGA|3D|Display'
EGPU_ID="1002:73bf" #RX6800

#(CHANGE THIS PATH TO YOUR DOCKSETTINGS LOCATION)
#ensure the state of settings is iGPU, just like the state of the device on boot
sudo -i -u "$USER_NAME" /run/media/system/GAMES/docksettings/docksettings.sh -g igpu
sleep 5

while true; do

    if [ -f "$STATE_FILE" ]; then
        PREV_STATE=$(cat "$STATE_FILE")
    else
        PREV_STATE="unknown"
    fi

    if lspci -nn -d "$EGPU_ID" | grep -q "$EGPU_ID"; then
        CURR_STATE="present"
    elif lspci -d ::0300 | grep -q .; then
        CURR_STATE="absent"
    else
        CURR_STATE="none"
    fi

    if [ "$PREV_STATE" != "$CURR_STATE" ]; then
        case "$CURR_STATE" in
            present)
                sudo "$USER_HOME/bin/switch-egpu.sh"
                sleep 30
                ;;
            absent)
                sudo "$USER_HOME/bin/switch-internal.sh"
                sleep 30
                ;;
            none)
                wall "NO GPU detected??"
                ;;
        esac
    fi

    echo "$CURR_STATE" > "$STATE_FILE"
    echo "$CURR_STATE"
    sleep 3
done
