#!/bin/bash
# Lets the arm64 VM run the x86-64 GCC 4.9 from AOSP prebuilts (the compiler the working awesometic kernel was built with).
# qemu-user-static (x86_64 binfmt) + x86-64 libc/libstdc++/zlib in a multiarch sysroot. VM only; nothing on the Mac.
set -e
step(){ echo; echo "=== [$1] $2   ($(date +%H:%M:%S))"; }
step 1/4 "Install qemu-user-static + binfmt"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-user-static binfmt-support
step 2/4 "Enable amd64 multiarch and install x86-64 runtime libs"
sudo dpkg --add-architecture amd64
sudo apt-get update -o Acquire::Languages=none 2>&1 | tail -3
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libc6:amd64 libstdc++6:amd64 zlib1g:amd64 libgmp10:amd64 libmpfr6:amd64 libmpc3:amd64 libisl23:amd64 2>&1 | tail -5 || true
sudo update-binfmts --enable qemu-x86_64 2>&1 | tail -2 || true
step 3/4 "Check binfmt and loader"
ls /proc/sys/fs/binfmt_misc/ | tr '\n' ' '; echo
ls -la /lib64/ld-linux-x86-64.so.2 /usr/lib/x86_64-linux-gnu/libc.so.6
step 4/4 "Run the prebuilt GCC 4.9"
G=/srv/lineage/android/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9
export QEMU_LD_PREFIX=/
ldd $G/libexec/gcc/aarch64-linux-android/4.9.x/cc1 2>&1 | grep -i "not found" || echo "cc1: all libs resolved"
echo 'int main(void){return 0;}' > /tmp/t.c
$G/bin/aarch64-linux-android-gcc -c /tmp/t.c -o /tmp/t.o && file /tmp/t.o && $G/bin/aarch64-linux-android-gcc --version | head -1
echo X86_LOADER_DONE
