#!/bin/bash
# Download the real Git-LFS files (WebView APKs etc.) that repo checked out as placeholders.
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
bash $DATA/scripts/mount.sh >/dev/null || exit 1
cd $ANDROID_BUILD_TOP
n=0; total=$(find . -path ./.repo -prune -o -name .gitattributes -print 2>/dev/null | xargs grep -l "filter=lfs" 2>/dev/null | wc -l)
echo "LFS repos to fetch: $total"
for ga in $(find . -path ./.repo -prune -o -name .gitattributes -print 2>/dev/null | xargs grep -l "filter=lfs" 2>/dev/null); do
  d=$(dirname $ga); n=$((n+1)); echo "[$n/$total] $d"
  ( cd $d && git config filter.lfs.smudge "git-lfs smudge -- %f" && git config filter.lfs.process "git-lfs filter-process" && git lfs pull 2>&1 | tail -2 ) 
done
echo "--- sizes:"; ls -lh external/chromium-webview/prebuilt/*/webview.apk
echo LFS_DONE
