# egpu-watchdog
Scripts and services to be used in tandem with docksettings and allwaysegpu for a seamless eGPU docking and undocking experience.

Follow the folders and copy the file structure on your Linux system.

##Requirements + Steps
[all-ways-egpu](https://github.com/ewagner12/all-ways-egpu) under $HOME/bin and have it setup already. This handles the device switch.
My fork of [docksettings](https://github.com/aerodevxp/egpudocksettings) setup already. This handles the game settings switch. You WILL have to edit the following files to state the location of docksettings.sh:
```
/usr/local/bin/egpu-watcher.sh
$HOME/bin/switch-egpu.sh
$HOME/bin/switch-internal.sh
```

Under '/usr/local/bin/egpu-watcher.sh', you must also change the EGPU_ID for your own. Find your ID using:
```
sudo lspci -nn | grep -E 'VGA|3D|Display'
```

After everything has been put in place, run:
```
sudo systemctl enable egpu-watcher.service
sudo reboot
```

From now on, your device will detect the eGPU connection when it happens, and fully switch to it within 60 seconds. The script supports hotplug. You can plug and unplug the eGPU anytime without shutting down the system. On unplugging, the system will restart the display manager (your session, most likely gamescope) using the internal GPU/screen and restore iGPU settings.
