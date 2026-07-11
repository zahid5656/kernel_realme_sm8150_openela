#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

OUT="$ROOT/out"
TC_ROOT="$ROOT/toolchains"
CLANG_DIR="$TC_ROOT/clang-r547379"
KSU_DIR="$ROOT/KernelSU-Next"
AK3_DIR="$ROOT/AnyKernel3"
LOG="$ROOT/build.log"
INFO="$ROOT/build-info.txt"
CONFIG_FRAGMENT="$ROOT/arch/arm64/configs/ksunext_v320_legacy.config"
KSU_PATCH="$ROOT/patches/ksunext/0001-fix-legacy-kprobes-input-hook-state.patch"

KERNEL_VERSION="4.14.357"
KSU_COMMIT="fd093e8b879063aeb0192a3959b0652101ded623"
KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
CLANG_REPO="https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git"
AK3_REPO="https://github.com/nayem8854/AnyKernel3.git"
AK3_BRANCH="rmx1931"

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=samurai
export KBUILD_BUILD_HOST=titan
export KBUILD_BUILD_VERSION=1
export CCACHE_DIR="${CCACHE_DIR:-$ROOT/.ccache}"

: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

info() { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }
trap 'rc=$?; printf "\033[1;31mBuild failed at line %s with exit code %s\033[0m\n" "$LINENO" "$rc" >&2; exit "$rc"' ERR

verify_source() {
    local version
    version="$(awk '$1=="VERSION"{v=$3} $1=="PATCHLEVEL"{p=$3} $1=="SUBLEVEL"{s=$3} END{print v"."p"."s}' Makefile)"
    [[ "$version" == "$KERNEL_VERSION" ]] || die "Expected kernel $KERNEL_VERSION, found $version"
    [[ -f arch/arm64/configs/samurai_defconfig ]] || die "samurai_defconfig is missing"
    [[ -f "$CONFIG_FRAGMENT" ]] || die "KernelSU config fragment is missing"
    [[ -f "$KSU_PATCH" ]] || die "KernelSU compatibility patch is missing"
    info "Source verified: OpenELA $version"
}

setup_toolchain() {
    mkdir -p "$TC_ROOT"
    if [[ ! -x "$CLANG_DIR/bin/clang" ]]; then
        rm -rf "$CLANG_DIR"
        info "Downloading clang-r547379"
        git clone --depth=1 "$CLANG_REPO" "$CLANG_DIR"
    else
        info "Using cached clang-r547379"
    fi

    export PATH="$CLANG_DIR/bin:$PATH"
    command -v clang >/dev/null || die "clang is unavailable"
    command -v ld.lld >/dev/null || die "ld.lld is unavailable"
    clang --version | head -n 1

    if command -v ccache >/dev/null; then
        ccache --set-config=compiler_check=content >/dev/null 2>&1 || true
        ccache --set-config=max_size=5G >/dev/null 2>&1 || true
        export CC="ccache clang"
    else
        export CC="clang"
    fi
}

reset_ksu_wiring() {
    if [[ -L drivers/kernelsu ]]; then
        rm -f drivers/kernelsu
    elif [[ -e drivers/kernelsu ]]; then
        rm -rf drivers/kernelsu
    fi

    sed -i '/obj-\$(CONFIG_KSU)[[:space:]]*+=[[:space:]]*kernelsu\//d' drivers/Makefile
    sed -i '/source "drivers\/kernelsu\/Kconfig"/d' drivers/Kconfig
}

prepare_ksu() {
    info "Preparing pinned KernelSU-Next v3.2.0-legacy"
    reset_ksu_wiring
    rm -rf "$KSU_DIR"

    git init "$KSU_DIR"
    git -C "$KSU_DIR" remote add origin "$KSU_REPO"
    git -C "$KSU_DIR" fetch --depth=1 origin "$KSU_COMMIT"
    git -C "$KSU_DIR" checkout --detach FETCH_HEAD
    [[ "$(git -C "$KSU_DIR" rev-parse HEAD)" == "$KSU_COMMIT" ]] || die "KernelSU commit mismatch"

    git -C "$KSU_DIR" apply --check "$KSU_PATCH"
    git -C "$KSU_DIR" apply "$KSU_PATCH"

    grep -q '^bool ksu_input_hook __read_mostly = true;' \
        "$KSU_DIR/kernel/runtime/ksud_integration.c" || die "ksu_input_hook definition patch missing"
    grep -q 'WRITE_ONCE(ksu_input_hook, false);' \
        "$KSU_DIR/kernel/runtime/ksud_integration.c" || die "ksu_input_hook stop-state patch missing"

    ln -s ../KernelSU-Next/kernel drivers/kernelsu
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
    sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"\n' drivers/Kconfig

    [[ -f drivers/kernelsu/Kconfig ]] || die "KernelSU Kconfig wiring failed"
    [[ -f drivers/kernelsu/Kbuild ]] || die "KernelSU Kbuild wiring failed"
    info "KernelSU source patched and wired: $KSU_COMMIT"
}

prepare_config() {
    rm -rf "$OUT"
    mkdir -p "$OUT"

    make O="$OUT" ARCH=arm64 samurai_defconfig
    scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "$CONFIG_FRAGMENT"
    make O="$OUT" ARCH=arm64 olddefconfig

    local required=(
        CONFIG_KSU=y
        CONFIG_KPROBES=y
        CONFIG_KRETPROBES=y
        CONFIG_HAVE_SYSCALL_TRACEPOINTS=y
        CONFIG_KSU_KPROBES_HOOK=y
        CONFIG_KSU_ALLOWLIST_WORKAROUND=y
        CONFIG_OVERLAY_FS=y
        CONFIG_EXT4_FS=y
        CONFIG_KALLSYMS=y
        CONFIG_KALLSYMS_ALL=y
    )
    local item
    for item in "${required[@]}"; do
        grep -qx "$item" "$OUT/.config" || die "Required config missing: $item"
    done

    grep -qx '# CONFIG_KSU_MANUAL_HOOK is not set' "$OUT/.config" || die "Manual hook mode was enabled"
    grep -qx '# CONFIG_KSU_DEBUG is not set' "$OUT/.config" || die "KernelSU debug mode was enabled"
    info "Final config verified: built-in KSU Next legacy / Kprobes"
}

build_kernel() {
    info "Compiling Samurai OpenELA $KERNEL_VERSION"
    make -j"$(nproc --all)" \
        O="$OUT" \
        ARCH=arm64 \
        CC="$CC" \
        LLVM=1 \
        LLVM_IAS=1 \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-

    [[ -s "$OUT/vmlinux" ]] || die "vmlinux was not generated"
    [[ -s "$OUT/arch/arm64/boot/Image.gz-dtb" ]] || die "Image.gz-dtb was not generated"

    if command -v llvm-nm >/dev/null; then
        llvm-nm "$OUT/vmlinux" | grep -q ' ksu_input_hook$' || die "ksu_input_hook is absent from vmlinux"
    fi

    if command -v ccache >/dev/null; then
        ccache --show-stats || true
    fi
}

package_kernel() {
    local stamp zip_name zip_path
    stamp="$(date +'%Y%m%d-%H%M')"
    zip_name="Samurai-OpenELA-${KERNEL_VERSION}-KSUNext-v3.2.0-legacy-${stamp}.zip"
    zip_path="$ROOT/$zip_name"

    rm -rf "$AK3_DIR"
    git clone --depth=1 --branch "$AK3_BRANCH" "$AK3_REPO" "$AK3_DIR"
    rm -rf "$AK3_DIR/.git"

    cp -f "$OUT/arch/arm64/boot/Image.gz-dtb" "$AK3_DIR/Image.gz-dtb"
    if [[ -s "$OUT/arch/arm64/boot/dtbo.img" ]]; then
        cp -f "$OUT/arch/arm64/boot/dtbo.img" "$AK3_DIR/dtbo.img"
    else
        warn "dtbo.img was not generated; ZIP contains Image.gz-dtb only"
    fi

    rm -f "$zip_path"
    (cd "$AK3_DIR" && zip -r9 "$zip_path" .)
    unzip -t "$zip_path"

    cat > "$INFO" <<INFOEOF
Device: Realme X2 Pro (samurai / RMX1931)
Kernel: $KERNEL_VERSION-openela
Source branch: ${GITHUB_REF_NAME:-local}
Source commit: ${GITHUB_SHA:-$(git rev-parse HEAD)}
KernelSU-Next tag: v3.2.0-legacy
KernelSU-Next commit: $KSU_COMMIT
Integration: built-in GKI legacy
Hook backend: Kprobes
KSU input-hook synchronization fix: applied
Kernel version spoof: disabled
Android BPF override: device tree ro.bpf.kver_override=5.10.239
Toolchain: clang-r547379
Kernel image: Image.gz-dtb
DTBO: $([[ -s "$OUT/arch/arm64/boot/dtbo.img" ]] && echo included || echo not-generated)
Performance configuration: original Samurai baseline preserved
Kernel ZIP: $zip_name
INFOEOF

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "zip_name=$zip_name"
            echo "zip_path=$zip_path"
            echo "build_log=$LOG"
            echo "build_info=$INFO"
        } >> "$GITHUB_OUTPUT"
    fi

    info "Build artifact: $zip_path"
}

main() {
    verify_source
    setup_toolchain
    prepare_ksu
    prepare_config
    build_kernel
    package_kernel
    info "Samurai kernel build completed successfully"
}

main "$@"
