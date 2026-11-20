#!/bin/bash
# Sync LineageOS 18.1 + gts3lwifi trees into /srv/lineage/android (image on the Data drive). Re-runnable.
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
bash $DATA/scripts/mount.sh >/dev/null || exit 1
git config --global user.name >/dev/null || git config --global user.name builder
git config --global user.email >/dev/null || git config --global user.email builder@localhost
git config --global color.ui false
cd $ANDROID_BUILD_TOP
START=$(date +%s)
echo "=== [1/3] repo init (lineage-18.1, shallow)"
[ -d .repo/manifests ] || repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --depth=1 --no-clone-bundle || exit 1
mkdir -p .repo/local_manifests
cp $DATA/scripts/local_manifest.xml .repo/local_manifests/gts3.xml
echo "=== [2/3] repo sync (shows per-project progress; ~80-120 GB; can take hours)"
for i in 1 2 3 4 5 6 7 8; do
  repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune && ok=1 && break
  echo "!!! sync attempt $i failed - retrying in 30s"; sleep 30
done
[ "$ok" = 1 ] || { echo "SYNC_FAILED"; exit 1; }
bash $DATA/scripts/lfs_fix.sh || exit 1
echo "=== [3/3] done in $(( ($(date +%s)-START)/60 )) min"
df -h /srv/lineage | tail -1; du -sh $ANDROID_BUILD_TOP/.repo 2>/dev/null
echo SYNC_DONE
