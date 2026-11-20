#!/bin/bash
set -e
cd /srv/lineage/android
# a) bison wrapper (system bison 3.7 must use its own skeletons)
B=prebuilts/build-tools/linux-x86/bin
rm -f $B/bison; printf '#!/bin/bash\nunset BISON_PKGDATADIR\nexec /usr/bin/bison "$@"\n' > $B/bison; chmod +x $B/bison
rm -f $B/flex; ln -s /usr/bin/flex $B/flex
# b) gcc-4.9 cross binutils -> llvm tools
for d in prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 prebuilts/gcc/linux-x86/x86/x86_64-linux-android-4.9; do
  tr=$(ls $d/bin | grep -m1 -oE '^[a-z0-9_]+-linux-android[a-z]*-' ); [ -z "$tr" ] && continue
  [ -d $d/bin.x86 ] || cp -a $d/bin $d/bin.x86
  for t in objcopy strip readelf objdump nm ar ranlib size strings addr2line; do
    l=llvm-$t; [ $t = strip ] && l=llvm-strip; [ $t = ranlib ] && l=llvm-ranlib
    rm -f $d/bin/${tr}$t; ln -s /usr/bin/$l-11 $d/bin/${tr}$t
  done
  echo "relinked binutils in $d (${tr})"
done
# c) host compiler-rt for linking host shared libs
for C in clang-r383902 clang-r383902b clang-r383902b1; do
  v=$(ls prebuilts/clang/host/linux-x86/$C/lib64/clang | head -1)
  mkdir -p prebuilts/clang/host/linux-x86/$C/lib64/clang/$v/lib/linux
  cp -n /usr/lib/llvm-11/lib/clang/11.0.1/lib/linux/*aarch64* prebuilts/clang/host/linux-x86/$C/lib64/clang/$v/lib/linux/ 2>/dev/null || true
done
# d) acp
mkdir -p /srv/lineage/tools-arm64
clang-11 -O2 -o /srv/lineage/tools-arm64/acp build/make/tools/acp/*.c -lz 2>&1 | tail -3 || true
[ -x /srv/lineage/tools-arm64/acp ] && { cp $B/acp $B/acp.x86 2>/dev/null; rm -f $B/acp; cp /srv/lineage/tools-arm64/acp $B/acp; echo acp-ok; }
