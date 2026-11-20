# Debugging guide

## A. Build failures

### A.1 Triage loop
1. Never wait for a pass to finish — triage while it runs:
   ```bash
   L=build_a11.log; s=$(grep -n '=== build start' $L | tail -1 | cut -d: -f1)
   tail -n +$s $L | tr '\r' '\n' > /tmp/cur.log
   grep '^FAILED' /tmp/cur.log | cut -c1-200
   grep -a 'error:' /tmp/cur.log | sed 's/^.*error: //' | sort | uniq -c | sort -rn | head
   ```
2. Fix in the tree, restart within ~1 h; ccache + ninja reuse finished work.
3. Re-run a single failing command by copying it from the log (`FAILED:` is followed by the
   command); add `-XDdev` (javac) / `-v` (clang) for detail.
4. A pass that stops at "soong bootstrap failed" is an `Android.bp` error — read the last
   20 log lines.

### A.2 Error catalogue (seen on this host, with fixes)
| Symptom | Cause | Fix |
|---|---|---|
| `clang: unknown argument '-Wno-error'` from cc1as | flags passed to assembler | wrapper skips extra flags for `.s/.S` |
| `-Werror=pointer-to-int-cast` despite `-Wno-error` | clang 11 groups | explicit `-Wno-error=<group>` list |
| duplicate symbols at link | clang 11 `-fno-common` default | `-fcommon` in wrapper |
| `ld.lld: relocation R_AARCH64_… against … libpthread.a` | lld 11 + glibc static | static host links use `/usr/bin/ld.bfd` (absolute path; PATH interposer blocks it otherwise) |
| `--pack-dyn-relocs` unknown | bfd used for Android targets | swap linker only for non-`-linux-android` |
| `aarch64-linux-gnu-ld` not allowed | module asked `-fuse-ld=gold` | wrapper normalizes host `-fuse-ld` to lld |
| `undefined __cfi_slowpath` in host libs | CFI on host | CFI only `ctx.Device()` |
| `siginfo_t`/`struct ucontext` errors (ART) | glibc 2.31 naming | `<signal.h>`, `ucontext_t` |
| `YYSTYPE`/`YYLTYPE` undeclared (packetgen, aidl, hidl) | bison 3.7 vs 3.0.4 | `#define YYSTYPE yy::parser::semantic_type` in `.ll` |
| checkfc prints usage | `char c` unsigned on arm64, `getopt` never returns -1 | `int c` |
| `std::count` in keystore `tuple_size` | template param named `count` | rename to `N` |
| undefined `android_load_sphal_library` / `SetTaskProfiles` | static libutils deps not propagated | add `libprocessgroup`, `libvndksupport` |
| `strip.sh: Too many levels of symbolic links` | self-symlinks in path whitelist | relink `echo true pwd` to `/bin/*` |
| `unzip -D` unsupported | wrong unzip in whitelist | link `/usr/bin/unzip` |
| turbine/javac fail on x86 `ziptime` | x86 prebuilt | `scripts/build_tools.sh` |
| Qualcomm HALs miss `linux/msm_audio.h` | no kernel headers | native `make headers_install` into `KERNEL_OBJ/usr` |
| javac `CompletionFailure: androidx.annotation.NonNull` (Tethering) | core stubs annotate with androidx; `java.base` can't read classpath | `--add-reads java.base=ALL-UNNAMED` |
| metalava silent for 30+ min | default heap (25 % RAM) → GC thrash (`jstat -gcutil`: O≈100 %, FGC climbing) | `-Xmx6g` in `out/soong/host/linux-x86/bin/metalava` (mtime preserved) |
| cpython `stropts.h`, `fnstcw`, `va_list` errors | x86_64 pyconfig on arm64 | `extra/arm64-shim/pyconfig.h` |
| `undefined _PyImport_Inittab`, `openpty` | x86_64-only target blocks | duplicate as `linux_glibc_arm64` |
| `module bcc missing dependencies: libLLVM_android` | LLVM host libs off unless `FORCE_BUILD_LLVM_COMPONENTS` | stub `bcc_strip_attr`, stub saturation filter |
| `cflags: Bad flag -I…` (soong) | raw `-I` not allowed | use `include_dirs` |
| `mv: cannot stat dex/tmp/*` (monkeylib, ANT) | javac produced empty jar (330 B) — **root cause open** | packages removed for v1 |
| Gallery2 `package com.android.gallery3d.common does not exist` | **root cause open** | removed for v1 (wallpaper "My photos" crashes) |
| `PRODUCT_PACKAGES := $(filter-out …)` has no effect | product vars of inherited files are merged later | delete the entry in the defining `.mk` |

### A.3 Resource problems
* VM OOM / swap storm: watch `scripts/memlog.sh` (peak → `mem_peak.txt`); size VM = peak + 20 %.
* Slow passes: check ccache hit rate (`ccache -s`), Mac memory pressure, CPU use ≥ 70 %.
* Long silent step: `ps -eo etime,pcpu,args --sort=-pcpu | head` in the VM; for Java tools
  `jstat -gcutil <pid> 1000 3`.

## B. Device debugging

### B.1 Access
* `adb root` needs **Developer options → Rooted debugging** on this build.
* `adb remount` makes `/system` (incl. `/vendor`) writable for quick experiments; reboot after.
* Logs: `scripts/logwatch.sh` keeps `logs/errors.log` (all E/F) and `logs/events.log`
  (crashes, ANRs, native crashes, watchdog, reboots) across reboots/disconnects.
* Tombstones: `adb root; adb shell ls -t /data/tombstones`.

### B.2 Performance
* `scripts/jankbench.sh <label>` — shade, Settings, app drawer; prints janky % and p90/p99.
  The lock screen must be **None** (scripted swipes on a pattern screen would count as unlock
  attempts) and the screen must stay on (`svc power stayon usb` during runs).
* Clocks during a run: `scaling_cur_freq` (cpu0, cpu2), `/sys/class/kgsl/kgsl-3d0/devfreq/cur_freq`.
* Composition: `dumpsys SurfaceFlinger` → layers should be `DEVICE`, not `CLIENT`.
* Boost path: `logcat | grep "QTI PowerHAL"` — `Failed to acquire lock` = no perf engine.
* Power rc overrides: `init.qcom.power.rc` `on enable-low-power` runs after
  `sys.boot_completed` and overwrites tunables — put defaults there, not in a separate rc.

### B.3 Recovery (TWRP 3.7.0) quirks
* `dd bs=4M` is rejected — use byte counts (`bs=4194304`).
* `adb wait-for-device` never matches `recovery` state — poll `adb devices`.
* Chaining `twrp` commands hangs ("Another threaded action is already running");
  run one, `adb reboot recovery` if stuck. `/tmp` is cleared on reboot.
* `/data` busy for `umount`: `mount -o remount,ro /data` for a consistent raw dump.

### B.4 Known runtime issues in v1
* Wallpaper picker "My photos" crashes (no gallery app) — install any gallery or wait for v2.
* Wallpaper picker RenderThread abort (`drawRenderNode called on a context with no surface!`)
  after the above.
* Benign log noise: `WRITE_DEVICE_CONFIG` denials from GMS, `No UICC` (Wi-Fi-only), OMX
  `UnsupportedSetting` during codec probing.
