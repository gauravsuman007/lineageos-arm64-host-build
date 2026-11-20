#!/bin/bash
# build native arm64 host tools, then replace x86 prebuilts with them
source /Volumes/Data/lineage-build/scripts/m.sh_env 2>/dev/null
cd /srv/lineage/android
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/srv/lineage/ccache LC_ALL=C ALLOW_MISSING_DEPENDENCIES=true BUILD_HOST_64bit=1 WITH_DEXPREOPT=false ALLOW_NINJA_ENV=true NINJA_ARGS="-k 0"
set +u; source build/envsetup.sh >/dev/null 2>&1; breakfast gts3lwifi userdebug >/dev/null 2>&1
m -j7 ziptime zipalign ziptool aidl hidl-lint bpfmt soong_zip zip2zip 2>&1 | grep --line-buffered -E "^\[ *[0-9]+%|^FAILED|error:|build completed|failed"| cut -c1-170 | tail -n 40
B=prebuilts/build-tools/linux-x86/bin
for t in ziptime zipalign ziptool aidl hidl-lint bpfmt soong_zip zip2zip; do
  s=out/soong/host/linux-x86/bin/$t
  if [ -f $s ] && file -L $s | grep -q aarch64; then [ -e $B/$t.x86 ] || mv $B/$t $B/$t.x86; ln -sf /srv/lineage/android/$s $B/$t; echo linked $t; else echo MISSING $t; fi
done
