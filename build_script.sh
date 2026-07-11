#!/usr/bin/env bash

set -Eeuo pipefail

KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KERNEL_DIR"

OUT_DIR="$KERNEL_DIR/out"
TC_DIR="$KERNEL_DIR/toolchains"
CLANG_DIR="$TC_DIR/clang-r547379"
KSU_DIR="$KERNEL_DIR/KernelSU-Next"
ANYKERNEL_DIR="$KERNEL_DIR/AnyKernel3"

CONFIG_FILE="samurai_defconfig"
KSU_CONFIG_FRAGMENT="$KERNEL_DIR/arch/arm64/configs/ksunext_legacy.config"

KERNEL_NAME="samurai-4.14.357"
EXPECTED_KERNEL_VERSION="4.14.357"

KSU_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
KSU_REF="${KSU_REF:-legacy}"

ANYKERNEL_REPO="https://github.com/nayem8854/AnyKernel3.git"
ANYKERNEL_BRANCH="rmx1931"

BUILD_LOG="$KERNEL_DIR/build.log"
BUILD_INFO="$KERNEL_DIR/build-info.txt"

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=samurai
export KBUILD_BUILD_HOST=titan
export KBUILD_BUILD_VERSION=1

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

: > "$BUILD_LOG"
exec > >(tee -a "$BUILD_LOG") 2>&1

info() {
    echo -e "${GREEN}$*${NC}"
}

warn() {
    echo -e "${YELLOW}$*${NC}"
}

fail() {
    echo -e "${RED}$*${NC}" >&2
    exit 1
}

on_error() {
    local rc=$?
    echo -e "${RED}Build failed with exit code: $rc${NC}" >&2
    echo -e "${RED}Build log: $BUILD_LOG${NC}" >&2
    exit "$rc"
}

trap on_error ERR

install_dependencies() {
    local apt=(apt-get)

    if command -v sudo >/dev/null 2>&1; then
        apt=(sudo apt-get)
    fi

    "${apt[@]}" update
    "${apt[@]}" install -y \
        bc \
        bison \
        build-essential \
        ccache \
        cpio \
        curl \
        device-tree-compiler \
        flex \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabi \
        git \
        libelf-dev \
        libncurses-dev \
        libssl-dev \
        python3 \
        python-is-python3 \
        rsync \
        unzip \
        wget \
        zip \
        zlib1g-dev
}

download_clang() {
    if [[ -x "$CLANG_DIR/bin/clang" ]]; then
        info "Using cached clang-r547379"
        return
    fi

    rm -rf "$CLANG_DIR"
    mkdir -p "$TC_DIR"

    info "Downloading Android clang-r547379"
    git clone --depth=1 \
        https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git \
        "$CLANG_DIR"

    [[ -x "$CLANG_DIR/bin/clang" ]] || fail "clang-r547379 was not downloaded correctly"
}

setup_environment() {
    export PATH="$CLANG_DIR/bin:$PATH"

    command -v clang >/dev/null 2>&1 || fail "clang is unavailable"
    command -v ld.lld >/dev/null 2>&1 || fail "ld.lld is unavailable"

    if command -v ccache >/dev/null 2>&1; then
        export CC="ccache clang"
        export CCACHE_DIR="${CCACHE_DIR:-$KERNEL_DIR/.ccache}"
        ccache --set-config=compiler_check=content >/dev/null 2>&1 || true
        ccache --set-config=max_size=5G >/dev/null 2>&1 || true
        ccache --zero-stats >/dev/null 2>&1 || true
    else
        export CC="clang"
    fi

    info "Compiler: $CC"
    clang --version | head -n 1
}

verify_kernel_version() {
    local version

    version="$(make -s kernelversion)"
    [[ "$version" == "$EXPECTED_KERNEL_VERSION" ]] || \
        fail "Expected kernel $EXPECTED_KERNEL_VERSION, found $version"

    info "Verified kernel version: $version"
}

remove_previous_ksu_integration() {
    if [[ -L "$KERNEL_DIR/drivers/kernelsu" ]]; then
        rm -f "$KERNEL_DIR/drivers/kernelsu"
    elif [[ -e "$KERNEL_DIR/drivers/kernelsu" ]]; then
        rm -rf "$KERNEL_DIR/drivers/kernelsu"
    fi

    sed -i '/obj-\$(CONFIG_KSU)[[:space:]]*+=[[:space:]]*kernelsu\//d' \
        "$KERNEL_DIR/drivers/Makefile"

    sed -i '/source "drivers\/kernelsu\/Kconfig"/d' \
        "$KERNEL_DIR/drivers/Kconfig"

    rm -rf "$KSU_DIR"
}

sync_ksunext() {
    info "Synchronizing KernelSU-Next ref: $KSU_REF"

    remove_previous_ksu_integration

    mkdir -p "$KSU_DIR"
    git -C "$KSU_DIR" init
    git -C "$KSU_DIR" remote add origin "$KSU_REPO"
    git -C "$KSU_DIR" fetch --depth=1 origin "$KSU_REF"
    git -C "$KSU_DIR" checkout --detach FETCH_HEAD

    git -C "$KSU_DIR" submodule sync --recursive
    git -C "$KSU_DIR" submodule update --init --recursive

    [[ -f "$KSU_DIR/kernel/Kconfig" ]] || fail "KernelSU-Next kernel/Kconfig is missing"
    [[ -f "$KSU_DIR/kernel/Kbuild" ]] || fail "KernelSU-Next kernel/Kbuild is missing"

    ln -sfn ../KernelSU-Next/kernel "$KERNEL_DIR/drivers/kernelsu"

    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_DIR/drivers/Makefile"
    sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"\n' "$KERNEL_DIR/drivers/Kconfig"

    KSU_COMMIT="$(git -C "$KSU_DIR" rev-parse HEAD)"
    KSU_SHORT="$(git -C "$KSU_DIR" rev-parse --short=12 HEAD)"
    KSU_DESCRIBE="$(git -C "$KSU_DIR" describe --tags --always 2>/dev/null || printf 'legacy-%s' "$KSU_SHORT")"

    export KSU_COMMIT KSU_SHORT KSU_DESCRIBE

    info "KernelSU-Next revision: $KSU_DESCRIBE"
    info "KernelSU-Next commit: $KSU_COMMIT"
}

clean_output() {
    info "Cleaning build output"
    rm -rf "$OUT_DIR" "$ANYKERNEL_DIR"
    rm -f "$BUILD_INFO"
    find "$KERNEL_DIR" -maxdepth 1 -type f -name 'samurai-4.14.357-*.zip' -delete
}

generate_config() {
    [[ -f "$KSU_CONFIG_FRAGMENT" ]] || \
        fail "Missing KSU config fragment: $KSU_CONFIG_FRAGMENT"

    info "Generating $CONFIG_FILE"
    make O="$OUT_DIR" ARCH=arm64 "$CONFIG_FILE"

    info "Merging built-in KernelSU-Next legacy configuration"
    "$KERNEL_DIR/scripts/kconfig/merge_config.sh" \
        -m \
        -O "$OUT_DIR" \
        "$OUT_DIR/.config" \
        "$KSU_CONFIG_FRAGMENT"

    make O="$OUT_DIR" ARCH=arm64 olddefconfig

    grep -qx 'CONFIG_KSU=y' "$OUT_DIR/.config" || \
        fail "CONFIG_KSU is not built-in"

    grep -qx 'CONFIG_KPROBES=y' "$OUT_DIR/.config" || \
        fail "CONFIG_KPROBES is not enabled"

    grep -qx 'CONFIG_KRETPROBES=y' "$OUT_DIR/.config" || \
        fail "CONFIG_KRETPROBES is not enabled"

    grep -qx 'CONFIG_KSU_KPROBES_HOOK=y' "$OUT_DIR/.config" || \
        fail "CONFIG_KSU_KPROBES_HOOK is not enabled"

    if grep -qx 'CONFIG_KSU_MANUAL_HOOK=y' "$OUT_DIR/.config"; then
        fail "Manual hook mode was enabled unexpectedly"
    fi

    info "Verified KernelSU-Next mode: built-in legacy with Kprobes"
}

compile_kernel() {
    info "Building Realme X2 Pro kernel"

    make -j"$(nproc --all)" \
        O="$OUT_DIR" \
        ARCH=arm64 \
        CC="$CC" \
        LLVM=1 \
        LLVM_IAS=1 \
        LD=ld.lld \
        AR=llvm-ar \
        NM=llvm-nm \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-

    if command -v ccache >/dev/null 2>&1; then
        ccache --show-stats || true
    fi
}

package_kernel() {
    local compiled_image=""
    local compiled_dtbo="$OUT_DIR/arch/arm64/boot/dtbo.img"
    local zip_name
    local output_zip

    if [[ -s "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]]; then
        compiled_image="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    elif [[ -s "$OUT_DIR/arch/arm64/boot/Image.gz" ]]; then
        compiled_image="$OUT_DIR/arch/arm64/boot/Image.gz"
    else
        fail "Missing Image.gz-dtb and Image.gz"
    fi

    zip_name="${KERNEL_NAME}-$(date +'%d%m%Y-%H%M')-KSU-Next-${KSU_DESCRIBE}-${KSU_SHORT}.zip"
    zip_name="${zip_name//\//-}"
    output_zip="$KERNEL_DIR/$zip_name"

    info "Cloning AnyKernel3 rmx1931 branch"
    git clone --depth=1 \
        --branch "$ANYKERNEL_BRANCH" \
        "$ANYKERNEL_REPO" \
        "$ANYKERNEL_DIR"

    cp -f "$compiled_image" "$ANYKERNEL_DIR/"

    if [[ -s "$compiled_dtbo" ]]; then
        cp -f "$compiled_dtbo" "$ANYKERNEL_DIR/"
    else
        warn "dtbo.img was not generated; packaging kernel image only"
    fi

    rm -rf "$ANYKERNEL_DIR/.git"
    rm -f "$output_zip"

    (
        cd "$ANYKERNEL_DIR"
        find . -type f -name '*.zip' -delete
        zip -r9 "$output_zip" .
    )

    rm -rf "$ANYKERNEL_DIR"

    [[ -s "$output_zip" ]] || fail "Kernel ZIP was not created"
    unzip -t "$output_zip"

    printf '%s\n' \
        "Device: Realme X2 Pro (samurai / RMX1931)" \
        "Kernel: $EXPECTED_KERNEL_VERSION" \
        "Source branch: ${GITHUB_REF_NAME:-local}" \
        "Source commit: ${GITHUB_SHA:-$(git rev-parse HEAD)}" \
        "KernelSU-Next ref: $KSU_REF" \
        "KernelSU-Next revision: $KSU_DESCRIBE" \
        "KernelSU-Next commit: $KSU_COMMIT" \
        "Integration: built-in" \
        "Hook mode: Kprobes" \
        "Kernel version spoof: disabled" \
        "Optimization: O2, clang-r547379, schedutil baseline" \
        "Kernel ZIP: $zip_name" \
        > "$BUILD_INFO"

    info "Kernel ZIP: $output_zip"
    info "Build log: $BUILD_LOG"
    info "Build information: $BUILD_INFO"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "zip_path=$output_zip"
            echo "zip_name=$zip_name"
            echo "build_log=$BUILD_LOG"
            echo "build_info=$BUILD_INFO"
            echo "ksu_commit=$KSU_COMMIT"
            echo "ksu_short=$KSU_SHORT"
            echo "ksu_describe=$KSU_DESCRIBE"
        } >> "$GITHUB_OUTPUT"
    fi
}

main() {
    local start end elapsed

    start="$(date +%s)"

    if [[ "${INSTALL_DEPS:-0}" == "1" ]]; then
        install_dependencies
    fi

    verify_kernel_version
    clean_output
    download_clang
    setup_environment
    sync_ksunext
    generate_config
    compile_kernel
    package_kernel

    end="$(date +%s)"
    elapsed=$((end - start))

    info "Build completed in ${elapsed} seconds"
}

main "$@"
