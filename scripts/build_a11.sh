#!/bin/bash
# Unattended Android 11 (LineageOS 18.1) build on native arm64 host. Re-run safely; ninja resumes.
LOG=/Volumes/Data/lineage-build/build_a11.log
cd /srv/lineage/android
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/srv/lineage/ccache LC_ALL=C ALLOW_MISSING_DEPENDENCIES=true BUILD_HOST_64bit=1 WITH_DEXPREOPT=${WITH_DEXPREOPT:-true} ALLOW_NINJA_ENV=true
export NINJA_ARGS="-k 0"
export CCACHE_COMPILERCHECK="string:a11-arm64-wrapper-v1"
source build/envsetup.sh >/dev/null 2>&1
breakfast gts3lwifi userdebug >/dev/null 2>&1
echo "=== build start $(date)" | tee -a $LOG
m -j7 "${@:-bacon}" 2>&1 | tee -a $LOG | grep --line-buffered -E "^\[ *[0-9]+%|^FAILED|error:|build completed|failed to build" | cut -c1-180
echo "=== end $(date) rc=${PIPESTATUS[0]}"
echo "failed outputs in log: $(grep -c '^FAILED' $LOG)"
