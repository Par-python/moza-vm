# moza-vm

Run **Moza Pit House** on Linux. `moza-vm` opens a window with Pit House in it and your wheel connected. There's no Windows desktop, just Pit House. Tune settings or update firmware, close Pit House, and the VM shuts down and hands the wheel back to Linux for gaming.

Under the hood it's a small Windows VM in kiosk mode, set up completely hands-off.

Built for Linux Mint, and should work on Ubuntu or Debian. It uses QEMU/KVM + libvirt.

> **This is for configuration, not gaming.** While the VM is running it owns the wheel, and Linux games can't see it. Settings you save in Pit House live on the wheelbase, so they still apply when you game on Linux afterwards. Features that need Pit House running *during* a game (telemetry effects, RPM lights, dash) won't work this way.

## Requirements

- A CPU with virtualization (AMD-V / Intel VT-x) **enabled in the BIOS**. On AMD laptops the setting is usually called **"SVM Mode"**.
- 8 GB RAM or more. The VM uses 4 GB, so close other big apps while it runs.
- About 45 GB free disk space.
- A Windows 10 ISO from [Microsoft](https://www.microsoft.com/software-download/windows10ISO) (the normal multi-edition one; it must include Windows 10 Pro). No product key needed; it runs unactivated.

No GPU passthrough. Pit House runs fine on the VM's virtual display.

## Setup (once)

```bash
git clone https://github.com/Par-python/moza-vm.git
cd moza-vm
./install.sh
```

If it says you were added to the `libvirt`/`kvm` groups, **log out and back in**. Then:

```bash
./create-vm.sh ~/Downloads/Win10_22H2_English_x64.iso
```

That's the last thing you do. Over the next 30–60 minutes it:

1. Downloads Moza's official Pit House offline package (~500 MB).
2. Installs Windows with no prompts (local account, no Microsoft login).
3. Installs Pit House, its USB drivers and the Visual C++ runtimes.
4. Turns on kiosk mode: Windows logs in automatically and shows only Pit House.
5. Turns Windows Update and sleep off, then shuts the VM down.

A window shows progress. You can close it and the install keeps going. When the terminal says `done!`, you're set.

If Moza's download link ever changes, download the **Pit House offline installer** zip from the [Download Center](https://mozaracing.com/pages/download-center) yourself and add `--pithouse-zip ~/Downloads/MOZA_Pit_House_....zip`.

## Everyday use

```bash
moza-vm          # open Pit House (starts the VM, hands it the wheel)
moza-vm stop     # shut the VM down; wheel returns to Linux
moza-vm status   # where is my wheel right now?
moza-vm release  # give the wheel back without shutting down
```

**Closing Pit House shuts the VM down** and the wheel returns to Linux. If Pit House restarts itself for an update, the VM waits for it instead of shutting down.

### Getting to the Windows desktop (rarely needed)

In the VM window, use virt-viewer's **Send key → Ctrl+Alt+Del** menu, open **Task Manager → File → Run new task**, and type `explorer.exe`.

## How it works

- `moza-vm` finds every connected USB device whose ID is listed in `/etc/moza-vm.conf` (`346e` = all Moza devices by default) and attaches it to the running VM.
- A **udev rule** watches for those devices reconnecting. During a firmware update the wheelbase reboots and shows up as a new USB device. The rule attaches it to the VM again automatically, so the update can finish. When the VM is off, the rule does nothing.
- The devices are only attached while the VM is running, so they never stay stuck to it after it shuts down.
- Inside Windows, a small PowerShell script (`windows/kiosk.ps1`) replaces the desktop. It starts Pit House maximized and powers the VM off once Pit House has been closed for 15 seconds.

## Firmware updates: read this first

- Keep the VM running and the window open until Pit House says the update is done.
- **Don't** run `moza-vm stop` or `release` mid-update.
- If Pit House loses the device partway through, the wheelbase probably reconnected with a USB ID that isn't in the config. While it's in that state, run `lsusb` on Linux, find the new line, add its `vendor:product` ID to `MOZA_USB_IDS` in `/etc/moza-vm.conf`, run `./install.sh` again, then retry the update in Pit House. `0483:df11` (the common STM32 bootloader) is already included as a guess.

## Configuration

`/etc/moza-vm.conf`:

| Setting | Default | What it does |
|---|---|---|
| `VM_NAME` | `moza-win` | libvirt VM name |
| `MOZA_USB_IDS` | `346e 0483:df11` | USB IDs to pass through (`vid` or `vid:pid`) |
| `VM_MEMORY_MB` | `4096` | VM RAM (used by `create-vm.sh`) |
| `VM_VCPUS` | `2` | VM CPU cores |
| `VM_DISK_GB` | `40` | VM disk size |
| `VM_RESOLUTION` | `1600x900` | Pit House window size (set at create time) |

Re-run `./install.sh` after changing `MOZA_USB_IDS`.

## Troubleshooting

- **`CPU virtualization is turned off`**: enable SVM / VT-x in the BIOS.
- **`can't talk to libvirt`**: log out and back in after `install.sh`.
- **Windows install stopped on a screen asking something**: the ISO is probably missing Windows 10 Pro, or its language wasn't detected. Use the standard multi-edition ISO from Microsoft.
- **Setup inside Windows failed**: the VM window shows the error. The full log is `C:\moza\setup.log` (get there through the desktop escape hatch above). Run `./uninstall.sh --delete-vm`, then `./install.sh` and `./create-vm.sh` again.
- **Pit House closes to the system tray instead of quitting**: kiosk mode has no tray. Run `moza-vm stop`.
- **Wheel not showing in Pit House**: run `moza-vm status`. If it says `-> Linux`, run `lsusb` and check the Moza device's ID is in the config.
- **Hotplug logs**: `journalctl -t moza-vm`.

## Uninstall

```bash
./uninstall.sh              # remove moza-vm command + udev rule, keep the VM
./uninstall.sh --delete-vm  # also delete the VM and its disk
```

The KVM packages stay installed. Remove them with `apt` if you want.

## License

MIT
