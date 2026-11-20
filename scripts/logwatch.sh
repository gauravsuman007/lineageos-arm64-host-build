#!/bin/bash
# Continuously capture tablet error logs; survives reboots/disconnects.
# Full error log: /Volumes/Data/lineage-build/logs/errors.log
# Important events (crashes, ANRs, native crashes, watchdog, reboots): events.log
D=/Volumes/Data/lineage-build/logs; mkdir -p "$D"
while true; do
  adb wait-for-device 2>/dev/null
  echo "=== $(date '+%F %T') connected ($(adb shell getprop ro.build.display.id | tr -d '\r'))" | tee -a "$D/events.log"
  adb logcat -v time -b main,system,crash,events '*:E' 2>/dev/null | tee -a "$D/errors.log" |
    grep --line-buffered -E "FATAL EXCEPTION|AndroidRuntime|ANR in|Fatal signal|\*\*\* \*\*\* \*\*\*|Watchdog|system_server.*died|am_crash|am_anr|tombstone|Rescue|beginning of crash|Process: " |
    tee -a "$D/events.log"
  echo "=== $(date '+%F %T') disconnected" | tee -a "$D/events.log"
  sleep 3
done
