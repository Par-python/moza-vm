#!/usr/bin/env bash
# Removes the moza-vm command and udev rule. Leaves the VM and the KVM
# packages alone unless you pass --delete-vm.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
MOZA_VM_CONF=/etc/moza-vm.conf . "$SRC/lib/common.sh"

if [[ "${1:-}" == "--delete-vm" ]] && vm_exists; then
  vm_running && virsh_ destroy "$VM_NAME" >/dev/null
  virsh_ undefine "$VM_NAME" --remove-all-storage
  sudo rm -rf /var/lib/libvirt/images/moza-vm
  log "deleted VM '$VM_NAME'"
fi

sudo rm -f /etc/udev/rules.d/99-moza-vm.rules /usr/local/bin/moza-vm
sudo rm -rf /opt/moza-vm
sudo udevadm control --reload-rules
log "removed moza-vm. /etc/moza-vm.conf was kept."
