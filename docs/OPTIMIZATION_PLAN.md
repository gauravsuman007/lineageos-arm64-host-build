# Optimization plan — Galaxy Tab S3 (SM-T820, `gts3lwifi`), LineageOS 18.1

Goal: smooth UI and app scrolling (launcher, notification shade, Settings, Spotify-class
apps) with **every change built into the shipped images** (`boot.img`, system image in the
flashable zip). No manual tweaks on the device, no root scripts, no Magisk modules.

This plan is the scope of release **v2 ("performance")**. Release v1 is the first
bootable build; see the device repo's release notes.

---

## 1. Where we are (measured, 2026-11-20)

Benchmark: `scripts/jankbench.sh` (5 rounds × shade pull, Settings open + scroll, app drawer),
plus a Spotify home-feed scroll (12 flings). Metric: `dumpsys gfxinfo` janky-frame % and
frame-time percentiles. 60 Hz panel ⇒ 16.7 ms budget.

| Scenario | Stock v1 | v1 + boost tuning (in device tree, not yet in a release) |
|---|---|---|
| Notification shade (SystemUI) | 17 % janky, p99 44 ms | 9–11 %, p99 ~38 ms |
| Settings | 17 %, p99 97 ms | 8–12 %, p99 ~77 ms |
| Launcher / app drawer | 14 %, p99 38 ms | 4–15 % (noisy) |
| Spotify home scroll | 21 %, p90 38 ms, p99 89 ms | not re-measured |

What the data says:

* **GPU is not the bottleneck.** Adreno 530 with the vendor driver; 90th-percentile GPU
  time 4–9 ms; all layers composited by HWC (`DEVICE`), no client (GLES) composition.
* **The UI/main thread is.** Slow frames are "Slow UI thread" / "deadline missed".
* **Frequency boosting is broken.** Every touch/launch logs
  `QTI PowerHAL: Failed to acquire lock`. The QTI power HAL forwards hints to
  `vendor.qti.hardware.perf@1.0-service`, but the actual perf engine (`libqti-perfd.so`)
  and its XML configs (`/vendor/etc/perf/*.xml`) are **not in the device's blob list**
  (`proprietary-files.txt` ships only the service, `libperfgluelayer.so`,
  `libqti-perfd-client.so`, `libqti-util.so`). So no interaction/launch boost ever happens.
* The kernel's own fallback boost was configured weakly in `init.qcom.power.rc`
  (1.32 GHz for **40 ms**), which is shorter than any animation.
* Spotify runs its main thread on the big cores (26/30 samples on cpu2/3) at ~2.0 GHz
  average and is still slow ⇒ part of the cost is the app itself on a 2016 SoC; the
  realistic target is removing the *ramp-up* stalls and the long-tail (p99) frames.
* System apps are **not dex-preopted**: the build used `WITH_DEXPREOPT=false`
  (workaround from the arm64-host bring-up). Apps start in interpreter/JIT until the
  idle background dexopt job runs, which costs first-launch and early scrolling smoothness.

## 2. Workstreams

### WS1 — Working interaction/launch boosts (the "Qualcomm boost") — highest impact

Two ways to get Qualcomm-style boosts. **Recommendation: Option B**, keep A as fallback.

#### Option A — complete the proprietary QTI perf stack
1. Source `libqti-perfd.so` (32/64-bit) and the perf configs from the *same* OnePlus 3/3T
   PKQ1.181203.001 (Android 9, msm8996) vendor image the other perf blobs come from, so ABI
   matches `vendor.qti.hardware.perf@1.0-service` (sha1 `7a38f7ef…`).
2. Add to `proprietary-files.txt` with pinned sha1s; re-run `extract-files.sh`/
   `setup-makefiles.sh`; add `vendor/etc/perf/{perfboostsconfig,targetconfig,perfconfigstore,commonresourceconfigs,targetresourceconfigs}.xml`.
3. Adapt `targetresourceconfigs.xml` to this kernel's nodes (3.18 + EAS/WALT,
   `blu_schedutil`, `cpu_boost`, `msm_performance` if present) — opcodes that point at
   missing nodes make every lock fail again.
4. SELinux: label `/vendor/bin/hw/vendor.qti.hardware.perf@1.0-service` data/sockets
   (`vendor_perfd`), allow sysfs writes.
* Pros: matches what Qualcomm devices ship. Cons: opaque blob, config is trial-and-error,
  provenance/licensing of an extra blob, hard to debug.

#### Option B — open-source AIDL power HAL on `libperfmgr` (recommended)
`hardware/google/pixel/power-libperfmgr` is already in the tree. It implements
`android.hardware.power.IPower` (AIDL) and turns hints into timed sysfs writes described in
a `powerhint.json`. Everything is source-built ⇒ ships in the system/vendor image.

Steps:
1. **Device makefile** (`gts3l.mk`): replace `android.hardware.power-service-qti` and
   `vendor.qti.hardware.perf@1.0-service` with `android.hardware.power-service.pixel-libperfmgr`
   (Lineage name may be `android.hardware.power-service.lineage-libperfmgr` — check the
   `Android.bp` in the tree); keep `vendor.lineage.power` features (tap-to-wake not
   applicable) only if implemented by the new HAL.
2. **`powerhint.json`** in `device/samsung/gts3l-common/configs/powerhint.json` →
   `$(TARGET_COPY_OUT_VENDOR)/etc/powerhint.json`. Nodes (all verified to exist on the device):

   | Node | Path | Default | Boost value |
   |---|---|---|---|
   | CPU little min | `/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq` | 307200 | 1036800 (interaction), 1593600 (launch) |
   | CPU big min | `/sys/devices/system/cpu/cpu2/cpufreq/scaling_min_freq` | 307200 | 1248000 (interaction), 2150400 (launch) |
   | Top-app stune | `/dev/stune/top-app/schedtune.boost` | 20 | 40 (interaction), 60 (launch) |
   | GPU min freq | `/sys/class/kgsl/kgsl-3d0/devfreq/min_freq` | 133000000 | 315000000 (interaction / expensive rendering) |
   | GPU idle timer | `/sys/class/kgsl/kgsl-3d0/idle_timer` | (read) | longer during interaction |

   Actions:
   * `INTERACTION` (touch/scroll/fling; duration from framework, cap 2000 ms) → CPU mins + stune + GPU min.
   * `LAUNCH` (app start, 5 s cap) → max CPU on both clusters, stune 60.
   * `EXPENSIVE_RENDERING` → GPU min 315–510 MHz.
   * `DISPLAY_UPDATE_IMMINENT`, `AUDIO_LAUNCH`, `CAMERA_LAUNCH` → short CPU boost.
   * `LOW_POWER` / Battery saver → cap big cluster to 1.4 GHz.
3. **Keep the kernel input boost as a floor** (already in `init.qcom.power.rc`:
   `0:1324800 2:1555200` for 500 ms, stune 20). libperfmgr covers the *duration* of
   scrolls/flings, which the 500 ms input boost cannot.
4. **SELinux** (`sepolicy/vendor/hal_power_default.te`): allow writing
   `sysfs_devices_system_cpu`, `sysfs_kgsl`, `cgroup` (stune) and reading the JSON.
   Today SELinux is permissive via the kernel cmdline; write the rules now so WS6 can flip
   to enforcing.
5. **Validation**: `dumpsys android.hardware.power.IPower/default` shows hint counts;
   watch `scaling_min_freq` while scrolling; jankbench + Spotify bench; idle battery drain
   (8 h screen-off, Wi-Fi on) must not regress more than ~10 %.

### WS2 — Kernel built from source and shipped in `boot.img`
Today `boot.img` carries awesometic's prebuilt v0.13 `Image.gz-dtb` (sha256 `f027448b…`).
1. Build the same source (`kernel/samsung/msm8996`, commit `f48aec90`, branch
   `lineage-18.1-caf`) natively — `scripts/kernel_build.sh` already does this for the
   20.0 branch; point it at the 18.1 tree.
2. Apply the **GPMU acknowledgement fix** (`scripts/gpmu_fix.py`, Adreno power-level
   changes were never confirmed, flooding dmesg and leaving the GPU at the wrong voltage
   level).
3. Kernel-side boost improvements:
   * `cpu_boost`: boost on *every* input event burst, not only the first (check
     `input_boost_ms` re-arm logic), and add a fling-length boost via `dynamic_stune_boost`.
   * `blu_schedutil`: default `up_rate_limit_us=0`, `down_rate_limit_us=40000` in code so
     the rc file is not the only source of truth.
   * `msm-adreno-tz`: lower the up-threshold so the GPU leaves 133 MHz faster.
4. Ship it: either build in-tree (`TARGET_KERNEL_SOURCE` + host toolchain fix for the
   x86-only kernel make path) or keep `TARGET_PREBUILT_KERNEL` but **produce that file from
   our own reproducible build** and record its hash in the release notes.

### WS3 — Ahead-of-time compilation in the image
1. Make host `dex2oat` work on the arm64 build host (ART host tools already compile;
   remove the `WITH_DEXPREOPT=false` workaround from `build_a11.sh`).
2. Preopt at least `SystemUI`, `Launcher3/Trebuchet`, `Settings`, `framework`, with
   `PRODUCT_DEXPREOPT_SPEED_APPS += SystemUI Launcher3QuickStep Settings`.
3. Ship boot image profiles (`PRODUCT_USE_PROFILE_FOR_BOOT_IMAGE := true`).
* Expected: faster first boot, no JIT warm-up jank, smaller p99.

### WS4 — Memory and I/O
1. Measure first: `dumpsys meminfo`, `/proc/pressure/*` (not on 3.18 — use
   `vmstat`), LMK kills (`lowmemorykiller: Error writing /proc/*/oom_score_adj` seen in logs).
2. zram: size 1–1.5 GB, `lz4`, `swappiness` 100; move to userspace `lmkd` with
   `ro.lmk.use_minfree_levels=true` if in-kernel LMK is fighting `lmkd`.
3. I/O: `read_ahead_kb` 128 for mmcblk0, `cfq`→`noop`/`bfq` if available; test app-start
   time and scroll while Play Store installs.

### WS5 — GPU follow-ups
* Confirm `msm-adreno-tz` governor behaviour during scroll (`cur_freq` sampling showed
  137–169 MHz average); tune via power HAL hints (WS1) rather than static high minimums.
* Keep HWC composition; check that no layer falls back to GLES when blur/rounded corners
  appear in apps.

### WS6 — Correctness and regressions found in v1 (ship in v2 too)
1. **Gallery2**: fix `package com.android.gallery3d.common does not exist` (missing
   source dir / glob) and restore it — the wallpaper picker crashes on "My photos"
   (`ActivityNotFoundException ACTION_PICK image/*`) without a gallery.
2. **Empty jars** (`monkeylib`, ANT radio): find why javac emitted 330-byte jars —
   possible toolchain bug that could silently affect other modules.
3. **RenderScript**: either build LLVM host components natively
   (`FORCE_BUILD_LLVM_COMPONENTS=true`, ~45–60 min) and restore real `bcc`/`llvm-rs-cc`,
   or keep it stubbed and document.
4. **SELinux enforcing** (drop `androidboot.selinux=permissive`), **data encryption**
   (FBE flags in fstab), **release keys** instead of test-keys.
5. `adb root` / `ro.adb.secure=0` are debug conveniences — keep for the "debug" variant,
   disable for the "daily" variant.

## 3. Measurement protocol (every change)
1. Tablet on the home screen, **lock screen set to None** (the benchmark injects input;
   never script through a secure lock screen), screen kept on only during the run
   (`svc power stayon usb`, then `svc power stayon false`).
2. `scripts/jankbench.sh <label>` × 3, Spotify scroll × 3; record median janky %, p90, p99.
3. Sample `scaling_cur_freq` (both clusters) and `kgsl-3d0/devfreq/cur_freq` during runs.
4. `scripts/logwatch.sh` running: no new crashes/ANRs/tombstones.
5. Battery: 8 h idle drain with Wi-Fi on, compare to v1.

## 4. Acceptance criteria for v2
* Launcher/shade/Settings: **≤ 5 % janky**, p99 ≤ 32 ms (median of 3 runs).
* Spotify home scroll: **≤ 10 % janky**, p99 ≤ 50 ms.
* No `Failed to acquire lock`; power HAL hints visible in `dumpsys`.
* Boots to home ≤ 45 s; no new crashes during a 30-min soak.
* Idle drain within +10 % of v1.
* Everything above produced by `build_a11.sh` from the patches in this repo — the
  device needs only: flash zip (+ optional GApps).

## 5. Order of work
1. WS1 Option B (power HAL + powerhint.json + sepolicy) → measure.
2. WS3 dexpreopt → measure.
3. WS2 kernel from source + GPMU fix + governor defaults → measure.
4. WS4 memory/I/O → measure.
5. WS6 regressions, then release v2.

## 6. Rollback
* Every flash is preceded by `scripts/backup_tablet.sh` (raw partitions + GPT, sha256
  verified) and is undone with `scripts/restore_from_twrp.sh` over adb — no buttons.
* The v1 zip stays attached to its release; re-flashing it restores v1.
