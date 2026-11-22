# Kernel from source (gts3lwifi, 3.18, awesometic v0.13)

**Compiler matters.** The kernel only boots when built with **GCC 4.9**. Builds with the VM's
host gcc 10 reboot-loop on the Samsung logo before the kernel prints anything (seen twice:
2026-11-17 and 2026-11-22). Two working setups, both verified to boot on the tablet:

| Script | Compiler | Output dir / ccache (separate) |
|---|---|---|
| `scripts/kernel_build_181.sh` | AOSP x86-64 GCC 4.9 (`prebuilts/gcc/.../aarch64-linux-android-4.9`) run through qemu-user (`scripts/setup_x86_loader.sh`) | `kernel-181-out-gcc49`, `ccache-kernel` |
| `scripts/kernel_build_181_native49.sh` | native aarch64 GCC 4.9.4 built from source (`scripts/build_native_gcc49.sh`, ~3 min) | `kernel-181-out-native49`, `ccache-kernel-native49` |

Both keep a persistent output directory plus ccache, print `compiled n/total (%)`, and accept
`--no-patches` (unpatched control build). Then `scripts/install_kernel.sh <Image.gz-dtb>` puts the
result into the device tree so `boot.img` ships it (the binary is deliberately not in `patches/`).

## Patches (`patches/kernel/`, plus `scripts/gpmu_fix.py`)
* `0001-battery-allow-clearing-store_mode.patch` — Samsung `store_mode` could only be set, never
  cleared (needs a reboot). Clearing it re-enables the buck/charging so the ROM charge-limit service
  can drain to the limit (store_mode = run from battery) and then hold (`hmt_ta_charge=0`).
* `gpmu_fix.py` — Adreno GPMU power-level acknowledgement (no more "not acknowledged" flood).

## Flashing safely
Back up `boot` first (`dd` to a file, sha256), flash with `dd bs=1048576`, read back and compare;
restore the same way from TWRP if it does not boot.
