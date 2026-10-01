#!/usr/bin/env bash
# One-time: creates the Windows VM and boots the installer.
# Usage: ./create-vm.sh /path/to/Win10_22H2_English_x64.iso
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SRC/lib/common.sh"

IMG_DIR="/var/lib/libvirt/images/moza-vm"

iso="${1:-}"
[[ -n "$iso" ]] || die "usage: ./create-vm.sh /path/to/windows.iso
  Download the Windows 10 ISO from https://www.microsoft.com/software-download/windows10ISO"
[[ -f "$iso" ]] || die "ISO not found: $iso"
command -v virt-install >/dev/null || die "virt-install missing. Run ./install.sh first."
virsh_ list >/dev/null 2>&1 || die "can't talk to libvirt. If you just ran install.sh, log out and back in first."
vm_exists && die "VM '$VM_NAME' already exists. Delete it first with:
  virsh -c $LIBVIRT_URI undefine $VM_NAME --remove-all-storage"

# libvirt's qemu user often can't read files in your home folder, so keep the
# ISO next to the disk image.
log "copying ISO to $IMG_DIR (needs sudo)..."
sudo install -d "$IMG_DIR"
sudo cp "$iso" "$IMG_DIR/windows.iso"

# SATA disk + e1000e network: Windows has built-in drivers for both, so the
# installer needs no extra driver disk. Slower than virtio but plenty for
# Pit House. qemu-xhci handles USB devices of every speed.
log "creating VM '$VM_NAME' (${VM_VCPUS} CPUs, ${VM_MEMORY_MB} MB RAM, ${VM_DISK_GB} GB disk)..."
virt-install \
  --connect "$LIBVIRT_URI" \
  --name "$VM_NAME" \
  --os-variant win10 \
  --memory "$VM_MEMORY_MB" \
  --vcpus "$VM_VCPUS" \
  --cpu host-passthrough \
  --disk "path=$IMG_DIR/disk.qcow2,size=$VM_DISK_GB,format=qcow2,bus=sata" \
  --cdrom "$IMG_DIR/windows.iso" \
  --network network=default,model=e1000e \
  --controller usb,model=qemu-xhci \
  --graphics spice \
  --video qxl \
  --sound none \
  --noautoconsole

log "VM created. Opening the window so you can install Windows..."
cat <<'EOF'

  In the Windows installer:
    - "I don't have a product key" is fine (it runs unactivated with a watermark).
    - Pick "Custom: Install Windows only" and use the 40 GB drive.
  After Windows is up:
    - Install Moza Pit House from https://mozaracing.com/pit-house/
    - Shut Windows down, then use 'moza-vm' from now on.

EOF
virt-viewer --connect "$LIBVIRT_URI" --wait "$VM_NAME" >/dev/null 2>&1 || true
