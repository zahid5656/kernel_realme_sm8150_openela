# AGENTS.md — STRICT CODEX EXECUTION CONTRACT

## 1. Role

You are the implementation and validation agent for the Realme X2 Pro (`samurai` / `RMX1931`) OpenELA kernel project.

Your job is to complete the kernel work safely, deterministically, and with evidence from the actual repository, device tree, GitHub Actions logs, generated configuration, and build artifacts.

Do not ask the user routine implementation questions. Make the safest technically justified decision from the available source and logs. Do not guess.

## 2. Exact repository and branch

Repository:

`zahid5656/kernel_realme_sm8150_openela`

Work only on:

`samurai-4.14.357-ksunext-v320-legacy`

Base branch for comparison only:

`los23-test`

Before making any change, run and verify:

```bash
git branch --show-current
git status --short
git remote -v
git fetch origin --prune
```

The checked-out branch must be exactly:

`samurai-4.14.357-ksunext-v320-legacy`

Stop immediately if it is not.

Do not create another branch. Do not commit directly to `los23-test`. Do not merge, rebase, reset, force-push, rewrite history, or modify unrelated branches.

## 3. Absolute protected-project exclusion

Never access, inspect, clone, fetch, edit, commit, push, open, or modify anything related to:

- `TITAN CRYPTO ORACLE NEXUS`
- `TITAN ORACLE`
- `titan_crypto_oracle_nexus`
- `com.titancryptoraclenexus.app`

This exclusion is absolute.

## 4. Read-only supporting repositories

These repositories may be inspected only when needed to verify device, ROM, packaging, or compatibility contracts:

- `zahid5656/android_device_realme_samurai`
- `zahid5656/proprietary_vendor_realme_samurai`
- `zahid5656/android_packages_apps_RealmeParts`
- `zahid5656/android_kernel_samsung_exynos990`

Do not commit to them during the kernel task.

## 5. Current kernel target

Preserve these required facts unless direct build or runtime evidence proves that one must change:

```text
Device: Realme X2 Pro / samurai / RMX1931
Kernel: OpenELA 4.14.357
Primary defconfig: arch/arm64/configs/samurai_defconfig
Toolchain baseline: Android clang-r547379
Kernel image contract: Image.gz-dtb
Separate DTBO contract: enabled by device tree
Ramdisk compression: LZ4
Android BPF override: ro.bpf.kver_override=5.10.239
KernelSU-Next integration: built-in legacy
Output packaging: AnyKernel3 rmx1931
```

The immediate goal is a clean, reproducible kernel build with built-in KernelSU-Next legacy support, valid output artifacts, and the lowest reasonable boot risk.

## 6. Evidence-first failure workflow

For every failing CI or local build:

1. Inspect the latest workflow run for this branch and draft PR.
2. Read the complete failed job log.
3. Identify the first real fatal error, not the final cascade.
4. Inspect the exact source and generated `out/.config` related to that error.
5. Make one minimal evidence-backed fix.
6. Run static checks and a clean build.
7. Commit and push only after validation.
8. Wait for the new CI result before making another speculative change.

Never apply multiple unrelated fixes in one iteration. Never hide warnings or undefined symbols with dummy implementations unless the symbol semantics are verified and the fix is technically correct.

## 7. KernelSU-Next rules

- Keep KernelSU built in: `CONFIG_KSU=y`.
- Keep debug disabled for release validation.
- Use only a source revision explicitly pinned by the build script.
- Verify the selected source revision, Kconfig symbols, Kbuild object list, and all referenced symbols before compile.
- Do not mix incompatible manual-hook and Kprobes implementations.
- Do not fake an internal 5.10 kernel ABI by changing global `uname`.
- The device-tree BPF override already supplies userspace BPF compatibility and must remain unless logs prove it is insufficient.
- Any KernelSU source patch must be stored as a deterministic repository patch and applied with a dry-run check before the build.
- Reject patches that are already applied, partially applied, or do not match the pinned source revision.

## 8. Performance and boot-safety constraints

Do not change these areas merely for experimentation while the build/boot baseline is unresolved:

- scheduler and WALT behavior
- CPU frequency tables or governors
- CPU idle states
- GPU driver or GPU frequency policy
- thermal policy
- voltage or overclocking
- memory allocator policy
- storage/filesystem defaults
- modem, Wi-Fi, Bluetooth, camera, audio, display, fingerprint, or charging drivers
- DTB/DTBO contents
- kernel compression or boot-image layout

KernelSU integration must not introduce broad hot-path overhead. Prefer feature-gated, one-time, or self-disabling hooks. Do not add continuous polling, verbose release logging, or unnecessary tracing.

Toolchain upgrades are allowed only after the current baseline builds and only in a separate measured comparison. Do not change clang-r547379 while diagnosing an unrelated source failure.

## 9. Build and validation contract

Before build:

```bash
bash -n build_samurai_v320.sh
chmod +x build_samurai_v320.sh scripts/kconfig/merge_config.sh
```

The final generated configuration must contain the required integration symbols selected by the current implementation. At minimum verify:

```text
CONFIG_KSU=y
CONFIG_KPROBES=y
CONFIG_KRETPROBES=y
CONFIG_OVERLAY_FS=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
```

Also verify the selected KernelSU hook symbol and confirm that conflicting hook modes are not simultaneously enabled.

A successful validation requires all of the following:

```text
out/vmlinux exists and is non-empty
out/arch/arm64/boot/Image.gz-dtb exists and is non-empty
final out/.config is archived
System.map is generated
required KernelSU symbols resolve in vmlinux/System.map
AnyKernel3 ZIP is generated
unzip -t passes
GitHub Actions build and verification steps pass
```

Do not report the kernel as boot-safe merely because it compiles. Compilation success, packaging success, device boot, KernelSU Manager detection, root grant, module mounting, suspend/resume, and hardware validation are separate states.

## 10. Device-tree contract

Use the device tree as the source of truth for ROM packaging and Android compatibility. Preserve:

```text
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb
BOARD_KERNEL_SEPARATED_DTBO := true
BOARD_INCLUDE_RECOVERY_DTBO := true
BOARD_RAMDISK_USE_LZ4 := true
TARGET_KERNEL_CONFIG := samurai_defconfig vendor/debugfs.config
ro.bpf.kver_override=5.10.239
```

Do not edit the device tree during this kernel-first task. Record any discovered Android 16 device-tree defects separately for later work.

## 11. Git and commit discipline

- Keep commits small and technically specific.
- Use the same isolated branch only.
- Do not commit generated build output, toolchains, caches, or downloaded AnyKernel working directories.
- Review before commit:

```bash
git status --short
git diff --check
git diff --stat
git diff
```

- Push only to:

`origin/samurai-4.14.357-ksunext-v320-legacy`

- Keep the PR as draft until CI build and output validation pass.
- Do not merge the PR without explicit user approval and device validation status.

## 12. Reporting format

Report only verified facts:

```text
Current branch
Current commit
CI run number and status
First fatal error, when present
Files changed
Why each change is necessary
Static checks performed
Build result
Artifact result
Remaining device-only validation
```

Do not claim success without corresponding logs or artifacts. Do not produce long generic explanations when a precise status and patch result are sufficient.
