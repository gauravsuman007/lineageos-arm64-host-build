# Build environment for LineageOS 18.1 / gts3lwifi (inside the `lineage` OrbStack VM)
export DATA=/mnt/mac/Volumes/Data/lineage-build
export LINEAGE=/srv/lineage
export ANDROID_BUILD_TOP=$LINEAGE/android
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_DIR=$LINEAGE/.ccache
export CCACHE_COMPRESS=1
export CCACHE_MAXSIZE=120G
export LC_ALL=C
export PATH=/usr/local/bin:$PATH
