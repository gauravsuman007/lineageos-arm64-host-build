#!/bin/bash
# Moves the build to a NATIVE arm64 VM (no Rosetta): releases the image from the x86 VM, creates `lineage-arm`, installs tools, mounts the image.
set -e
step(){ echo; echo "=== [$1] $2"; }
step 1/6 "Releasing the build image from the old x86 VM"
orb -m lineage sudo sh -c 'swapoff /srv/lineage/lineage-swap 2>/dev/null; sync; umount /srv/lineage' || true
orbctl stop lineage || true
step 2/6 "Creating arm64 Debian 11 machine 'lineage-arm' (native, no Rosetta)"
orbctl list | grep -q "^lineage-arm" || orbctl create -a arm64 debian:bullseye lineage-arm
orb -m lineage-arm uname -m
step 3/6 "Pointing apt at Debian archive (bullseye is EOL)"
orb -m lineage-arm sudo bash -c 'printf "deb http://archive.debian.org/debian bullseye main contrib non-free\ndeb http://archive.debian.org/debian-security bullseye-security main contrib non-free\n" > /etc/apt/sources.list; rm -f /etc/apt/sources.list.d/*; echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/99archive; apt-get update 2>&1 | tail -2'
step 4/6 "Installing native arm64 build tools (git-lfs, repo, JDK11, gcc, clang-11, kernel deps)"
orb -m lineage-arm sudo bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y git git-lfs gnupg flex bison build-essential zip unzip curl wget zlib1g-dev libncurses5-dev libssl-dev libxml2-utils xsltproc python3 python-is-python3 rsync bc lzop imagemagick ccache lz4 liblz4-tool squashfs-tools pngcrush schedtool openjdk-11-jdk-headless e2fsprogs xz-utils file util-linux cpio kmod device-tree-compiler clang-11 lld-11 llvm-11 gcc g++ make ninja-build golang-go libelf-dev 2>&1 | tail -3'
orb -m lineage-arm sudo sh -c 'curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo; chmod a+x /usr/local/bin/repo; git lfs install --system'
step 5/6 "Mounting the sparse ext4 image from the Data drive"
orb -m lineage-arm bash /mnt/mac/Volumes/Data/lineage-build/scripts/mount.sh
step 6/6 "Versions"
orb -m lineage-arm bash -c 'uname -m; gcc --version | head -1; clang-11 --version | head -1; java -version 2>&1 | head -1; go version; git lfs version; nproc; free -g | head -2'
echo SETUP_ARM_DONE
