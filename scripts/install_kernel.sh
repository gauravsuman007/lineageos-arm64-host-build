#!/bin/bash
# Put a built kernel into the device tree so the ROM image (boot.img) ships it.
# usage: install_kernel.sh /path/to/Image.gz-dtb   (e.g. the output of kernel_build_181_native49.sh)
set -e; T=/srv/lineage/android/device/samsung/gts3l-common/prebuilt/Image.gz-dtb
cp "$1" $T; sha256sum $T
