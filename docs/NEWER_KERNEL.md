# Is a newer kernel feasible for the SM-T820?  (assessment, 2026-11-22)

Today: Samsung/awesometic **3.18.140** (msm8996 CAF base), built with **GCC 4.9** (see KERNEL.md).

| Option | Feasibility | Notes |
|---|---|---|
| **3.18.x LTS patch-ups** (stay on 3.18) | easy | 3.18.140 is the final upstream 3.18 release; only CAF/Samsung/Android-common backports remain (e.g. schedutil/EAS fixes, security backports). Same GCC 4.9. |
| **CAF msm-4.4** (as used by LG G5/V20 and OnePlus 3 community kernels) | hard, weeks | Samsung-only drivers (battery_v2, touch, sensors, panel DT, sec_debug, Wi-Fi qcacld) must be forward-ported; vendor blobs expect 3.18-era interfaces (kgsl, ion, qseecom). Worth it only for a concrete win (security, EAS). |
| **Mainline 6.x** (`msm8996-mainline`, v6.17 tags) | not with this ROM | No kgsl/Android vendor HAL support; would mean a different userspace (postmarketOS-style, freedreno). |

## Compiler per kernel
* 3.18 (now): **GCC 4.9** — verified; host gcc 10 builds do not boot.
* msm-4.4 (if attempted): start with **GCC 4.9** (same ABI/flags as the 3.18 tree), then try
  **clang 9–11** from AOSP prebuilts (the arm64 wrappers installed by `arm64_clang.sh`:
  clang-r353983c / r365631c / r370808) with GNU binutils; 4.4 trees need `CC_WRAPPER`/LTO off at first.
* Never use the Debian host gcc 10 for these trees without a boot test on a throwaway image.

Verdict: stay on 3.18 for v2.0; revisit 4.4 only if a specific need appears.
