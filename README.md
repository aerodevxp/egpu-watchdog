# egpu-watchdog for Gamescope
Scripts and services to be used in tandem with my fork of docksettings and all-ways-egpu for a seamless eGPU docking and undocking experience.


Installation:
```
curl -fsSL -o /tmp/egpu-install.sh https://raw.githubusercontent.com/aerodevxp/egpu-watchdog/main/install.sh && chmod +x /tmp/egpu-install.sh && sudo /tmp/egpu-install.sh; rm -f /tmp/egpu-install.sh
```
OR Follow the folders and copy the file structure on your Linux system.

This will most likely work on other sessions thanks to all-ways-egpu, but that's not something I'm officially supporting.

## Requirements + Steps
- [all-ways-egpu](https://github.com/ewagner12/all-ways-egpu) under $HOME/bin and have it setup already. This handles the device switch.
- My fork of [docksettings](https://github.com/aerodevxp/egpudocksettings) setup already. This handles the game settings switch. You WILL have to edit the following files to state the location of docksettings.sh:
```
/usr/local/bin/egpu-watcher.sh
$HOME/bin/switch-egpu.sh
$HOME/bin/switch-internal.sh
```

Under '/usr/local/bin/egpu-watcher.sh', you must also change the EGPU_ID for your own. Find your ID using:
```
sudo lspci -nn | grep -E 'VGA|3D|Display'
```

Now, in your sudoers file (run 'EDITOR=nano visudo'). I am using the deck user as an example here. Replace deck with your username:
```
# Allow your user to run egpu scripts without password
deck ALL=(ALL) NOPASSWD: /home/deck/bin/switch-egpu.sh, /home/deck/bin/switch-internal.sh, /home/bin/all-ways-egpu

```
*Once your edits are done; Ctrl+O -> Enter -> Ctrl+Q.*

Finally, after everything has been put in place, run:
```
sudo systemctl enable egpu-watcher.service
sudo reboot
```

From now on, your device will detect the eGPU connection when it happens, and fully switch to it within 60 seconds. The script supports hotplug. You can plug and unplug the eGPU anytime without shutting down the system. On unplugging, the system will restart the display manager (your session, most likely gamescope) using the internal GPU/screen and restore iGPU settings.

There's a bug with CachyOS and the AG03 Dock that requires a reboot before docking a second time. If you plug in your eGPU and nothing happens for more than 90 seconds, reboot the device and it will work.

Tested on:
ROG Ally X + Bazzite 44
ROG Ally X + CachyOS
