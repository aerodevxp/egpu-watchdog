#!/bin/bash

[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }

LOG="/var/log/egpu-watcher.log"
: > "$LOG"
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a "$LOG"; }

log "started"

USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)
USER_UID=1000

[ -z "$USER_NAME" ] && { log "no uid 1000"; exit 1; }

STATE_FILE="/run/user/${USER_UID}/egpu-watcher.state"
EGPU_ID="1002:73bf" #RX6800
IGPU_ID="1002:1638" #z1 extreme igpu
EGPU_VENDOR="${EGPU_ID%%:*}"
EGPU_DEVICE="${EGPU_ID##*:}"

NODRM_TIMEOUT=8

rm -rf "$STATE_FILE"

norm() { printf '%s' "$1" | tr 'A-F' 'a-f' | sed 's/^0x//'; }

find_pci() {
    local dev
    for dev in /sys/bus/pci/devices/*; do
        [ -d "$dev" ] || continue
        [ -r "$dev/vendor" ] || continue
        if [ "$(norm "$(cat "$dev/vendor" 2>/dev/null)"):$(norm "$(cat "$dev/device" 2>/dev/null)")" = \
             "$(norm "$EGPU_VENDOR"):$(norm "$EGPU_DEVICE")" ]; then
            printf '%s\n' "$dev"
            return 0
        fi
    done
    return 1
}

NODRM_SINCE=""

#await proper boot
sleep 5

while true; do
    if [ -f "$STATE_FILE" ]; then
        PREV_STATE=$(cat "$STATE_FILE")
    else
        PREV_STATE="unknown"
    fi

    PCI=""
    if ! PCI="$(find_pci)"; then
        CURR_STATE="absent"
        NODRM_SINCE=""
    elif compgen -G "$PCI/drm/card*" >/dev/null; then
        CURR_STATE="present"
        NODRM_SINCE=""
    else
        CURR_STATE="pending"
        if [ -z "$NODRM_SINCE" ]; then
            NODRM_SINCE=$(date +%s)
            log "eGPU present, no DRM - timer started"
        fi
    fi

    if [ "$PREV_STATE" != "$CURR_STATE" ] && [ "$CURR_STATE" != "pending" ]; then
        log "state: $PREV_STATE -> $CURR_STATE"
        case "$CURR_STATE" in
            present)
                "$USER_HOME/bin/switch-egpu.sh" "$EGPU_ID"
                ;;
            absent)
                "$USER_HOME/bin/switch-internal.sh" "$IGPU_ID"
                ;;
        esac
    fi

    [ "$CURR_STATE" != "pending" ] && echo "$CURR_STATE" > "$STATE_FILE"
    log "$CURR_STATE"

    if [ "$CURR_STATE" = "pending" ]; then
        elapsed=$(( $(date +%s) - NODRM_SINCE ))
        if [ "$elapsed" -ge "$NODRM_TIMEOUT" ]; then
            log "no DRM for ${elapsed}s - rebooting"
            [ -e "$PCI/driver" ] && syswrite "$PCI/remove" 1
            echo "reb"
            echo s | sudo tee /proc/sysrq-trigger    # sync
            echo u | sudo tee /proc/sysrq-trigger    # remount everything read-only
            echo b | sudo tee /proc/sysrq-trigger    # reboot now
        fi
    fi

    sleep 3
done
