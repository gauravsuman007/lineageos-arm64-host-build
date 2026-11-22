#!/bin/bash
# Interleaved kernel comparison on the tablet: A,B,C,A,B,C. Only flashes boot images that already booted on this tablet.
# A = native GCC 4.9.4 (patched)   B = AOSP GCC 4.9 via qemu (patched)   C = awesometic prebuilt (v1 kernel)
# Each phase: flash (verified) -> reboot -> boot time -> settle -> ROUNDS x scripts/jankbench.sh -> metrics. CSV + live progress.
export ANDROID_SERIAL=b745f4952147b2ac
O=/Volumes/Data/lineage-build/kernel-output; R=/Users/hellonfire/Coding/LineageOS/repos/lineageos-arm64-host-build
CSV=/Volumes/Data/lineage-build/logs/kernel_compare.csv; ROUNDS=${ROUNDS:-4}; SETTLE=${SETTLE:-300}
IMG(){ case $1 in A) echo boot-native49-patched.img;; B) echo boot-gcc49-patched.img;; C) echo boot-pre-ws2.img;; esac; }
SHA(){ case $1 in A) echo 85c0e730aaca8256;; B) echo 9287aebaa45430b6;; C) echo 60cf667fdceb0f05;; esac; }
NAME(){ case $1 in A) echo native-gcc4.9.4;; B) echo emulated-gcc4.9;; C) echo awesometic-prebuilt;; esac; }
# (macOS bash 3.2: no associative arrays)
ORDER=${ORDER:-"A B C A B C"}
ts(){ date +%H:%M:%S; }
say(){ echo "$(ts)  $*"; }
echo "phase,kernel,round,app,frames,janky_pct,p90_ms,p99_ms,therm_c,batt_c" > $CSV
echo "phase,kernel,boot_s,gpmu_errors,version" > ${CSV%.csv}_phases.csv
TZ=$(adb shell 'for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type) $z"; done' | tr -d '\r' | awk '$1=="msm_therm"{print $2; exit}')
say "thermal zone: ${TZ:-none}"
flash(){ k=$1; f=$O/$(IMG $k)
  [ "$(shasum -a 256 $f | cut -c1-16)" = "$(SHA $k)" ] || { say "ABORT: image checksum mismatch for $k"; exit 2; }
  adb root >/dev/null 2>&1; sleep 2
  cur=$(adb shell "dd if=/dev/block/by-name/boot bs=1048576 count=76 2>/dev/null | head -c 79691776 | sha256sum" | cut -c1-16)
  if [ "$cur" = "$(SHA $k)" ]; then say "boot partition already holds $k"; return; fi
  adb push $f /sdcard/cmp.img >/dev/null; r=$(adb shell sha256sum /sdcard/cmp.img | cut -c1-16)
  [ "$r" = "$(SHA $k)" ] || { say "ABORT: push mismatch"; exit 2; }
  adb shell "dd if=/sdcard/cmp.img of=/dev/block/by-name/boot bs=1048576 2>/dev/null; rm /sdcard/cmp.img"
  back=$(adb shell "dd if=/dev/block/by-name/boot bs=1048576 count=76 2>/dev/null | head -c 79691776 | sha256sum" | cut -c1-16)
  [ "$back" = "$(SHA $k)" ] || { say "ABORT: readback mismatch ($back)"; exit 2; }
  say "flashed $k ($(NAME $k)), readback verified"; }
n=0; tot=$(echo $ORDER | wc -w | tr -d " ")
for k in $ORDER; do n=$((n+1)); P="$n/$tot $k"
  say "=== PHASE $P  $(NAME $k)"
  flash $k
  t0=$(date +%s); adb reboot; sleep 25
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; [ $(( $(date +%s)-t0 )) -gt 300 ] && { say "ABORT: not booted after 300 s with kernel $k - needs recovery (button combo). Nothing further flashed."; exit 3; }; done
  bt=$(( $(date +%s)-t0 )); say "booted in ${bt}s"
  adb root >/dev/null 2>&1; sleep 3
  ver=$(adb shell cat /proc/version | tr -d '\r' | sed 's/.*(gcc version \([^)]*\)).*/\1/' | cut -c1-30)
  say "settling ${SETTLE}s (background work after boot)"; sleep $SETTLE
  adb shell "svc power stayon usb; input keyevent KEYCODE_WAKEUP" >/dev/null
  for r in $(seq 1 $ROUNDS); do
    out=$(bash $R/scripts/jankbench.sh x | tr -d '\r')
    th=$(adb shell "cat $TZ/temp 2>/dev/null" | tr -d '\r'); bt2=$(adb shell cat /sys/class/power_supply/battery/temp | tr -d '\r')
    echo "$out" | awk -v P="$n" -v K="$k" -v R="$r" -v T="$th" -v B="$bt2" '{app=$2; f=$3; sub("frames=","",f); j=$4; sub("janky=\\(","",j); sub("%\\)","",j); p9=$6; sub("p90=","",p9); sub("ms","",p9); p99=$7; sub("p99=","",p99); sub("ms","",p99); printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",P,K,R,app,f,j,p9,p99,T,B}' >> $CSV
    s=$(echo "$out" | awk '{j=$4; sub("janky=\\(","",j); sub("%\\)","",j); printf "%s %s%%  ", substr($2,13), j}')
    say "phase $P round $r/$ROUNDS: $s therm=$th batt=$bt2"
    sleep 20
  done
  g=$(adb shell "dmesg | grep -c 'GPMU powerlevel'" | tr -d '\r'); echo "$n,$k,$bt,$g,$ver" >> ${CSV%.csv}_phases.csv
  say "phase $n done: gpmu_errors=$g compiler=$ver"
  adb shell "svc power stayon false" >/dev/null
done
say "CAMPAIGN_DONE"
