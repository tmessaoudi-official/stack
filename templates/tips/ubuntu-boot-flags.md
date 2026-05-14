# Ubuntu Boot Flags for Hardware Stability

**What they solve**: System freezes, kernel panics, or GPU instability on boot — often caused by PCIe devices (GPUs, NVMe controllers, network cards) that don't handle MSI (Message Signaled Interrupts) or Active State Power Management correctly.

## The flags

```
pci=nomsi,noaer pcie_aspm=off
```

- `pci=nomsi` — disables MSI for all PCI devices; falls back to legacy INTx interrupts. Fixes freezes on systems where a device's MSI implementation is buggy.
- `pci=noaer` — disables Advanced Error Reporting; stops the kernel from logging (and sometimes panicking on) PCI errors that don't actually affect operation.
- `pcie_aspm=off` — disables Active State Power Management on PCIe. Fixes instability on systems where ASPM transitions (link power state changes) cause devices to become unresponsive.

## Test without making permanent (single boot)

At the GRUB menu, press `e` to edit the boot entry. Find the line starting with `linux` and append the flags at the end:
```
linux /boot/vmlinuz-... root=... quiet splash pci=nomsi,noaer pcie_aspm=off
```
Press `Ctrl+X` or `F10` to boot. Changes apply only for this boot.

## Make permanent (GRUB config)

```bash
sudo nano /etc/default/grub
```

Find `GRUB_CMDLINE_LINUX_DEFAULT` and append the flags:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pci=nomsi,noaer pcie_aspm=off"
```

Apply:
```bash
sudo update-grub
sudo reboot
```

Verify after reboot:
```bash
cat /proc/cmdline
```

## When to use each flag

| Symptom | Flag to try |
|---------|-------------|
| Random freeze on boot or under GPU load | `pci=nomsi` |
| Kernel logs flooded with `AER: correctable` errors | `pci=noaer` |
| Freeze when screen goes to sleep or device idles | `pcie_aspm=off` |

Start with one flag at a time to isolate which device is the cause.
