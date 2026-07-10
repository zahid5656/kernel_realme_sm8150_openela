# Samurai Build Log Summary

## Build Command

```bash
KSU_AUTO_SYNC=0 ./build.sh
```

## Toolchain

```text
Android (11967740, +pgo, +bolt, +lto, +mlgo, based on r522817) clang version 18.0.1
```

Toolchain path:

```text
toolchain/clang-r522817
```

## KernelSU-Next

```text
Version: 33189
Tag: v3.2.0-legacy
Hook mode: Manual
Auto-sync: disabled with KSU_AUTO_SYNC=0
```

## Result

```text
Build status: PASS
Kernel version: 4.14.356-openela
Build time: 1431 seconds
Modules: MODPOST 0 modules
```

## Artifacts

```text
out/arch/arm64/boot/Image.gz
out/arch/arm64/boot/dtbo.img
samurai-4.14.356-[10072026-0536]-KSU_Next.zip
```

Artifact sizes:

```text
Image.gz: 19M
dtbo.img: 485K
AnyKernel zip: 22M
```

## Warning Summary

The saved `build.log` contains no `warning:` or `error:` matches.

Observed console warnings:

```text
arch/arm64/configs/samurai_defconfig:532: warning: override: reassigning to symbol HID_SONY
arch/arm64/configs/samurai_defconfig:533: warning: override: reassigning to symbol SONY_FF
arch/arm64/configs/samurai_defconfig:535: warning: override: reassigning to symbol HID_STEAM
arch/arm64/configs/samurai_defconfig:537: warning: override: reassigning to symbol HID_GREENASIA
arch/arm64/configs/samurai_defconfig:538: warning: override: reassigning to symbol GREENASIA_FF
scripts/dtc/libfdt/mkdtboimg.py:127: SyntaxWarning: "is" with 'int' literal. Did you mean "=="?
```

These warnings did not stop defconfig generation, DTBO generation, vmlinux link, image generation, or AnyKernel packaging.

## Error Fixed During Build

Initial final link failure:

```text
ld.lld: error: undefined symbol: slow_avc_audit_kp
ld.lld: error: undefined symbol: destroy_kprobe
ld.lld: error: undefined symbol: slow_avc_audit_pre_handler
ld.lld: error: undefined symbol: init_kprobe
```

Fix:

```text
build.sh
KernelSU-Next/kernel/feature/selinux_hide.c
```

Changed slow AVC kprobe guards from `CONFIG_KPROBES` to `KSU_KPROBES_HOOK` so Manual hook builds do not reference kprobe-only helper symbols.
`build.sh` applies this targeted KernelSU-Next source adjustment after KernelSU sync/link, so the parent branch does not depend on ignored local KernelSU-Next edits.

## Verification Commands

```bash
make kernelversion
rg -n "warning:|error:" build.log
ls -lh out/arch/arm64/boot/Image.gz out/arch/arm64/boot/dtbo.img 'samurai-4.14.356-[10072026-0536]-KSU_Next.zip'
git status --short
git -C KernelSU-Next status --short
```

## Notes

- `build.sh` still disables ccache unless `USE_CCACHE=1`; that change was already present in the working tree before the OpenELA alignment work.
- `KernelSU-Next/kernel/Kbuild` had a nested dirty change related to clean-build hook checks during local verification. It is separate from the `selinux_hide.c` Manual hook adjustment applied by `build.sh`.
