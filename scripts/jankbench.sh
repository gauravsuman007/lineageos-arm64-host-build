#!/bin/bash
# Repeatable UI-animation jank benchmark over adb. Usage: jankbench.sh <label>
L=${1:-run}
adb shell '
input keyevent KEYCODE_WAKEUP; sleep 1; wm dismiss-keyguard; sleep 1
input keyevent KEYCODE_HOME; sleep 2
for p in com.android.systemui com.android.settings com.android.launcher3; do dumpsys gfxinfo $p reset >/dev/null; done
for i in 1 2 3 4 5; do
 input swipe 768 5 768 1500 250; sleep 1.2; input keyevent KEYCODE_BACK; sleep 1
 am start -W -n com.android.settings/.Settings >/dev/null; sleep 1.5; input swipe 768 1700 768 300 250; sleep 1; input keyevent KEYCODE_HOME; sleep 1.5
 input swipe 768 1700 768 400 250; sleep 1.2; input keyevent KEYCODE_BACK; sleep 1
done
for p in com.android.systemui com.android.settings com.android.launcher3; do
 dumpsys gfxinfo $p | awk -v p=$p "/Total frames/{t=\$4} /Janky frames/{j=\$4\" \"\$3} /^90th percentile/{a=\$3} /^99th percentile/{b=\$3} END{printf \"%-24s frames=%s janky=%s p90=%s p99=%s\n\", p, t, j, a, b}"
done' | sed "s/^/[$L] /"
