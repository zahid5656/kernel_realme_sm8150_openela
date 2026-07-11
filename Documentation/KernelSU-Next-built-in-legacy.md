# KernelSU-Next built-in legacy integration

Target:

- Device: Realme X2 Pro (`samurai` / `RMX1931`)
- Kernel: OpenELA `4.14.357`
- KernelSU-Next source: configurable ref, default `legacy`
- Integration: built into the kernel (`CONFIG_KSU=y`)
- Hook mode: Kprobes
- Manual hooks: disabled
- Kernel version spoofing: disabled

## Why the kernel version is not spoofed

KernelSU-Next's manager already classifies Linux 4.1 through 4.18 as legacy kernels. Spoofing
`uname` to Linux 5.10 is therefore not required for built-in root support. It would only change
manager-side GKI installation choices and could mislead Android userspace, module tooling, and
diagnostics about the real kernel ABI.

## Boot-safety policy

This branch intentionally keeps the known `los23-test` baseline:

- OpenELA 4.14.357
- clang-r547379
- `-O2`
- existing Samurai AnyKernel3 packaging
- gzip kernel output
- schedutil as the default CPU-frequency governor

ThinLTO, ZSTD kernel compression, aggressive CPU ISA flags, and kernel-version spoofing are not
enabled because they are not required for KernelSU-Next and add independent boot-risk variables.
