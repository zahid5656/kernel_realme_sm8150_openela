# Samurai OpenELA 4.14.356 Upgrade Report

## Scope

- Device: Realme X2 Pro (`samurai`)
- Kernel family: Linux 4.14.x
- Working branch: `upgrade-openela-4.14.356-samurai`
- Starting checkout state: `4.14.357-openela` on `openela-357-ksun_legacy`, not `4.14.339`
- Target state: `4.14.356-openela`
- Source of truth: official OpenELA tag `v4.14.356-openela`

## Repository Audit

- Detected defconfig: `arch/arm64/configs/samurai_defconfig`
- Detected build script: `build.sh`
- Detected toolchain: official AOSP Clang prebuilt `clang-r522817`
- Detected KernelSU-Next: `KernelSU-Next`, version `33189`, tag `v3.2.0-legacy`, Manual hook mode
- Detected output format: `Image.gz`, `dtbo.img`, AnyKernel3 zip

## Integration Method

The local tree was already ahead of the requested target at `4.14.357-openela`. To align to the requested OpenELA LTS `4.14.356` without replacing downstream Realme/Qualcomm/Android code, I fetched the official OpenELA tag and reversed only the official `v4.14.356-openela..v4.14.357-openela` delta.

This touched the small upstream delta surface:

- `.elts/config.yaml`
- `Makefile`
- `drivers/clk/clk-devres.c`
- `fs/ocfs2/quota_global.c`
- `fs/ocfs2/quota_local.c`
- `include/linux/skbuff.h`
- `net/core/sock_destructor.h`
- `net/ipv4/inet_fragment.c`
- `net/ipv4/ip_fragment.c`
- `net/ipv6/netfilter/nf_conntrack_reasm.c`
- `security/integrity/ima/ima_api.c`
- `security/integrity/ima/ima_template_lib.c`

No Qualcomm device tree, display, touch, fingerprint, audio, camera, WLAN, power, or Realme/Oplus driver code was removed for the OpenELA alignment.

## Final Version

`make kernelversion` reports:

```text
4.14.356-openela
```

## Build Fix Applied

The first full build reached final link and failed only in KernelSU-Next:

```text
undefined symbol: slow_avc_audit_kp
undefined symbol: destroy_kprobe
undefined symbol: slow_avc_audit_pre_handler
undefined symbol: init_kprobe
```

Cause: `KernelSU-Next/kernel/feature/selinux_hide.c` used generic `CONFIG_KPROBES` guards while the samurai defconfig builds KernelSU in Manual hook mode:

```text
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
# CONFIG_KSU_KPROBES_HOOK is not set
CONFIG_KPROBES=y
```

Fix: guard the slow AVC kprobe helper references with `KSU_KPROBES_HOOK` instead of `CONFIG_KPROBES`, so Manual hook builds do not link kprobe-only helper symbols.

## Build Result

- Status: PASS
- Kernel image: `out/arch/arm64/boot/Image.gz`
- DTBO: `out/arch/arm64/boot/dtbo.img`
- Flashable package: `samurai-4.14.356-[10072026-0536]-KSU_Next.zip`
- Modules: `MODPOST 0 modules`
- Build time: `1431 seconds`

## Remaining Risks

- Runtime boot was not tested on a device.
- Vendor and RealmeParts repositories were not found locally, so sysfs/vendor init compatibility is documented as a required sync check.
- Android 15/16 readiness is config/source/build validated only; it is not a certified runtime result.
