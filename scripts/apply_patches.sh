#!/bin/bash
# Apply patches/<project>.patch to the LineageOS tree (run inside the VM). Idempotent.
set -u
REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
T=${T:-/srv/lineage/android}
for f in "$REPO"/patches/*.patch; do
  p=$(basename "$f" .patch)
  # map file name back to project path via pinned-revisions.txt
  d=$(awk '{print $2}' "$REPO/pinned-revisions.txt" | while read x; do [ "$(echo "$x" | tr / _)" = "$p" ] && echo "$x"; done | head -1)
  [ -z "$d" ] && { echo "?? no project for $p"; continue; }
  if git -C "$T/$d" apply --check -R "$f" 2>/dev/null; then echo "ok   $d (already applied)"; continue; fi
  git -C "$T/$d" apply --whitespace=nowarn "$f" && echo "done $d" || echo "FAIL $d"
done
mkdir -p "$T/external/python/arm64-shim" && cp -a "$REPO/extra/arm64-shim/." "$T/external/python/arm64-shim/"
for C in clang-r383902 clang-r383902b clang-r383902b1; do
  for n in clang clang++; do cp "$REPO/extra/clang-wrapper.tmpl" "$T/prebuilts/clang/host/linux-x86/$C/bin/$n"; chmod +x "$T/prebuilts/clang/host/linux-x86/$C/bin/$n"; done
done
install -D -m755 "$REPO/extra/versioner-stub.sh" /srv/lineage/tools-arm64/versioner
ln -sfn /srv/lineage/tools-arm64/versioner "$T/prebuilts/clang-tools/linux-x86/bin/versioner"
echo APPLY_DONE
