#!/bin/bash
# Replace x86 host prebuilts with native arm64 equivalents (originals kept as *.x86). Idempotent.
set -e
cd /srv/lineage/android
swap(){ # swap <dir> <target>
  [ -L "$1" ] && { echo "already: $1"; return; }
  mv "$1" "$1.x86"; ln -s "$2" "$1"; echo "swapped $1 -> $2"; }
GOROOT=$(go env GOROOT); JH=$(dirname $(dirname $(readlink -f $(which java))))
swap prebuilts/go/linux-x86 $GOROOT
swap prebuilts/jdk/jdk11/linux-x86 $JH
# build-tools: keep dir, replace known binaries with system ones
B=prebuilts/build-tools/linux-x86/bin
[ -d $B.x86 ] || cp -a $B $B.x86
for t in make ninja bison flex m4 bzip2 gzip xz; do p=$(which $t) && ln -sfn $p $B/$t; done
# path tools
P=prebuilts/build-tools/path/linux-x86
[ -d $P.x86 ] || cp -a $P $P.x86
for f in $P.x86/*; do n=$(basename $f); s=$(command -v $n 2>/dev/null || true); [ -n "$s" ] && ln -sfn $s $P/$n; done
ln -sfn $(which python2) $P/python2; ln -sfn $(which python2) $P/python2.7; ln -sfn $(which python3) $P/python3; ln -sfn $(which python3) $P/python
echo "remaining x86 ELF files in build-tools bin:"; file -L $B/* | grep "x86-64" | cut -d: -f1 | xargs -n1 basename | tr '\n' ' '; echo
ls /usr/share/bison 2>/dev/null | head -1
