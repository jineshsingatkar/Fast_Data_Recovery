#!/usr/bin/env bash
# Fast Data Recovery - Linux CLI Dashboard
# Safe-first menu for SMART checks, imaging with ddrescue, mounting images read-only,
# and launching TestDisk/PhotoRec.
#
# REQUIREMENTS (Debian/Ubuntu):
#   sudo apt update && sudo apt install -y gddrescue testdisk photorec smartmontools \
#       ntfs-3g exfatprogs e2fsprogs xfsprogs btrfs-progs kpartx util-linux
#
# USAGE:
#   chmod +x FastDataRecovery.sh
#   sudo ./FastDataRecovery.sh
#
# SAFETY:
# - Always image first with ddrescue if there are read errors.
# - Perform recovery on the image, not the original.
# - Filesystem repair commands are guarded and should be used only on a clone.

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$LOG_DIR" "$REPORT_DIR"

pause() { read -r -p "Press Enter to continue..." _; }
warn() { echo -e "\033[33mWARNING:\033[0m $*"; }
err() { echo -e "\033[31mERROR:\033[0m $*"; }
info() { echo -e "\n\033[36m==== $* ====\033[0m\n"; }
need_root() { if [[ $EUID -ne 0 ]]; then err "Run as root (sudo)."; exit 1; fi }

check_cmd() { command -v "$1" &>/dev/null; }

list_disks() {
  info "Disks Overview"
  if check_cmd lsblk; then
    lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL
  fi
  echo
  sudo fdisk -l || true
  echo
  warn "Never repair a failing source; image first with ddrescue."
}

smart_menu() {
  need_root
  if ! check_cmd smartctl; then err "smartctl not found. Install smartmontools."; return; fi
  list_disks
  read -r -p "Enter device path for SMART (e.g., /dev/sda): " dev
  [[ -b "$dev" ]] || { err "Invalid block device: $dev"; return; }
  info "SMART for $dev"
  smartctl -a -d auto "$dev" || warn "smartctl returned non-zero (may include warnings)"
  pause
}

imaging_menu() {
  need_root
  if ! check_cmd ddrescue; then err "ddrescue not found. Install gddrescue."; return; fi
  list_disks
  read -r -p "Source device (e.g., /dev/sdX): " src
  [[ -b "$src" ]] || { err "Invalid source: $src"; return; }
  mkdir -p /mnt/recovery
  read -r -p "Destination directory (e.g., /mnt/recovery): " dest
  [[ -d "$dest" ]] || { err "Destination directory does not exist: $dest"; return; }
  ts="$(date +%Y%m%d_%H%M%S)"
  img="$dest/image_${ts}.img"
  map="$dest/map_${ts}.log"
  info "ddrescue pass 1 (no-scrape)"
  ddrescue -f -n "$src" "$img" "$map"
  info "ddrescue retry pass (scrape)"
  read -r -p "Retries count (default 3, 0 to skip): " retries
  retries=${retries:-3}
  if [[ "$retries" =~ ^[0-9]+$ && "$retries" -gt 0 ]]; then
    ddrescue -f -r"$retries" "$src" "$img" "$map"
  else
    warn "Skipping retry pass."
  fi
  echo "Image: $img" | tee -a "$LOG_DIR/imaging_last.txt"
  echo "Map:   $map" | tee -a "$LOG_DIR/imaging_last.txt"
  pause
}

mount_image_menu() {
  need_root
  read -r -p "Path to image file (.img): " img
  [[ -f "$img" ]] || { err "Image not found: $img"; return; }
  info "Setting up loop device (read-only)"
  loopdev=$(losetup --find --show --read-only "$img")
  echo "Loop: $loopdev"
  info "Adding partition mappings (kpartx)"
  kpartx -av "$loopdev" || true
  echo "Available mappings:"
  ls /dev/mapper/ | grep -E "$(basename "$loopdev")p" || true
  read -r -p "Partition to mount (e.g., /dev/mapper/$(basename "$loopdev")p1): " part
  [[ -e "$part" ]] || { err "Mapping not found: $part"; losetup -d "$loopdev"; return; }
  read -r -p "Mount point (e.g., /mnt/imgp1): " mnt
  mkdir -p "$mnt"
  # Try to detect filesystem
  fstype=$(blkid -o value -s TYPE "$part" || true)
  if [[ "$fstype" == "ntfs" ]]; then
    mount -o ro,show_sys_files,streams_interface=windows "$part" "$mnt"
  elif [[ "$fstype" == ext* ]]; then
    mount -o ro,noload "$part" "$mnt"
  else
    mount -o ro "$part" "$mnt"
  fi
  echo "Mounted $part -> $mnt (read-only)"
  warn "To unmount: umount '$mnt'; kpartx -dv '$loopdev'; losetup -d '$loopdev'"
  pause
}

launch_testdisk() {
  need_root
  if ! check_cmd testdisk; then err "testdisk not found. Install testdisk."; return; fi
  read -r -p "Target (device or image path, e.g., /dev/sdX or /path/image.img): " target
  [[ -e "$target" ]] || { err "Target not found: $target"; return; }
  testdisk "$target"
}

launch_photorec() {
  need_root
  local bin="photorec"
  if ! check_cmd "$bin"; then
    # Some distros package as 'qphotorec' GUI only; try 'photorec' from testdisk package
    if check_cmd testdisk && [[ -x "/usr/sbin/photorec" ]]; then bin="/usr/sbin/photorec"; else err "photorec not found. Install photorec/testdisk."; return; fi
  fi
  read -r -p "Target (device or image path): " target
  [[ -e "$target" ]] || { err "Target not found: $target"; return; }
  "$bin" "$target"
}

repair_fs_menu() {
  need_root
  info "Filesystem repair (use only on a clone)"
  read -r -p "Block device to repair (e.g., /dev/sdXN): " dev
  [[ -b "$dev" ]] || { err "Invalid device: $dev"; return; }
  warn "These operations modify the filesystem. Ensure you work on a clone!"
  read -r -p "Type I UNDERSTAND to continue: " ack
  [[ "$ack" == "I UNDERSTAND" ]] || { echo "Cancelled."; return; }
  fstype=$(blkid -o value -s TYPE "$dev" || true)
  case "$fstype" in
    ntfs)
      echo "Running ntfsfix (basic). For full repair, use Windows chkdsk on the clone."
      ntfsfix "$dev" || true
      ;;
    ext2|ext3|ext4)
      e2fsck -f -y -v "$dev"
      ;;
    vfat|fat|fat32)
      fsck.vfat -v "$dev"
      ;;
    exfat)
      fsck.exfat -v "$dev"
      ;;
    xfs)
      xfs_repair -n "$dev"
      echo "Review output. Remove -n to modify (on clone only)."
      ;;
    btrfs)
      btrfs check --readonly "$dev"
      echo "For data recovery, consider 'btrfs restore' on the image."
      ;;
    *)
      warn "Unknown or undetected FS type: $fstype. Proceed manually."
      ;;
  esac
  pause
}

report_menu() {
  ts="$(date +%Y%m%d_%H%M%S)"
  out="$REPORT_DIR/disk_report_${ts}.txt"
  {
    echo "Fast Data Recovery - Disk Report (Linux)"
    echo "Timestamp: $(date)"
    echo
    echo "lsblk:"; lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL
    echo
    echo "fdisk -l:"; sudo fdisk -l 2>&1
    if check_cmd smartctl; then
      echo
      echo "SMART overall (-H):"
      for d in /dev/sd? /dev/nvme?n? 2>/dev/null; do
        [[ -e "$d" ]] || continue
        echo "== $d =="
        sudo smartctl -H -d auto "$d" 2>&1 || true
        echo
      done
    else
      echo
      echo "SMART: smartctl not installed."
    fi
  } >"$out"
  echo "Saved: $out"
  pause
}

menu() {
  while true; do
    clear
    info "Fast Data Recovery - Linux CLI Dashboard"
    echo "Select an option:"
    echo "  1) List disks (safe)"
    echo "  2) SMART health check (smartctl)"
    echo "  3) Image drive with ddrescue"
    echo "  4) Mount image read-only"
    echo "  5) Launch TestDisk"
    echo "  6) Launch PhotoRec"
    echo "  7) Filesystem repair (guarded)"
    echo "  8) Generate disk report to file"
    echo "  0) Exit"
    read -r -p "Enter choice: " sel
    case "$sel" in
      1) list_disks; pause ;;
      2) smart_menu ;;
      3) imaging_menu ;;
      4) mount_image_menu ;;
      5) launch_testdisk ;;
      6) launch_photorec ;;
      7) repair_fs_menu ;;
      8) report_menu ;;
      0) break ;;
      *) warn "Invalid selection"; sleep 1 ;;
    esac
  done
}

menu

