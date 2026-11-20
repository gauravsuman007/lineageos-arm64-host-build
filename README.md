# Building LineageOS 18.1 (Android 11) natively on an arm64 host

This repository documents and automates building **LineageOS 18.1 / AOSP 11** on an
**arm64 Linux host** (an OrbStack Debian 11 VM on an Apple-silicon Mac) **without Rosetta or
any x86 emulation**. AOSP 11 officially supports only x86-64 Linux build hosts; this setup
replaces every x86 host prebuilt with a native arm64 equivalent and patches the sources
that break on an arm64/glibc host.

It was used to produce the first Android 11 build for the Samsung Galaxy Tab S3
(SM-T820, `gts3lwifi`) — images and release notes live in the companion repo
[`gts3lwifi-lineage-18.1`](../gts3lwifi-lineage-18.1).

* [docs/DEBUGGING.md](docs/DEBUGGING.md) — build-failure catalogue, device debugging, rescue.
* [docs/OPTIMIZATION_PLAN.md](docs/OPTIMIZATION_PLAN.md) — plan for the performance release.

---

## 1. Host layout

| Item | Value |
|---|---|
| Mac | Apple silicon, 8 cores |
| VM | OrbStack machine `lineage-arm`, Debian 11 (bullseye) **arm64**, 7 vCPU |
| VM RAM | 11 GB (`orb config set memory_mib 11264`) — peak observed 9.4 GB during Soong analysis; 20 % headroom |
| Build tree | sparse ext4 image `lineage.img` on an external drive, loop-mounted at `/srv/lineage` |
| ccache | `/srv/lineage/ccache`, 80 GB max, `CCACHE_COMPILERCHECK=string:a11-arm64-wrapper-v1` |
| Disk used | ~250 GB tree + out, ~20 GB ccache |

> **After every `orb stop/start` or Mac reboot, re-run `scripts/mount.sh`** — the loop mount
> does not survive and `/srv/lineage` then looks empty (nothing is lost).

Paths in the scripts assume the external drive is `/Volumes/Data` and the work directory is
`/Volumes/Data/lineage-build` (visible inside the VM as `/mnt/mac/Volumes/Data/...`).
Adjust `scripts/env.sh` if yours differ.

## 2. Step by step

### 2.1 Create the VM and install tools
```bash
bash scripts/setup_arm.sh
```
Creates `lineage-arm` (arm64 Debian 11), points apt at `archive.debian.org`, installs the
toolchain (clang/lld/llvm 11, OpenJDK 11, Go, bison, flex, git-lfs, repo …), and mounts the
build image (`scripts/mount.sh`). Then set the VM memory and keep the Mac awake for long jobs:
```bash
orb config set memory_mib 11264
caffeinate -dimsu &
```

### 2.2 Sync the sources
```bash
orb -m lineage-arm bash /mnt/mac/Volumes/Data/lineage-build/scripts/sync.sh
```
`repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --depth=1` plus
`scripts/local_manifest.xml` (awesometic's gts3l device, common, kernel and vendor trees).
`pinned-revisions.txt` lists the exact commit of all 869 projects used for release v1.

### 2.3 Make the host prebuilts native (arm64)
Run in order inside the VM (each script is idempotent and keeps the originals as `*.x86`):

| Script | What it does |
|---|---|
| `scripts/arm64_swap_prebuilts.sh` | Go and JDK 11 → system arm64 versions; `make ninja bison flex m4 bzip2 gzip xz` and the `path/` tool whitelist → system binaries |
| `scripts/arm64_clang.sh` | AOSP clang r383902/b/b1: keep headers + runtime libs, replace executables with Debian clang-11/lld/llvm-11; composite resource dir |
| `scripts/arm64_tools2.sh` | bison wrapper (own skeletons), gcc-4.9 binutils → llvm tools, aarch64 compiler-rt, native `acp` |
| `scripts/arm64_tools3.sh` | GNU as/ld for the gcc-4.9 dirs, clang-tidy no-op, `.fpu neon` fix for armv7 asm |
| `extra/clang-wrapper.tmpl` | **Final clang wrapper** — copy over `bin/clang` and `bin/clang++` of all three clang dirs (see §3) |
| `scripts/build_tools.sh` | builds `ziptime zipalign ziptool aidl hidl-lint bpfmt soong_zip zip2zip` natively and links them over the x86 prebuilts |
| `extra/versioner-stub.sh` | stand-in for the x86 `versioner` (copies headers) → `prebuilts/clang-tools/linux-x86/bin/versioner` |
| `extra/arm64-shim/` | → `external/python/arm64-shim/` (pyconfig + `stropts.h` for the cpython host interpreters) |

Path-tool fixes that the scripts do not cover yet (do them by hand once):
```bash
cd prebuilts/build-tools/path/linux-x86
ln -sfn /bin/echo echo; ln -sfn /bin/true true; ln -sfn /bin/pwd pwd; ln -sfn /usr/bin/unzip unzip
```

### 2.4 Apply the source patches
```bash
orb -m lineage-arm bash /mnt/mac/Volumes/Data/lineage-build/scripts/apply_patches.sh
```
Applies `patches/<project>.patch` (one per git project, 29 projects). Summary of what they
change is in §3 and in `docs/DEBUGGING.md`.

### 2.5 Build
```bash
orb -m lineage-arm bash /mnt/mac/Volumes/Data/lineage-build/scripts/build_a11.sh   # = m -j7 bacon
```
Environment set by the script:
`USE_CCACHE=1 CCACHE_COMPILERCHECK=string:a11-arm64-wrapper-v1 ALLOW_MISSING_DEPENDENCIES=true
BUILD_HOST_64bit=1 WITH_DEXPREOPT=false NINJA_ARGS="-k 0"` and `breakfast gts3lwifi userdebug`.
`-k 0` keeps ninja going past failures so one pass shows every broken module.
Re-running resumes; ccache makes a full rebuild ~1 h, an incremental pass minutes.
Log: `build_a11.log` (each pass starts with `=== build start`). Progress view:
```bash
tail -c 4000 build_a11.log | tr -s '\015' '\012' | grep -E '^.[ 0-9]+%' | tail -3
```
Output: `out/target/product/gts3lwifi/lineage-18.1-<date>-UNOFFICIAL-gts3lwifi.zip`.

### 2.6 Flash without touching the tablet's buttons
Requirements: TWRP in `recovery`, USB debugging on.
```bash
bash scripts/backup_tablet.sh /Volumes/Data/lineage-build/tablet-backup     # every partition + GPT, sha256-verified
adb reboot recovery
adb shell 'mount -o remount,ro /data'; bash scripts/backup_tablet.sh <dir> userdata
adb push lineage-18.1-*.zip /tmp/rom.zip
adb shell twrp format data          # only when changing Android version
adb reboot recovery                 # TWRP's command queue hangs if commands are chained
adb push lineage-18.1-*.zip /tmp/rom.zip
adb shell twrp install /tmp/rom.zip
adb reboot
```
Rescue: `adb reboot recovery` then `scripts/restore_from_twrp.sh [--with-data]`.
The build sets `ro.adb.secure=0` and `persist.sys.usb.config=adb`, so adb is reachable early
during boot even in a boot loop.

GApps (optional, not part of the images): MindTheGapps 11 arm64. TWRP crashed (watchdog)
running `twrp install` for it; running its installer directly works:
```bash
adb push MindTheGapps-11.0.0-arm64-*.zip /tmp/gapps.zip
adb shell 'cd /tmp && mkdir g && cd g && unzip -o ../gapps.zip META-INF/com/google/android/update-binary &&
           umount /system_root; sh META-INF/com/google/android/update-binary 3 1 /tmp/gapps.zip'
adb shell twrp format data    # GApps after first boot needs a clean /data
```

## 3. What had to change for an arm64 host (summary)

**Toolchain**
* Clang wrapper (`extra/clang-wrapper.tmpl`): drops `-msoft-float` (Debian clang disables
  NEON with it), adds `-fcommon` and `-Wno-error[=…]` for clang-11 strictness, skips those
  flags for assembler inputs, normalizes host links to `lld`, uses absolute
  `/usr/bin/ld.bfd` for static host links (lld 11 cannot link glibc's static libpthread).
* `CCACHE_COMPILERCHECK=string:…` — otherwise every wrapper edit invalidates the cache.
* Native builds of host tools that were x86-only prebuilts; `versioner` stub; path whitelist fixes.

**Soong / build**
* `build/soong/cc/config/arm64_linux_host.go`: `-DPAGE_SIZE=4096`, python shim include.
* CFI only for device modules (`sanitize.go`, `library.go`) — host libs referenced `__cfi_slowpath`.
* Kernel UAPI headers generated with native `make headers_install` into `KERNEL_OBJ/usr`.

**Sources** (arm64 host = unsigned `char`, glibc 2.31, bison 3.7, JDK 11.0.32)
* `checkfc.c` `char c` → `int c` (getopt loop never ended).
* ART: `ucontext_t`, `<signal.h>`; libcutils `gettid` guard; keystore template param `count`→`N`.
* `YYSTYPE`/`YYLTYPE` defines in the bluetooth packetgen, aidl and hidl lexers.
* Missing shared deps (`libprocessgroup`, `libvndksupport`) for gsid, remount, incremental, wificond.
* Tethering: `javacflags: ["--add-reads java.base=ALL-UNNAMED"]` (core stubs carry
  `androidx.annotation.NonNull`; `java.base` cannot read the classpath).
* cpython 2/3 host: arm64 target blocks, pyconfig shim (`VA_LIST_IS_ARRAY`, x87 asm, `SOABI`).
* RenderScript: `bcc_strip_attr` → shell stub, saturation filter stubbed, `bcc`/`ld.mc` dropped.
* Packages removed: Gallery2, monkey, AntHalService/ANT radio library (see DEBUGGING.md).

**Device**
* `init.qcom.power.rc`: stronger kernel input boost (see the optimization plan).

## 4. Known limitations of the v1 output
Unencrypted `/data`, SELinux permissive (kernel cmdline), test-keys, no Gallery2,
RenderScript compile stubbed, Qualcomm perf boosts non-functional (fix planned).

## 5. Repository layout
```
scripts/        setup, sync, toolchain, build, backup/restore, benchmark, log watching
patches/        one patch per git project of the LineageOS tree
extra/          files outside git projects (clang wrapper, python shim, versioner stub)
pinned-revisions.txt   project → commit used for release v1
docs/           debugging guide, optimization plan
```
