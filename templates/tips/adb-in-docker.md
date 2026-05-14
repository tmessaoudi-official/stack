# ADB in Docker

**What it solves**: Running Android development tools (ADB, Android SDK) inside a Docker container while still being able to communicate with a physical Android device or emulator attached to the host machine. The problem is that USB devices are bound to the host and not automatically visible inside containers.

**When to reach for it**: You want a reproducible, isolated Android build/test environment without installing the Android SDK on the host, but you still need to push APKs or run instrumentation tests on a real device.

**The non-obvious part**: ADB uses a client-server model. The ADB server runs on the host (where the USB device is connected). Containers can reach it via the host network (`host.docker.internal` or the Docker bridge IP) on port 5037. You don't need USB passthrough at all — you just need the container's ADB client to talk to the host's ADB server. The bridge approach is simpler than USB device sharing and works without `--privileged`.

Reference: https://twosixtech.com/blog/integrating-docker-and-adb/
