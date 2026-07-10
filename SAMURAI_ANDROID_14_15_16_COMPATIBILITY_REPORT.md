# Samurai Android 14/15/16 Compatibility Report

## Status

Build-time Android compatibility status: PASS.

Runtime Android 14/15/16 status: not device-tested in this environment.

## Verified Kernel Config Surface

`arch/arm64/configs/samurai_defconfig` keeps the important Android custom ROM options enabled:

```text
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ASHMEM=y
CONFIG_DM_DEFAULT_KEY=y
CONFIG_DM_VERITY=y
CONFIG_DM_VERITY_FEC=y
CONFIG_F2FS_FS_ENCRYPTION=y
CONFIG_FS_ENCRYPTION_INLINE_CRYPT=y
CONFIG_FUSE_FS=y
CONFIG_OVERLAY_FS=y
CONFIG_INCREMENTAL_FS=y
CONFIG_EXFAT_FS=y
CONFIG_SDCARD_FS=y
CONFIG_SECURITY_SELINUX=y
CONFIG_CGROUPS=y
CONFIG_CPUSETS=y
CONFIG_PSI=y
CONFIG_NAMESPACES=y
CONFIG_SECCOMP=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_WIREGUARD=y
```

## Build Evidence

The following Android-relevant areas compiled successfully:

- Binder and binderfs
- Ashmem and ION
- dm-default-key, dm-verity, dm-verity-fec
- ext4, f2fs encryption, fsverity
- FUSE, overlayfs, incrementalfs, exFAT, sdcardfs
- cgroups, cpuset, PSI, seccomp, BPF
- SELinux
- WireGuard
- Qualcomm IPA/RMNET, MHI, UFS crypto
- Oplus/Realme charging, display, touch, fingerprint, NFC, audio, camera

## Android 14 Readiness

Android 14 is the lowest risk target because the tree already preserves legacy Android compatibility paths such as ashmem and sdcardfs while also keeping binderfs and modern filesystem support enabled.

## Android 15/16 Readiness

Android 15/16 readiness is plausible from the kernel config and successful build. Key support areas are present: binderfs, modern FBE/fscrypt paths, dm-default-key, dm-verity/FEC, SELinux, PSI, BPF, WireGuard, FUSE/overlayfs, and vendor Qualcomm/Oplus drivers.

This is not a runtime certification. Android 15/16 must still be checked with the actual device tree, vendor blobs, init rc files, ueventd rules, SELinux policy, and biometric HAL stack used by the ROM.

## Vendor And RealmeParts Sync

Local search did not find:

```text
proprietary_vendor_realme_samurai
android_packages_apps_RealmeParts
```

Required follow-up checks when those repos are available:

- `/vendor/etc/init/*.rc`
- `/vendor/etc/ueventd*.rc`
- `/vendor/etc/permissions/*.xml`
- vendor SELinux labels and file contexts
- RealmeParts sysfs paths for display, charging, vibration, thermal, and fingerprint behavior
- fingerprint device permissions and input node ownership
- thermal HAL paths
- charger and VOOC sysfs paths
- display HBM/DC dimming/AOD/on-screen-fingerprint sysfs paths

## Remaining Risks

- `CONFIG_SDCARD_FS=y` is preserved for compatibility but may be unused by newer Android userspace.
- Android 15/16 biometric and display-under-fingerprint behavior depends on vendor HAL and SELinux policy not present in this checkout.
- Runtime validation on AOSP 14, 15, and 16 boot images is still required.
