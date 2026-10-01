# Shared helpers for moza-vm. Sourced, not executed.

LIBVIRT_URI="qemu:///system"
CONF_FILE="${MOZA_VM_CONF:-/etc/moza-vm.conf}"

# Defaults, overridden by the config file.
# shellcheck disable=SC2034  # used by create-vm.sh
VM_NAME="moza-win"
MOZA_USB_IDS="346e 0483:df11"
VM_MEMORY_MB=4096
VM_VCPUS=2
VM_DISK_GB=40
VM_RESOLUTION="1600x900"

# shellcheck source=moza-vm.conf
[[ -r "$CONF_FILE" ]] && . "$CONF_FILE"

virsh_() { virsh --connect "$LIBVIRT_URI" "$@"; }

log() { printf '[moza-vm] %s\n' "$*"; }
die() { printf '[moza-vm] error: %s\n' "$*" >&2; exit 1; }

vm_exists()  { virsh_ dominfo "$VM_NAME" >/dev/null 2>&1; }
vm_running() { [[ "$(virsh_ domstate "$VM_NAME" 2>/dev/null)" == "running" ]]; }

# True if vendor:product (lowercase hex) matches an entry in MOZA_USB_IDS.
usb_id_matches() {
  local vid="$1" pid="$2" entry
  for entry in $MOZA_USB_IDS; do
    entry="${entry,,}"
    if [[ "$entry" == *:* ]]; then
      [[ "$entry" == "$vid:$pid" ]] && return 0
    else
      [[ "$entry" == "$vid" ]] && return 0
    fi
  done
  return 1
}

# Prints "busnum devnum vid:pid" for every connected matching USB device.
list_moza_devices() {
  local dev vid pid
  for dev in /sys/bus/usb/devices/*; do
    [[ -r "$dev/idVendor" && -r "$dev/busnum" ]] || continue
    vid="$(<"$dev/idVendor")"
    pid="$(<"$dev/idProduct")"
    usb_id_matches "$vid" "$pid" || continue
    echo "$(<"$dev/busnum") $(<"$dev/devnum") $vid:$pid"
  done
}

hostdev_xml() {
  # Address by bus/device so identical devices never get mixed up.
  printf "<hostdev mode='subsystem' type='usb' managed='yes'><source><address bus='%d' device='%d'/></source></hostdev>\n" \
    "$((10#$1))" "$((10#$2))"
}

is_attached() {
  # Herestring, not a pipe: grep -q exiting early would trip pipefail.
  grep -q "<address bus='$((10#$1))' device='$((10#$2))'/>" <<<"$(virsh_ dumpxml "$VM_NAME")"
}

attach_device() {
  local bus="$1" dev="$2" xml
  is_attached "$bus" "$dev" && return 0
  xml="$(mktemp)"
  hostdev_xml "$bus" "$dev" >"$xml"
  local rc=0
  virsh_ attach-device "$VM_NAME" "$xml" --live >/dev/null || rc=$?
  rm -f "$xml"
  return $rc
}

detach_device() {
  local bus="$1" dev="$2" xml
  is_attached "$bus" "$dev" || return 0
  xml="$(mktemp)"
  hostdev_xml "$bus" "$dev" >"$xml"
  local rc=0
  virsh_ detach-device "$VM_NAME" "$xml" --live >/dev/null || rc=$?
  rm -f "$xml"
  return $rc
}
