#!/bin/bash
# NATIVE-host build of the 18.1 kernel (awesometic v0.13 source) with the Android GCC 4.9 (x86-64, run via qemu-user)
# -- the compiler the working prebuilt kernel was made with (host gcc 10 builds did not boot).
# Usage: kernel_build_181.sh [--no-patches]   (--no-patches = unpatched source, to prove the toolchain boots)
# Build reuse: persistent $OUT (never wiped) + ccache (20G, direct mode, path-independent) -> reruns recompile only what changed;
# changing flags forces kbuild to recompile affected files, but ccache still serves any object whose preprocessed input + flags match.
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
bash $DATA/scripts/mount.sh >/dev/null || exit 1
K=$LINEAGE/kernel-181; OUT=$LINEAGE/kernel-181-out-gcc49; RES=$DATA/kernel-output; mkdir -p $RES $OUT
TAG=${1:-patched}
step(){ echo; echo "=== [$1] $2   ($(date +%H:%M:%S))"; }
step 1/5 "Sync source from kernel/samsung/msm8996 (rsync keeps mtimes: unchanged files are not rebuilt)"
mkdir -p $K; rsync -a --delete --exclude .git $LINEAGE/android/kernel/samsung/msm8996/ $K/
if [ "$TAG" != "--no-patches" ]; then
  step 2/5 "Apply patches"
  for p in $DATA/kernel-patches/*.patch; do patch -d $K -p1 -N --no-backup-if-mismatch < $p || exit 1; done
  python3 $DATA/scripts/gpmu_fix.py $K/drivers/gpu/msm/adreno_a5xx.c
else
  step 2/5 "UNPATCHED build (toolchain proof)"
fi
cd $K
step 3/5 "Toolchain + configure"
export ARCH=arm64 QEMU_LD_PREFIX=/
G=$LINEAGE/android/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9
# wrapper dir: GCC 4.9 (x86, via qemu) + native arm64 binutils; no x86 LTO linker plugin (native ld cannot load it)
W=$LINEAGE/gcc49-bin; mkdir -p $W
for f in $G/bin/aarch64-linux-android-*; do ln -sf $f $W/$(basename $f); done
rm -f $W/aarch64-linux-android-gcc; printf '#!/bin/sh\nexec ccache %s/bin/aarch64-linux-android-gcc -fno-use-linker-plugin "$@"\n' "$G" > $W/aarch64-linux-android-gcc; chmod +x $W/aarch64-linux-android-gcc
export CROSS_COMPILE="$W/aarch64-linux-android-"  # ccache is called inside the gcc wrapper
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
which arm-linux-gnueabi-gcc >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gcc-arm-linux-gnueabi >/dev/null 2>&1
$W/aarch64-linux-android-gcc --version | head -1
export CCACHE_DIR=$LINEAGE/ccache-kernel CCACHE_BASEDIR=$LINEAGE CCACHE_NOHASHDIR=1 CCACHE_MAXSIZE=20G
export CCACHE_COMPILERCHECK=content CCACHE_SLOPPINESS=file_macro,time_macros,include_file_mtime,include_file_ctime
mkdir -p $LINEAGE/hostcc; printf '#!/bin/sh\nexec gcc -fcommon "$@"\n' > $LINEAGE/hostcc/clang; chmod +x $LINEAGE/hostcc/clang; touch $LINEAGE/hostcc/ld
which python2 >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python2 >/dev/null 2>&1
make O=$OUT gts3lwifi_defconfig 2>&1 | tail -2
step 4/5 "Count what needs building (dry run, reuses everything already built)"
MK="make O=$OUT -j7 CROSS_COMPILE=$CROSS_COMPILE HOSTCC=$LINEAGE/hostcc/clang HOSTCXX=g++ KCFLAGS=-Wno-error"
TOTAL=$($MK -n Image.gz-dtb 2>/dev/null | grep -c " -c -o ")
echo "   $TOTAL files to compile in this run (already-built objects are skipped)"
step 4/5 "Build Image.gz-dtb (-j7)"
$MK Image.gz-dtb 2>&1 \
  | grep -E "^\s+(CC|AS|LD|GZIP|DTC|Kernel)|error:|\*\*\*" | awk -v T=$TOTAL 'BEGIN{t0=systime()}
    /^ +(CC|AS) /{n++; if (n%25==0) printf "%s  compiled %d/%d (%d%%)  %ds  %s\n", strftime("%H:%M:%S"), n, T, (T?100*n/T:0), systime()-t0, $2; fflush(); next}
    /error|\*\*\*|Kernel|GZIP|DTC/{printf "%s  %s\n", strftime("%H:%M:%S"), $0; fflush()}
    END{printf "%s  compiled %d/%d total\n", strftime("%H:%M:%S"), n, T}'
IMG=$OUT/arch/arm64/boot/Image.gz-dtb
if [ -f $IMG ] && [ $IMG -nt $K/Makefile ]; then
  step 5/5 "Done"; D=$RES/Image.gz-dtb-181-gcc49$([ "$TAG" = "--no-patches" ] && echo -unpatched)
  cp -v $IMG $D; sha256sum $D; ccache -s | grep -E "hit|miss|size"; echo KERNEL_BUILD_DONE
else
  echo KERNEL_BUILD_FAILED
fi
