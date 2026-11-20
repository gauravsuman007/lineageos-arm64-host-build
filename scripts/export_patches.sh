#!/bin/bash
# Export every source change in the LineageOS tree as one patch per project.
# Prebuilt binary swaps are NOT exported (they are recreated by the arm64_* scripts);
# small text files under prebuilts (clang wrapper) are exported separately.
set -u
T=/srv/lineage/android; OUT=${1:-/Volumes/Data/lineage-build/export/patches}
rm -rf "$OUT"; mkdir -p "$OUT"
cd $T
repo list -p | while read p; do
  case "$p" in prebuilts/*) continue;; esac
  [ -d "$p/.git" ] || [ -f "$p/.git" ] || continue
  st=$(git -C "$p" status --porcelain 2>/dev/null) || continue
  [ -z "$st" ] && continue
  f="$OUT/$(echo "$p" | tr / _).patch"
  git -C "$p" add -N . 2>/dev/null          # include new (untracked) files in the diff
  git -C "$p" diff --binary -- . ':(exclude)*.orig' > "$f"
  git -C "$p" reset -q 2>/dev/null
  [ -s "$f" ] && echo "$p $(grep -c '^diff --git' "$f") files" || rm -f "$f"
done
# files outside any git project
mkdir -p "$OUT/../extra"
cp -a external/python/arm64-shim "$OUT/../extra/" 2>/dev/null
cp prebuilts/clang/host/linux-x86/wrapper.tmpl "$OUT/../extra/clang-wrapper.tmpl" 2>/dev/null
cp /srv/lineage/tools-arm64/versioner "$OUT/../extra/versioner-stub.sh" 2>/dev/null
echo EXPORT_DONE
