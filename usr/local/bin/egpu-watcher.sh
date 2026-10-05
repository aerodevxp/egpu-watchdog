#!/bin/bash

systemctl stop display-manager

# Resolve the primary user (first user with UID 1000)
USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)
USER_UID=1000

[ -z "$USER_NAME" ] && { echo "Could not find user with UID 1000"; exit 1; }

STATE_FILE="/run/user/${USER_UID}/egpu-watcher.state"
#CHANGE THIS TO YOUR EGPU ID. You can find it with:
# lspci -nn | grep -E 'VGA|3D|Display'
EGPU_ID="1002:73bf" #RX6800
IGPU_ID="1002:1638" #z1 extreme igpu
#fresh start on boot
rm -rf "$STATE_FILE"

while true; do

    if [ -f "$STATE_FILE" ]; then
        PREV_STATE=$(cat "$STATE_FILE")
    else
        PREV_STATE="unknown"
    fi

    EGPU_VENDOR=$(echo "$EGPU_ID" | cut -d: -f1)
    EGPU_DEVICE=$(echo "$EGPU_ID" | cut -d: -f2)
    EGPU_DRM=0
    EGPU_PCI_PATH=""
    for dev in /sys/bus/pci/devices/*; do
        [ -d "$dev" ] || continue
        vid=$(cat "$dev/vendor" 2>/dev/null | sed 's/0x//' | tr 'A-F' 'a-f')
        did=$(cat "$dev/device" 2>/dev/null | sed 's/0x//' | tr 'A-F' 'a-f')
        if [ "$vid" = "$(echo "$EGPU_VENDOR" | tr 'A-F' 'a-f')" ] && [ "$did" = "$(echo "$EGPU_DEVICE" | tr 'A-F' 'a-f')" ]; then
            EGPU_PCI_PATH="$dev"
            if ls "$dev"/drm/card* >/dev/null 2>&1; then
                EGPU_DRM=1
            fi
        fi
    done

    if [ "$EGPU_DRM" = "1" ]; then
        CURR_STATE="present"
    else
        CURR_STATE="absent"
    fi

    if [ "$PREV_STATE" != "$CURR_STATE" ]; then
        case "$CURR_STATE" in
            present)
                #egpu detected, do not use igpu
                sudo "$USER_HOME/bin/switch-egpu.sh" $EGPU_ID
                ;;
            absent)
                sudo "$USER_HOME/bin/switch-internal.sh" $IGPU_ID
                #to have proper memory for replug
                echo 1 | sudo tee /proc/sys/vm/compact_memory > /dev/null
                echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
                ;;
        esac
    fi

    echo "$CURR_STATE" > "$STATE_FILE"
    echo "$CURR_STATE"
    sleep 3
done
