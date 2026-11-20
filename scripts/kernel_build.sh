#!/bin/bash
# NATIVE arm64 kernel build for gts3lwifi (3.18, awesometic lineage-20.0-caf = the branch your tablet runs) with the GPMU fix.
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
bash $DATA/scripts/mount.sh >/dev/null || exit 1
K=$LINEAGE/kernel-20; OUT=$LINEAGE/kernel-out; RES=$DATA/kernel-output; mkdir -p $RES
step(){ echo; echo "=== [$1] $2   ($(date +%H:%M:%S))"; }
step 1/5 "Clone kernel (shallow, branch lineage-20.0-caf)"
[ -d $K/.git ] || git clone --depth 1 -b lineage-20.0-caf https://github.com/awesometic/android_kernel_samsung_msm8996 $K
cd $K; git log -1 --format='   HEAD: %h %s'
step 2/5 "Apply GPMU fix (drivers/gpu/msm/adreno_a5xx.c)"
git checkout -q -- drivers/gpu/msm/adreno_a5xx.c
python3 $DATA/scripts/gpmu_fix.py drivers/gpu/msm/adreno_a5xx.c
git --no-pager diff --stat | tail -2
step 3/5 "Configure (gts3lwifi_defconfig, host gcc $(gcc -dumpversion), native aarch64)"
export ARCH=arm64
which arm-linux-gnueabi-gcc >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-arm-linux-gnueabi >/dev/null 2>&1
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
# HOSTCC shim: this tree's link-vmlinux-preparation.sh expects HOSTCC=<dir>/clang and <dir>/ld; with GCC we just need it to be a no-op
mkdir -p $LINEAGE/hostcc; printf '#!/bin/sh\nexec gcc -fcommon "$@"\n' > $LINEAGE/hostcc/clang; chmod +x $LINEAGE/hostcc/clang; touch $LINEAGE/hostcc/ld
which python2 >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python2 >/dev/null 2>&1
mkdir -p $OUT
make O=$OUT gts3lwifi_defconfig 2>&1 | tail -2
step 4/5 "Build Image.gz-dtb with -j7 (progress lines below)"
make O=$OUT -j7 CC=gcc HOSTCC=$LINEAGE/hostcc/clang HOSTCXX=g++ KCFLAGS="-Wno-error -Wno-address-of-packed-member -Wno-array-bounds" Image.gz-dtb 2>&1 | grep -E "^\s+(CC|LD|AS|GZIP|DTC|HOSTCC|Kernel)|error|Error|\*\*\*" | awk '{n++; if (n%50==0 || /error|Error|\*\*\*|Kernel/) print strftime("%H:%M:%S"), n, $0}'
rc=${PIPESTATUS[0]}
if [ -f $OUT/arch/arm64/boot/Image.gz-dtb ]; then
  step 5/5 "Done"
  cp -v $OUT/arch/arm64/boot/Image.gz-dtb $RES/Image.gz-dtb-gpmufix
  ls -lh $RES; echo KERNEL_BUILD_DONE
else
  echo "KERNEL_BUILD_FAILED (make rc=$rc) - last errors:"; make O=$OUT -j1 CC=gcc Image.gz-dtb HOSTCC="gcc -fcommon" 2>&1 | grep -B2 -A6 -E "error:|Error " | head -40
fi
