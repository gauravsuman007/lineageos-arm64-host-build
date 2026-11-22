#!/bin/bash
# usage: repack_boot2.sh <base boot.img> <kernel Image.gz-dtb> <out boot.img>  (everything but the kernel stays identical to the base)
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
BASE=$1; KERN=$2; OUTIMG=$3; W=/tmp/bootwork2; rm -rf $W; mkdir -p $W
T=$LINEAGE/android/system/tools/mkbootimg
python3 $T/unpack_bootimg.py --boot_img $BASE --out $W/orig > $W/info.txt
CMD=$(sed -n 's/^command line args: //p' $W/info.txt); echo "cmdline: $CMD"; grep -E "header version|os version|page size|load address|tags" $W/info.txt
python3 $T/mkbootimg.py --kernel $KERN --ramdisk $W/orig/ramdisk --base 0x80000000 --kernel_offset 0x00008000 --ramdisk_offset 0x02200000 --second_offset 0x00000000 --tags_offset 0x02000000 --pagesize 4096 --os_version 11.0.0 --os_patch_level 2024-02 --header_version 0 --cmdline "$CMD" -o $W/new.img
truncate -s $(stat -c %s $BASE) $W/new.img; cp $W/new.img $OUTIMG
python3 $T/unpack_bootimg.py --boot_img $OUTIMG --out $W/chk >/dev/null
[ "$(sha256sum < $W/orig/ramdisk)" = "$(sha256sum < $W/chk/ramdisk)" ] && echo "ramdisk SAME" || echo "ramdisk DIFFERENT"
[ "$(sha256sum < $KERN)" = "$(sha256sum < $W/chk/kernel)" ] && echo "kernel MATCH" || echo "kernel MISMATCH"
sha256sum $OUTIMG; echo REPACK_DONE
