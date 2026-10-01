# moza-vm

Run **Moza Pit House** on Linux by putting it in a small Windows VM and passing your Moza wheelbase through to it over USB. You can tune wheel settings and update firmware, then shut the VM down and the wheel goes back to Linux for gaming.

Built for Linux Mint, and should work on Ubuntu or Debian. It uses QEMU/KVM + libvirt.

> **This is for configuration, not gaming.** While the VM is running it owns the wheel, and Linux games can't see it. Settings you save in Pit House live on the wheelbase, so they still apply when you game on Linux afterwards. Features that need Pit House running *during* a game (telemetry effects, RPM lights, dash) won't work this way.

## Requirements

- A CPU with virtualization (AMD-V / Intel VT-x) **enabled in the BIOS**. On AMD laptops the setting is usually called **"SVM Mode"**.
- 8 GB RAM or more. The VM uses 4 GB, so close other big apps while it runs.
- About 45 GB free disk space.
- A Windows 10 ISO from [Microsoft](https://www.microsoft.com/software-download/windows10ISO). No product key needed; unactivated Windows works fine with a watermark.

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

A window opens with the Windows installer. Install Windows, then download and install [Moza Pit House](https://mozaracing.com/pit-house/) inside it, and shut Windows down.

## Everyday use

```bash
moza-vm          # start VM, hand it the wheel, open the window
moza-vm stop     # shut Windows down; wheel returns to Linux
moza-vm status   # where is my wheel right now?
moza-vm release  # give the wheel back without shutting down
```

Shutting Windows down from its Start menu works too. The wheel returns to Linux as soon as the VM turns off.

## How it works

- `moza-vm` finds every connected USB device whose ID is listed in `/etc/moza-vm.conf` (`346e` = all Moza devices by default) and attaches it to the running VM.
- A **udev rule** watches for those devices reconnecting. During a firmware update the wheelbase reboots and shows up as a new USB device. The rule attaches it to the VM again automatically, so the update can finish. When the VM is off, the rule does nothing.
- The devices are only attached while the VM is running, so they never stay stuck to it after it shuts down.

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

Re-run `./install.sh` after changing `MOZA_USB_IDS`.

## Troubleshooting

- **`CPU virtualization is turned off`**: enable SVM / VT-x in the BIOS.
- **`can't talk to libvirt`**: log out and back in after `install.sh`.
- **Wheel not showing in Pit House**: run `moza-vm status`. If it says `-> Linux`, run `lsusb` and check the Moza device's ID is in the config. You may also need the Moza USB driver inside Windows, which comes with Pit House.
- **Hotplug logs**: `journalctl -t moza-vm`.

## Uninstall

```bash
./uninstall.sh              # remove moza-vm command + udev rule, keep the VM
./uninstall.sh --delete-vm  # also delete the VM and its disk
```

The KVM packages stay installed. Remove them with `apt` if you want.

## License

MIT
