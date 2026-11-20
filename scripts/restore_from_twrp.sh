#!/bin/bash
# Emergency restore of the Lineage 20 boot+system (and optionally userdata)
# from the verified backup, run while the tablet is in TWRP (adb reachable).
# Usage: restore_from_twrp.sh [--with-data]
set -eu
B=/Volumes/Data/lineage-build/tablet-backup-lineage20
BN=/dev/block/bootdevice/by-name
adb wait-for-recovery
parts="boot system"
[ "${1:-}" = "--with-data" ] && parts="$parts userdata"
for p in $parts; do
  echo "restoring $p"
  adb shell "umount $BN/$p 2>/dev/null; true"
  pv "$B/$p.img" | adb shell "dd of=$BN/$p bs=4194304"
  want=$(grep " $p.img$" "$B/SHA256SUMS" | awk '{print $1}')
  got=$(adb shell "sha256sum $BN/$p" | awk '{print $1}')
  [ "$want" = "$got" ] && echo "verified $p" || { echo "MISMATCH $p"; exit 1; }
done
echo "restore done; rebooting"; adb reboot
