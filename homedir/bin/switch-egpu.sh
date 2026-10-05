#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

#getting the egpu ID from the watchdog call
EGPU_ID="$1"
[ -z "$EGPU_ID" ] && { echo "Usage: $0 <EGPU_PCI_ID> (e.g., 1002:73bf)"; exit 1; }

USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)

[ -z "$USER_NAME" ] && { echo "Could not find user with UID 1000"; exit 1; }

systemctl stop display-manager

#SETTINGS (CHANGE THIS PATH TO YOUR DOCKSETTINGS LOCATION)
sudo -i -u "$USER_NAME" "$USER_HOME/bin/egpudocksettings-main/docksettings.sh" -g egpu

#HARDWARE SWITCH
systemctl --machine="${USER_NAME}@.host" --user stop sunshine
pkill sunshine
#For supported versions
sudo -i -u "$USER_NAME" "$USER_HOME/bin/all-ways-egpu" set-compositor-primary egpu
#For all the rest
systemctl --machine="${USER_NAME}@.host" --user set-environment MESA_VK_DEVICE_SELECT=${EGPU_ID}
sleep 1


#cpu boost amd
systemctl stop autotdp
ryzenadj -a 53000 -f 53000 -b 53000
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference
echo 1 | sudo tee /sys/devices/system/cpu/cpufreq/boost

# for Bazzite
sudo -i -u "$USER_NAME" cardwire debug refresh-gpu

systemctl restart display-manager


# audio
sleep 10
sudo -i -u "$USER_NAME" pactl set-default-sink alsa_output.pci-0000_08_00.1.hdmi-stereo-extra3

echo 0 | sudo tee /sys/class/backlight/*/brightness

# sunshine
sleep 30
systemctl --machine="${USER_NAME}@.host" --user start sunshine
