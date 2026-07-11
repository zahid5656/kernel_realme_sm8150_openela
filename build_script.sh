#!/usr/bin/env bash

set -Eeuo pipefail

KERNEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$KERNEL_DIR"

OUT_DIR="$KERNEL_DIR/out"
TC_DIR="$KERNEL_DIR/toolchains"
CLANG_DIR="$TC_DIR/clang-r547379"
ANYKERNEL_DIR="$KERNEL_DIR/AnyKernel3"
BUILD_LOG="$KERNEL_DIR/build.log"

CONFIG_FILE="samurai_defconfig"
DEFCONFIG_FILE="$KERNEL_DIR/arch/arm64/configs/$CONFIG_FILE"

KERNEL_NAME="samurai-4.14.357"
KSU_BRANCH="legacy"
KSU_SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/legacy/kernel/setup.sh"
KSU_DIR="$KERNEL_DIR/KernelSU-Next"

ANYKERNEL_REPO="https://github.com/nayem8854/AnyKernel3.git"
ANYKERNEL_BRANCH="rmx1931"

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

    [[ -x "$CLANG_DIR/bin/clang" ]] || fail "clang was not downloaded correctly"
}

setup_environment() {
    export PATH="$CLANG_DIR/bin:$PATH"

    command -v clang >/dev/null 2>&1 || fail "clang is unavailable"

    if command -v ccache >/dev/null 2>&1; then
        export CC="ccache clang"
        ccache --set-config=compiler_check=content >/dev/null 2>&1 || true
        ccache --set-config=max_size=5G >/dev/null 2>&1 || true
    else
        export CC="clang"
    fi

    info "Compiler: $CC"
    clang --version | head -n 1
}

set_config() {
    local symbol="$1"
    local value="$2"

    sed -i \
        -e "/^${symbol}=.*/d" \
        -e "/^# ${symbol} is not set$/d" \
        "$DEFCONFIG_FILE"

    printf '%s=%s\n' "$symbol" "$value" >> "$DEFCONFIG_FILE"
}

disable_config() {
    local symbol="$1"

    sed -i \
        -e "/^${symbol}=.*/d" \
        -e "/^# ${symbol} is not set$/d" \
        "$DEFCONFIG_FILE"

    printf '# %s is not set\n' "$symbol" >> "$DEFCONFIG_FILE"
}

install_latest_ksunext_legacy() {
    local setup_script
    setup_script="$(mktemp)"

    [[ -f "$DEFCONFIG_FILE" ]] || fail "Missing defconfig: $DEFCONFIG_FILE"

    info "Downloading official KernelSU-Next legacy setup script"
    curl -fLSs "$KSU_SETUP_URL" -o "$setup_script"
    chmod +x "$setup_script"

    info "Removing previous KernelSU-Next integration"
    bash "$setup_script" --cleanup || true

    info "Installing latest KernelSU-Next legacy branch"
    bash "$setup_script" "$KSU_BRANCH"
    rm -f "$setup_script"

    [[ -d "$KSU_DIR/.git" ]] || fail "KernelSU-Next repository was not installed"

    KSU_COMMIT="$(git -C "$KSU_DIR" rev-parse HEAD)"
    KSU_SHORT="$(git -C "$KSU_DIR" rev-parse --short=12 HEAD)"
    KSU_DESCRIBE="$(git -C "$KSU_DIR" describe --tags --always 2>/dev/null || echo legacy-$KSU_SHORT)"
    export KSU_COMMIT KSU_SHORT KSU_DESCRIBE

    info "KernelSU-Next branch: $KSU_BRANCH"
    info "KernelSU-Next revision: $KSU_DESCRIBE ($KSU_SHORT)"

    sed -i \
        -e '/^CONFIG_KSU_KPROBE_HOOKS=.*/d' \
        -e '/^# CONFIG_KSU_KPROBE_HOOKS is not set$/d' \
        -e '/^CONFIG_KSU_KPROBE_HOOK=.*/d' \
        -e '/^# CONFIG_KSU_KPROBE_HOOK is not set$/d' \
        "$DEFCONFIG_FILE"

    set_config CONFIG_KPROBES y
    set_config CONFIG_KRETPROBES y
    set_config CONFIG_KPROBE_EVENTS y
    set_config CONFIG_KSU y
    disable_config CONFIG_KSU_MANUAL_HOOK
    set_config CONFIG_KSU_KPROBES_HOOK y
}

clean_output() {
    info "Cleaning previous output"
    rm -rf "$OUT_DIR"
    rm -f "$KERNEL_DIR"/*.zip
}

generate_config() {
    info "Generating $CONFIG_FILE"

    make \
        O="$OUT_DIR" \
        ARCH=arm64 \
        "$CONFIG_FILE"

    grep -qx 'CONFIG_KSU=y' "$OUT_DIR/.config" || fail "CONFIG_KSU is not enabled"
    grep -qx 'CONFIG_KPROBES=y' "$OUT_DIR/.config" || fail "CONFIG_KPROBES is not enabled"
    grep -qx 'CONFIG_KRETPROBES=y' "$OUT_DIR/.config" || fail "CONFIG_KRETPROBES is not enabled"
    grep -qx 'CONFIG_KSU_KPROBES_HOOK=y' "$OUT_DIR/.config" || fail "KernelSU Kprobes hook mode is not enabled"

    if grep -qx 'CONFIG_KSU_MANUAL_HOOK=y' "$OUT_DIR/.config"; then
        fail "Manual hook mode was enabled unexpectedly"
    fi
}

compile_kernel() {
    info "Building Realme X2 Pro kernel"

    make -j"$(nproc --all)" \
        O="$OUT_DIR" \
        ARCH=arm64 \
        CC="$CC" \
        LLVM=1 \
        LLVM_IAS=1 \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-
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

    zip_name="${KERNEL_NAME}-$(date +'%d%m%Y-%H%M')-KSU-Next-legacy-${KSU_SHORT}.zip"
    output_zip="$KERNEL_DIR/$zip_name"

    info "Cloning AnyKernel3 rmx1931 branch"
    rm -rf "$ANYKERNEL_DIR"
    git clone --depth=1 \
        --branch "$ANYKERNEL_BRANCH" \
        "$ANYKERNEL_REPO" \
        "$ANYKERNEL_DIR"

    cp -f "$compiled_image" "$ANYKERNEL_DIR/"

    if [[ -s "$compiled_dtbo" ]]; then
        cp -f "$compiled_dtbo" "$ANYKERNEL_DIR/"
    else
        warn "dtbo.img was not generated; preserving the original optional-dtbo packaging behavior"
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

    printf '%s\n' \
        "Device: Realme X2 Pro (samurai / RMX1931)" \
        "Kernel: $KERNEL_NAME" \
        "Source branch: ${GITHUB_REF_NAME:-local}" \
        "KernelSU-Next branch: $KSU_BRANCH" \
        "KernelSU-Next revision: $KSU_DESCRIBE" \
        "KernelSU-Next commit: $KSU_COMMIT" \
        "Hook mode: Kprobes" \
        "Kernel ZIP: $zip_name" \
        > "$KERNEL_DIR/build-info.txt"

    info "Kernel ZIP: $output_zip"
    info "Build log: $BUILD_LOG"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "zip_path=$output_zip"
            echo "zip_name=$zip_name"
            echo "build_log=$BUILD_LOG"
            echo "build_info=$KERNEL_DIR/build-info.txt"
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

    clean_output
    download_clang
    setup_environment
    install_latest_ksunext_legacy
    generate_config
    compile_kernel
    package_kernel

    end="$(date +%s)"
    elapsed=$((end - start))
    info "Build completed in ${elapsed} seconds"
}

main "$@"
