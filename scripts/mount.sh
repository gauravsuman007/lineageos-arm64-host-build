#!/bin/bash
# Idempotent: create (once) and mount the sparse ext4 build image that lives on the Data drive.
source /mnt/mac/Volumes/Data/lineage-build/scripts/env.sh
IMG=$DATA/lineage.img
step(){ echo; echo "=== $*"; }
if mountpoint -q /srv/lineage; then echo "already mounted:"; df -h /srv/lineage | tail -1; exit 0; fi
if [ ! -f $IMG ]; then
  step "[1/4] Creating sparse 1200G image on Data (no space used until filled)"
  truncate -s 1200G $IMG
  step "[2/4] Formatting ext4 (lazy init, 0% reserved)"
  sudo mkfs.ext4 -F -m 0 -L lineage -E lazy_itable_init=1,lazy_journal_init=1,nodiscard $IMG
else
  echo "image exists: $(ls -lsh $IMG | awk '{print "on-disk "$1", logical "$6}')"
fi
step "[3/4] Mounting at /srv/lineage"
sudo mkdir -p /srv/lineage
sudo mount -o loop,noatime $IMG /srv/lineage
sudo chown $(id -u):$(id -g) /srv/lineage
mkdir -p $LINEAGE/android $LINEAGE/.ccache
if ! swapon --show | grep -q lineage-swap; then
  step "[4/4] Creating 16G swap file inside the image"
  [ -f $LINEAGE/lineage-swap ] || { sudo fallocate -l 16G $LINEAGE/lineage-swap; sudo chmod 600 $LINEAGE/lineage-swap; sudo mkswap $LINEAGE/lineage-swap; }
  sudo swapon $LINEAGE/lineage-swap
fi
df -h /srv/lineage | tail -1; free -g | head -3
echo MOUNT_DONE
