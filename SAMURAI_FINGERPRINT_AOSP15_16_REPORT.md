# Samurai Fingerprint AOSP 15/16 Report

## Status

Kernel build status: PASS.

Fingerprint runtime status: not device-tested.

## Detected Hardware Path

The samurai tree uses the Oplus/Goodix optical fingerprint path.

## Required Config Flags

`arch/arm64/configs/samurai_defconfig` contains:

```text
CONFIG_OPPO_FINGERPRINT=y
CONFIG_OPPO_FINGERPRINT_QCOM=y
CONFIG_OPPO_FINGERPRINT_GOODIX=y
```

## Driver Paths

Primary driver paths:

```text
drivers/input/oppo_fp_drivers/oppo_fp_common/
drivers/input/oppo_fp_drivers/goodix_optical_fp/
drivers/input/oppo_secure_common/oppo_secure_common/
drivers/gpu/drm/msm/oplus/oppo_onscreenfingerprint.c
```

The Goodix driver exposes names including:

```text
compatible = "goodix,goodix_fp"
GF_DEV_NAME = "goodix_fp"
CHRD_DRIVER_NAME = "goodix_fp_spi"
CLASS_NAME = "goodix_fp"
GF_INPUT_NAME = "qwerty"
```

## DTS Nodes

Relevant DTS files:

```text
arch/arm64/boot/dts/qcom/sm8150-mtp.dtsi
arch/arm64/boot/dts/qcom/sm8150-pinctrl.dtsi
```

Detected DTS details:

```text
oplus_fp_common
goodix_optical
goodix_fp compatible = "goodix,goodix_fp"
goodix,gpio_irq = GPIO 118
goodix,gpio_reset = GPIO 121
goodix,goodix_pwr = GPIO 101
ldo7-supply = &L7P
pinctrl-0 = &gpio_goodix_irq_default
fingerprint_underscreen_support
```

## Build Evidence

These fingerprint-related objects compiled successfully during the clean build:

```text
drivers/input/oppo_fp_drivers/goodix_optical_fp/gf_spi.o
drivers/input/oppo_fp_drivers/goodix_optical_fp/gf_platform.o
drivers/input/oppo_fp_drivers/goodix_optical_fp/gf_netlink.o
drivers/input/oppo_fp_drivers/oppo_fp_common/oppo_fp_common.o
drivers/input/oppo_secure_common/oppo_secure_common/oppo_secure_common.o
drivers/gpu/drm/msm/oplus/oppo_onscreenfingerprint.o
```

## Fixes Applied

No fingerprint driver or DTS changes were required for the OpenELA 4.14.356 build.

The only build fix was KernelSU-Next Manual hook compatibility in `KernelSU-Next/kernel/feature/selinux_hide.c`; it is not a fingerprint functional change.

## Android 15/16 Risks

Fingerprint cannot be claimed fully fixed for AOSP 15/16 until the following are checked with the ROM/vendor stack:

- Goodix vendor HAL service starts successfully.
- Vendor init rc creates expected device nodes and permissions.
- ueventd permissions cover Goodix SPI/input nodes.
- SELinux permits HAL access to fingerprint SPI/input/sysfs/proc paths.
- On-screen fingerprint display hooks, HBM/AOD/dimming behavior, and touch under-display events match the ROM framework.
- Input node naming and event behavior match the biometric HAL expectation.
- Power, regulator, reset, IRQ, and pinctrl behavior is validated on hardware.

## Current Conclusion

Kernel-side fingerprint source, config, DTS, and build are preserved and buildable for samurai. Runtime AOSP 15/16 fingerprint validation remains blocked until vendor and RealmeParts repositories or device logs are available.
