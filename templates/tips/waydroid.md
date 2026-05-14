# Waydroid — Android Apps on Linux Desktop

**What it solves**: Running full Android applications natively on a Linux desktop without an emulator or virtual machine. Waydroid uses Linux namespaces and a minimal Android system image to run the Android OS as a containerized environment directly on your kernel.

**When to reach for it**: Testing Android apps on Linux without needing a physical device or the heavyweight Android Studio emulator. Useful for automation testing, running Android-only apps on a Linux workstation, or quick compatibility checks.

**The non-obvious part**: Waydroid requires a **Wayland** session (not X11) and a kernel with `binder` and `ashmem` modules. On Ubuntu 22.04+, these modules are often missing from the default kernel — you may need to install `linux-modules-extra-$(uname -r)` or use the `waydroid-image` script which handles module loading. Also, hardware GPU acceleration requires additional setup (mesa or proprietary drivers configured for Waydroid's renderer).

Reference: https://www.makeuseof.com/tag/run-android-apps-games-linux/
