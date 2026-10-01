#!/usr/bin/env bash
# One-time, hands-off: creates the Windows VM, installs Windows, Pit House and
# its drivers, and sets up kiosk mode. Takes 30-60 minutes; the VM turns
# itself off when it's done.
#
# Usage: ./create-vm.sh /path/to/Win10.iso [--pithouse-zip /path/to/MOZA_Pit_House.zip]
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "$SRC/lib/common.sh"

IMG_DIR="/var/lib/libvirt/images/moza-vm"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/moza-vm"
# Moza's official offline package (Download Center). This page redirects to a
# short-lived signed CDN link, so it is resolved fresh each time.
PITHOUSE_PAGE="https://ace.gudsen.vip/racing/cdn/indirect/63a5273b-749d-4cc6-9f69-2fc45cecf11f"
INSTALL_TIMEOUT_MIN=180

usage() {
  die "usage: ./create-vm.sh /path/to/windows10.iso [--pithouse-zip /path/to/MOZA_Pit_House.zip]
  Get the Windows 10 ISO from https://www.microsoft.com/software-download/windows10ISO"
}

iso="" pithouse_zip=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pithouse-zip) pithouse_zip="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) [[ -z "$iso" ]] || usage; iso="$1"; shift ;;
  esac
done
[[ -n "$iso" ]] || usage
[[ -f "$iso" ]] || die "ISO not found: $iso"
for cmd in virt-install xorriso curl python3 qemu-img; do
  command -v "$cmd" >/dev/null || die "$cmd missing. Run ./install.sh first."
done
virsh_ list >/dev/null 2>&1 || die "can't talk to libvirt. If you just ran install.sh, log out and back in first."
vm_exists && die "VM '$VM_NAME' already exists. Delete it first with: ./uninstall.sh --delete-vm"

mkdir -p "$CACHE_DIR"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 1. Windows language ------------------------------------------------------
# The unattend file must name the ISO's language or Setup stops to ask.
lang="en-US"
if xorriso -osirrox on -indev "$iso" -extract /sources/lang.ini "$work/lang.ini" >/dev/null 2>&1; then
  detected="$(awk '/^\[Available UI Languages\]/{f=1;next} /^\[/{f=0} f && /=/{gsub(/[ \t\r]/,""); split($0,a,"="); print a[1]; exit}' "$work/lang.ini")"
  [[ -n "$detected" ]] && lang="$detected"
fi
log "Windows ISO language: $lang"

# 2. Pit House offline package ---------------------------------------------
check_zip() {
  python3 - "$1" <<'EOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
sys.exit(0 if "MOZA Pit House/bin/MOZA Pit House.exe" in z.namelist() else 1)
EOF
}
if [[ -z "$pithouse_zip" ]]; then
  pithouse_zip="$CACHE_DIR/pithouse.zip"
  if [[ ! -f "$pithouse_zip" ]]; then
    log "finding the latest Pit House offline package..."
    url="$(curl -fsSL "$PITHOUSE_PAGE" | grep -oE 'https://cdn\.gudsen\.vip/[^"'"'"' )<>]+\.zip[^"'"'"' )<>]*' | head -1)" || true
    [[ -n "$url" ]] || die "couldn't find the download link on Moza's site. Download the Pit House
  offline installer zip yourself from https://mozaracing.com/pages/download-center
  and re-run with: --pithouse-zip /path/to/the.zip"
    log "downloading ${url%%\?*} (~500 MB)..."
    curl -fL --progress-bar -o "$pithouse_zip.part" "$url"
    mv "$pithouse_zip.part" "$pithouse_zip"
  else
    log "using cached Pit House package: $pithouse_zip"
  fi
fi
check_zip "$pithouse_zip" || die "$pithouse_zip doesn't look like the Pit House offline package
  (no 'MOZA Pit House/bin/MOZA Pit House.exe' inside). Delete it and re-run."

# 3. Setup ISO --------------------------------------------------------------
log "building setup disc..."
sed "s/@LANG@/$lang/g" "$SRC/windows/autounattend.xml.in" >"$work/autounattend.xml"
sed "s/@RESOLUTION@/$VM_RESOLUTION/g" "$SRC/windows/kiosk.ps1" >"$work/kiosk.ps1"
xorriso -as mkisofs -quiet -J -joliet-long -R -V MOZA_SETUP -o "$work/setup.iso" -graft-points \
  "autounattend.xml=$work/autounattend.xml" \
  "setup.ps1=$SRC/windows/setup.ps1" \
  "kiosk.ps1=$work/kiosk.ps1" \
  "pithouse.zip=$pithouse_zip"

# libvirt's qemu user often can't read your home folder, so everything the VM
# uses lives under /var/lib/libvirt/images.
log "copying files to $IMG_DIR (needs sudo)..."
sudo install -d "$IMG_DIR"
sudo cp "$iso" "$IMG_DIR/windows.iso"
sudo install -m 644 "$work/setup.iso" "$IMG_DIR/setup.iso"
sudo qemu-img create -q -f qcow2 "$IMG_DIR/disk.qcow2" "${VM_DISK_GB}G"

# 4. VM ----------------------------------------------------------------------
# Boot order disk-then-CD: the empty disk falls through to the installer, and
# after Windows' first reboot the disk boots, so no "press any key" prompts.
# SATA disk + e1000e network have built-in Windows drivers. qemu-xhci handles
# USB devices of every speed.
log "creating VM '$VM_NAME' (${VM_VCPUS} CPUs, ${VM_MEMORY_MB} MB RAM, ${VM_DISK_GB} GB disk)..."
virt-install \
  --connect "$LIBVIRT_URI" \
  --name "$VM_NAME" \
  --os-variant win10 \
  --memory "$VM_MEMORY_MB" \
  --vcpus "$VM_VCPUS" \
  --cpu host-passthrough \
  --disk "path=$IMG_DIR/disk.qcow2,format=qcow2,bus=sata,boot.order=1" \
  --disk "path=$IMG_DIR/windows.iso,device=cdrom,bus=sata,boot.order=2" \
  --disk "path=$IMG_DIR/setup.iso,device=cdrom,bus=sata" \
  --network network=default,model=e1000e \
  --controller usb,model=qemu-xhci \
  --graphics spice \
  --video qxl \
  --sound none \
  --import \
  --noautoconsole >/dev/null

log "installing Windows + Pit House. Nothing to click; this takes 30-60 minutes."
log "a window shows progress. Closing it is fine, the install keeps going."
setsid virt-viewer --connect "$LIBVIRT_URI" --reconnect "$VM_NAME" >/dev/null 2>&1 &

start=$SECONDS
while vm_running; do
  elapsed=$(( (SECONDS - start) / 60 ))
  (( elapsed < INSTALL_TIMEOUT_MIN )) || die "still not finished after $INSTALL_TIMEOUT_MIN minutes. Check the VM window
  (virt-viewer -c $LIBVIRT_URI $VM_NAME). Setup log inside Windows: C:\\moza\\setup.log"
  printf '\r[moza-vm] working... %d min' "$elapsed"
  sleep 30
done
echo
pkill -f "virt-viewer --connect $LIBVIRT_URI --reconnect $VM_NAME" 2>/dev/null || true

# 5. Clean up ---------------------------------------------------------------
log "install finished. Removing installer discs from the VM..."
while read -r target path; do
  [[ "$path" == *.iso ]] || continue
  virsh_ detach-disk "$VM_NAME" "$target" --config >/dev/null || true
done < <(virsh_ domblklist "$VM_NAME" | awk 'NR>2 && NF==2 {print $1, $2}')
sudo rm -f "$IMG_DIR/windows.iso" "$IMG_DIR/setup.iso"

log "done! Run 'moza-vm' to open Pit House."
