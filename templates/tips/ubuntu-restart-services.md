# Restarting Ubuntu System Services

When a desktop service misbehaves — frozen UI, lost network, no audio — you usually don't need to reboot. Each service can be restarted independently.

---

## GNOME Shell

**Symptom**: Desktop frozen, panels unresponsive, windows won't move, extensions crashed.

**Restart (X11 only)**:
Press `Alt+F2`, type `r` (or `restart`), press `Enter`. GNOME Shell reloads in-place without closing your applications.

**Gotcha**: This only works on **X11**. On **Wayland**, `Alt+F2` does not offer the restart command — you must log out and back in, or kill `gnome-shell` (which ends your session). Check which you're on: `echo $XDG_SESSION_TYPE`.

**Alternative (both X11 and Wayland)**:
```bash
# Restarts gnome-shell as a background process — loses your session
killall -3 gnome-shell
```

---

## NetworkManager

**Symptom**: Wi-Fi or Ethernet connection dropped, VPN stuck, DNS not resolving, network icon missing.

**Restart**:
```bash
sudo systemctl restart NetworkManager
```

**Gotcha**: Restarting NetworkManager drops all active connections for 2–5 seconds. SSH sessions and VPNs will be interrupted. If you need to run this remotely, wrap it:
```bash
sleep 2 && sudo systemctl restart NetworkManager &
```
The `sleep` gives you time to confirm the command queued before the connection drops.

**Verify after**:
```bash
systemctl status NetworkManager
nmcli general status
```

---

## PulseAudio / Sound

**Symptom**: No audio output, audio device disappeared, sound stuck after suspend/resume, Bluetooth audio disconnected.

**Restart PulseAudio and force ALSA reload**:
```bash
pulseaudio -k && sudo alsa force-reload
```

`pulseaudio -k` kills the running PulseAudio daemon (it auto-restarts). `alsa force-reload` resets the kernel ALSA driver state.

**Gotcha**: On systems using **PipeWire** instead of PulseAudio (Ubuntu 22.10+), PulseAudio commands may not work. Check first:
```bash
pactl info | grep "Server Name"
```
If it shows `PipeWire`, use:
```bash
systemctl --user restart pipewire pipewire-pulse
```

**Verify after**:
```bash
pactl list sinks short   # should list output devices
aplay -l                 # list ALSA playback devices
```
