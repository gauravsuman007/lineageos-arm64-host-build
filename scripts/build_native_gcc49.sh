#!/bin/bash
# Build a NATIVE aarch64 GCC 4.9.4 (C only) on the arm64 VM, to compile the kernel without x86 emulation.
# Installs to /srv/lineage/gcc49-native -- separate from the AOSP x86 GCC 4.9 + qemu setup (kept untouched).
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
P=/srv/lineage/gcc49-native; SRC=$LINEAGE/gcc49-src; BLD=$LINEAGE/gcc49-build; LOG=$DATA/logs/gcc49-native.log
URL=https://ftp.gnu.org/gnu/gcc/gcc-4.9.4; TB=gcc-4.9.4.tar.bz2
step(){ echo; echo "=== [$1] $2   ($(date +%H:%M:%S))"; }
step 1/6 "Download $TB (~100 MB) from $URL + checksum"
mkdir -p $SRC && cd $SRC
[ -f $TB ] || curl -fL --progress-bar -o $TB $URL/$TB
curl -fsSL -o sha512.sum https://sourceware.org/pub/gcc/releases/gcc-4.9.4/sha512.sum   # GNU ftp has no checksum file; sourceware publishes it
grep " $TB\$" sha512.sum | sha512sum -c - || { echo "CHECKSUM FAILED"; exit 1; }
step 2/6 "Extract + build deps (Debian packages: gmp, mpfr, mpc)"
dpkg -s libgmp-dev libmpfr-dev libmpc-dev >/dev/null 2>&1 || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libgmp-dev libmpfr-dev libmpc-dev texinfo >/dev/null 2>&1
[ -d gcc-4.9.4 ] || tar xf $TB
# glibc >= 2.26 removed 'struct ucontext' (libgcc unwinder); use the typedef
sed -i 's/struct ucontext/ucontext_t/g' gcc-4.9.4/libgcc/config/aarch64/linux-unwind.h
step 3/6 "Configure (C only, no bootstrap, host gcc 10 workarounds)"
mkdir -p $BLD && cd $BLD
if [ ! -f Makefile ]; then
  CC="gcc -fcommon" CXX="g++ -std=gnu++98 -fpermissive -fcommon" CFLAGS="-O2 -fcommon -w" CXXFLAGS="-O2 -std=gnu++98 -fpermissive -fcommon -w" \
  $SRC/gcc-4.9.4/configure --prefix=$P --enable-languages=c --disable-multilib --disable-bootstrap --disable-nls \
    --disable-libsanitizer --disable-libgomp --disable-libitm --disable-libquadmath --disable-libssp --disable-libatomic --disable-libcilkrts \
    --with-system-zlib --disable-werror > $LOG.configure 2>&1 || { tail -20 $LOG.configure; echo CONFIGURE_FAILED; exit 1; }
fi
step 4/6 "Compile (-j7). Progress = compile steps done (total is approximate, ~1500 for C-only)"
T=1500
make -j7 all-gcc all-target-libgcc 2>&1 | tee $LOG | awk -v T=$T 'BEGIN{t0=systime()}
  /(gcc|g\+\+|cc1|xgcc).* -c |libtool: compile|^(gcc|g\+\+) /{n++; if (n%50==0) printf "%s  compiled ~%d/%d (%d%%)  %ds\n", strftime("%H:%M:%S"), n, T, 100*n/T, systime()-t0; fflush()}
  /error:|\*\*\*|Error [0-9]/{print strftime("%H:%M:%S"), $0; fflush()}'
[ ${PIPESTATUS[0]} = 0 ] || { echo "GCC_BUILD_FAILED (see $LOG)"; tail -20 $LOG; exit 1; }
step 5/6 "Install to $P"
make install-gcc install-target-libgcc >/dev/null 2>&1 || make install-gcc 2>&1 | tail -3
step 6/6 "Self-test"
export PATH=$P/bin:$PATH
ls $P/bin | head; G=$(ls $P/bin/*-gcc | head -1); echo "using $G"
$G --version | head -1
echo 'int main(void){return 0;}' > /tmp/t49.c && $G /tmp/t49.c -o /tmp/t49 && /tmp/t49 && echo "native gcc 4.9 compiles+runs OK"
echo NATIVE_GCC49_DONE
