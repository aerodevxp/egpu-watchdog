#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

# Resolve the primary user (first user with UID 1000)
USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)

[ -z "$USER_NAME" ] && { echo "Could not find user with UID 1000"; exit 1; }

# Get uptime in seconds
uptime_seconds=$(cut -d. -f1 /proc/uptime)

if [ "$uptime_seconds" -lt 60 ]; then
    echo "System uptime is less than a minute ($uptime_seconds seconds)"
    exit
else
    sudo systemctl stop display-manager
    echo "System uptime is $uptime_seconds seconds"
    systemctl --machine="${USER_NAME}@.host" --user stop sunshine
    sudo pkill sunshine
    #SETTINGS - CHANGE THIS PATH
    sudo -i -u "$USER_NAME" /run/media/system/GAMES/docksettings/docksettings.sh -g igpu
    sudo -i -u "$USER_NAME" "$USER_HOME/bin/all-ways-egpu" set-compositor-primary internal
    #disable TDP boost, and go powersave mode. Also start autotdp.service if it exists (from my other repo)
    echo 0 | sudo tee /sys/devices/system/cpu/cpufreq/boost
    echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
    echo balance_performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference
    sudo systemctl restart autotdp
    sudo -i -u "$USER_NAME" cardwire debug refresh-gpu
    sudo systemctl restart display-manager
    echo 30000 | sudo tee /sys/class/backlight/*/brightness
    sleep 15
    systemctl --machine="${USER_NAME}@.host" --user start sunshine
    
fi
