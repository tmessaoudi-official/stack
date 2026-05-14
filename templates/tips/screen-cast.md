# Screen Casting Ubuntu to Chromecast

**What it solves**: Mirroring your Ubuntu desktop or casting a video from your Linux machine to a Chromecast device on the same network — without needing a browser tab cast (which requires Chrome).

**When to reach for it**: Presenting your Linux desktop on a TV or monitor that has a Chromecast attached, or playing local video files on a larger screen without physically connecting a cable.

**The non-obvious part**: Ubuntu does not have built-in Chromecast support. The common approach uses `mkchromecast` (for audio/video streaming) or VLC with Chromecast output. `mkchromecast` relies on GStreamer pipelines and the Chromecast discovery protocol (`zeroconf`/`avahi`). The non-obvious requirement: `avahi-daemon` must be running on your machine for device discovery to work (`sudo systemctl start avahi-daemon`). If your Chromecast doesn't appear, avahi is usually the missing piece.

Reference: https://vitux.com/how-to-cast-video-from-ubuntu-to-chromecast/
