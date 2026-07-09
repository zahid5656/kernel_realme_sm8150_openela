#!/usr/bin/env bash

set -e
set -o pipefail

KERNEL_DIR="$(pwd)"
OUT_DIR="$KERNEL_DIR/out"

TC_DIR="$KERNEL_DIR/toolchain"
CLANG_VERSION="clang-r522817"
CLANG_DIR="$TC_DIR/$CLANG_VERSION"
CLANG_ARCHIVE="$CLANG_DIR/$CLANG_VERSION.tgz"
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/$CLANG_VERSION.tgz"

ANYKERNEL_DIR="$KERNEL_DIR/AnyKernel3"
ANYKERNEL_REPO="https://github.com/nayem8854/AnyKernel3.git"
ANYKERNEL_BRANCH="rmx1931"

CONFIG_FILE="samurai_defconfig"
KSU_REPO_DIR="$KERNEL_DIR/KernelSU-Next"
KSU_REPO_URL="${KSU_REPO_URL:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KSU_LEGACY_BRANCH="${KSU_LEGACY_BRANCH:-legacy}"
KSU_REF="${KSU_REF:-$KSU_LEGACY_BRANCH}"
KSU_AUTO_SYNC="${KSU_AUTO_SYNC:-1}"

KERNEL_NAME="samurai-4.14.357"
DATE=$(date +"[%d%m%Y-%H%M]")
TIME=$(date +"%H.%M.%S")
ZIP_NAME="$KERNEL_NAME-$DATE-KSU_Next.zip"
BUILD_LOG="$KERNEL_DIR/build.log"

export ARCH=arm64
export SUBARCH=arm64

export KBUILD_BUILD_USER=samurai
export KBUILD_BUILD_HOST=titan
export KBUILD_BUILD_VERSION=1

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

START=$(date +%s)

msg()
{
    echo -e "${GREEN}$*${NC}"
}

warn()
{
    echo -e "${YELLOW}$*${NC}"
}

err()
{
    echo -e "${RED}$*${NC}" >&2
}

have_cmd()
{
    command -v "$1" >/dev/null 2>&1
}

install_deps()
{
    msg "Installing dependencies..."

    apt-get update

    apt-get install -y \
        bc \
        git-core \
        gnupg \
        flex \
        bison \
        build-essential \
        zip \
        curl \
        wget \
        zlib1g-dev \
        libc6-dev-i386 \
        libncurses5 \
        lib32ncurses5-dev \
        x11proto-core-dev \
        libx11-dev \
        lib32z1-dev \
        libgl1-mesa-dev \
        libxml2-utils \
        xsltproc \
        unzip \
        fontconfig \
        libssl-dev \
        ccache \
        cpio || true
}

check_required_tools()
{
    local missing=()
    local tool

    for tool in bc bison flex git make openssl perl python3 tar zip; do
        if ! have_cmd "$tool"; then
            missing+=("$tool")
        fi
    done

    if ! have_cmd curl && ! have_cmd wget; then
        missing+=("curl-or-wget")
    fi

    if ((${#missing[@]})); then
        err "Missing required host tools: ${missing[*]}"
        err "Run './build.sh deps' as root, or install them with your package manager."
        exit 1
    fi
}

download_file()
{
    local url="$1"
    local output="$2"

    if have_cmd curl; then
        curl -L --fail --retry 3 --output "$output" "$url"
    else
        wget -O "$output" "$url"
    fi
}

download_clang()
{
    if [[ -x "$CLANG_DIR/bin/clang" ]]; then
        msg "Clang already exists: $CLANG_DIR"
        return
    fi

    msg "Downloading official AOSP LLVM Clang $CLANG_VERSION from android.googlesource.com..."

    rm -rf "$CLANG_DIR"
    mkdir -p "$CLANG_DIR"

    download_file "$CLANG_URL" "$CLANG_ARCHIVE"
    tar -xzf "$CLANG_ARCHIVE" -C "$CLANG_DIR"
    rm -f "$CLANG_ARCHIVE"

    if [[ ! -x "$CLANG_DIR/bin/clang" ]]; then
        err "Clang download completed, but $CLANG_DIR/bin/clang is missing."
        exit 1
    fi
}

setup_env()
{
    export PATH="$CLANG_DIR/bin:$PATH"

    if have_cmd ccache; then
        export CC="ccache clang"
    else
        export CC="clang"
    fi

    msg "Using compiler:"
    clang --version | head -n 1
}

sync_submodules()
{
    git submodule update --init --recursive
}

patch_ksu_config()
{
    local defconfig_file="arch/arm64/configs/${CONFIG_FILE}"

    msg "Patching ${defconfig_file}"

    grep -qxF "CONFIG_KPROBES=y" "$defconfig_file" || \
        echo "CONFIG_KPROBES=y" >> "$defconfig_file"

    grep -qxF "CONFIG_KPROBE_EVENTS=y" "$defconfig_file" || \
        echo "CONFIG_KPROBE_EVENTS=y" >> "$defconfig_file"

    grep -qxF "CONFIG_KSU_KPROBE_HOOKS=y" "$defconfig_file" || \
        echo "CONFIG_KSU_KPROBE_HOOKS=y" >> "$defconfig_file"

    grep -qxF "CONFIG_KSU=y" "$defconfig_file" || \
        echo "CONFIG_KSU=y" >> "$defconfig_file"
}

link_ksu_source()
{
    ln -sfn "../KernelSU-Next/kernel" "$KERNEL_DIR/drivers/kernelsu"

    grep -q "kernelsu" "$KERNEL_DIR/drivers/Makefile" || \
        printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$KERNEL_DIR/drivers/Makefile"

    grep -q "source \"drivers/kernelsu/Kconfig\"" "$KERNEL_DIR/drivers/Kconfig" || \
        sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$KERNEL_DIR/drivers/Kconfig"
}

sync_ksu_legacy()
{
    local stashed=0

    if [[ "$KSU_AUTO_SYNC" != "1" ]]; then
        warn "KernelSU-Next auto-sync disabled by KSU_AUTO_SYNC=$KSU_AUTO_SYNC"
        link_ksu_source
        patch_ksu_config
        return
    fi

    msg "Syncing KernelSU-Next from ${KSU_REF} before compile..."

    if [[ ! -d "$KSU_REPO_DIR/.git" ]]; then
        git clone "$KSU_REPO_URL" "$KSU_REPO_DIR"
    fi

    git -C "$KSU_REPO_DIR" fetch origin --tags

    if [[ -n "$(git -C "$KSU_REPO_DIR" status --porcelain)" ]]; then
        git -C "$KSU_REPO_DIR" stash push -u -m "build.sh auto-stash before ${KSU_REF} sync"
        stashed=1
    fi

    if git -C "$KSU_REPO_DIR" show-ref --verify --quiet "refs/remotes/origin/${KSU_REF}"; then
        git -C "$KSU_REPO_DIR" checkout -B "$KSU_REF" "origin/$KSU_REF"
        git -C "$KSU_REPO_DIR" pull --ff-only origin "$KSU_REF"
    else
        git -C "$KSU_REPO_DIR" checkout "$KSU_REF"
    fi

    if [[ "$stashed" == "1" ]]; then
        git -C "$KSU_REPO_DIR" stash pop || {
            warn "KernelSU local patch reapply had conflicts; resolve KernelSU-Next and rebuild."
            exit 1
        }
    fi

    link_ksu_source
    patch_ksu_config

    msg "KernelSU-Next source synced at $(git -C "$KSU_REPO_DIR" rev-parse --short HEAD)"
}

clean()
{
    msg "Cleaning output directory..."
    rm -rf "$OUT_DIR"
}

install_ksu()
{
    if [[ "$1" == "ksu" ]]; then
        msg "KernelSU-Next already synced at ${KSU_REF}"
    fi
}

make_defconfig()
{
    msg "Generating ${CONFIG_FILE}"

    make O="$OUT_DIR" \
        ARCH=arm64 \
        "$CONFIG_FILE"
}

compile_kernel()
{
    msg "Building kernel..."

    make -j"$(nproc --all)" \
        O="$OUT_DIR" \
        ARCH=arm64 \
        CC="$CC" \
        LLVM=1 \
        LLVM_IAS=1 \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        2>&1 | tee "$BUILD_LOG"
}

clean_anykernel_payload()
{
    msg "Cleaning AnyKernel3 package payload..."

    find "$ANYKERNEL_DIR" -name "*.zip" -type f -delete
    rm -rf \
        "$ANYKERNEL_DIR/.git" \
        "$ANYKERNEL_DIR/.github" \
        "$ANYKERNEL_DIR/.gitignore" \
        "$ANYKERNEL_DIR/README"* \
        "$ANYKERNEL_DIR/LICENSE"* \
        "$ANYKERNEL_DIR"/*.md \
        "$ANYKERNEL_DIR"/*.log \
        "$ANYKERNEL_DIR/out" \
        "$ANYKERNEL_DIR/toolchain" \
        "$ANYKERNEL_DIR/KernelSU-Next" 2>/dev/null || true
}

create_flashable_zip()
{
    (
        cd "$ANYKERNEL_DIR"
        zip -r9 "$KERNEL_DIR/$ZIP_NAME" . \
            -x "*.git*" \
            -x "*.github*" \
            -x "*README*" \
            -x "*LICENSE*" \
            -x "*.md" \
            -x "*.log" \
            -x "out/*" \
            -x "toolchain/*" \
            -x "KernelSU-Next/*"
    )
}

completion()
{
    local compiled_image=""
    local compiled_dtbo="$OUT_DIR/arch/arm64/boot/dtbo.img"
    local end diff

    if [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]]; then
        compiled_image="$OUT_DIR/arch/arm64/boot/Image.gz"
    elif [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]]; then
        compiled_image="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    fi

    if [[ -z "$compiled_image" ]]; then
        err "############################################"
        err "##         This Is Not Epic :'(          ##"
        err "############################################"
        err "Missing: Image.gz or Image.gz-dtb"
        exit 1
    fi

    msg "Packaging AnyKernel3..."

    rm -rf "$ANYKERNEL_DIR"

    git clone --depth=1 \
        -b "$ANYKERNEL_BRANCH" \
        "$ANYKERNEL_REPO" \
        "$ANYKERNEL_DIR"

    clean_anykernel_payload

    cp -f "$compiled_image" "$ANYKERNEL_DIR/"

    if [[ -f "$compiled_dtbo" ]]; then
        cp -f "$compiled_dtbo" "$ANYKERNEL_DIR/dtbo.img"
    else
        warn "dtbo.img not found, packaging kernel image only."
    fi

    rm -f "$KERNEL_DIR"/*.zip
    create_flashable_zip

    rm -rf "$ANYKERNEL_DIR"

    end=$(date +%s)
    diff=$((end - START))

    echo
    echo "Build Time: ${diff} seconds"
    echo
    msg "############################################"
    msg "############# OkThisIsEpic! ################"
    msg "############################################"
    echo
    echo "Output:"
    echo "$KERNEL_DIR/$ZIP_NAME"
}

usage()
{
    cat <<EOF
Usage: ./build.sh [deps] [ksu]

  deps  Install Ubuntu/Debian build dependencies with apt-get.
  ksu   Compatibility alias; KernelSU-Next sync runs by default.

Environment:
  KSU_REF=$KSU_REF
  KSU_LEGACY_BRANCH=$KSU_LEGACY_BRANCH
  KSU_AUTO_SYNC=$KSU_AUTO_SYNC
  CLANG_VERSION=$CLANG_VERSION
  ZIP_NAME=$ZIP_NAME
EOF
}

main()
{
    local ksu_arg=""

    while (($#)); do
        case "$1" in
            deps)
                install_deps
                ;;
            ksu)
                ksu_arg="ksu"
                ;;
            -h|--help|help)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done

    check_required_tools
    download_clang
    setup_env
    sync_submodules
    sync_ksu_legacy
    clean
    install_ksu "$ksu_arg"
    make_defconfig
    compile_kernel
    completion
}

main "$@"
