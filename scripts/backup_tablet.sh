#!/bin/bash
# Back up every partition of the Tab S3 (SM-T820) eMMC plus both GPT copies,
# verifying each image against an on-device sha256.
# Usage: backup_tablet.sh <outdir> [partition ...]   (default: all except userdata)
set -u
OUT=${1:?outdir}; shift
mkdir -p "$OUT"
adb root >/dev/null 2>&1; adb get-state >/dev/null
BN=/dev/block/bootdevice/by-name
if [ $# -gt 0 ]; then PARTS="$*"; else
  PARTS=$(adb shell "ls $BN" | tr -d '\r' | grep -vx userdata); fi
DISK=/dev/block/mmcblk0
if [ ! -f "$OUT/gpt_primary.bin" ]; then
  # primary GPT: LBA 0..33 ; backup GPT: last 33 sectors
  adb exec-out "dd if=$DISK bs=512 count=34 2>/dev/null" > "$OUT/gpt_primary.bin"
  SECT=$(adb shell "cat /sys/block/mmcblk0/size" | tr -d '\r')
  adb exec-out "dd if=$DISK bs=512 skip=$((SECT-33)) count=33 2>/dev/null" > "$OUT/gpt_backup.bin"
  adb shell "sgdisk --print $DISK 2>/dev/null || cat /proc/partitions" > "$OUT/partition_table.txt"
fi
fail=0
for p in $PARTS; do
  f="$OUT/$p.img"
  dev_sum=$(adb shell "sha256sum $BN/$p" | awk '{print $1}')
  if [ -f "$f" ] && [ "$(shasum -a 256 "$f" | awk '{print $1}')" = "$dev_sum" ]; then
    echo "skip  $p (already verified)"; continue; fi
  sz=$(adb shell "blockdev --getsize64 $BN/$p" | tr -d '\r')
  echo "dump  $p ($((sz/1048576)) MiB)"
  adb exec-out "dd if=$BN/$p bs=4194304 2>/dev/null" | pv -s "$sz" -N "$p" > "$f"
  host_sum=$(shasum -a 256 "$f" | awk '{print $1}')
  if [ "$host_sum" = "$dev_sum" ]; then echo "ok    $p $host_sum"; echo "$host_sum  $p.img" >> "$OUT/SHA256SUMS"
  else echo "FAIL  $p device=$dev_sum host=$host_sum"; fail=1; fi
done
echo "=== backup done, fail=$fail"
