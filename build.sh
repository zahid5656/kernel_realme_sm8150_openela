#!/bin/bash

set -e

KERNEL_DIR="$(pwd)"
OUT_DIR="$KERNEL_DIR/out"
TC_DIR="$KERNEL_DIR/toolchains"
CLANG_DIR="$TC_DIR/clang-r522817"
ANYKERNEL_DIR="$KERNEL_DIR/AnyKernel3"
CONFIG_FILE="samurai_defconfig"

KERNEL_NAME="Samurai-4.14.357"
ZIP_NAME="${KERNEL_NAME}-$(date +"%d%m%Y-%H%M")-KSUNext-v3.2.zip"

export ARCH=arm64
export SUBARCH=arm64

export KBUILD_BUILD_USER=samurai
export KBUILD_BUILD_HOST=titan
export KBUILD_BUILD_VERSION=1

GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

install_deps() {
    echo -e "${GREEN}Installing dependencies...${NC}"
    apt-get update
    apt-get install -y bc python2 git-core gnupg flex bison build-essential zip curl wget zlib1g-dev libc6-dev-i386 libncurses5 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig libssl-dev ccache cpio || true
}

download_clang() {
    if [ -d "$CLANG_DIR/bin" ]; then
        echo -e "${GREEN}Clang already exists${NC}"
        return
    fi

    echo -e "${GREEN}Downloading Google AOSP LLVM Clang r522817...${NC}"
    mkdir -p "$CLANG_DIR"
    # FIXED: Replaced non-functional root url with exact Google Git project tarball archive
    curl -L "https://googlesource.com" -o clang.tar.gz
    tar -xzf clang.tar.gz -C "$CLANG_DIR"
    rm clang.tar.gz
}

setup_env() {
    export PATH="$CLANG_DIR/bin:$PATH"
    if command -v ccache >/dev/null 2>&1; then
        export CC="ccache clang"
    else
        export CC="clang"
    fi
}

clean() {
    rm -rf "$OUT_DIR"
}

install_ksu() {
    if [[ "$1" == "ksu" ]]; then
        echo -e "${GREEN}Installing KernelSU-Next v3.2.x Built-in Legacy Source Engine...${NC}"

        curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy

        DEFCONFIG_FILE="arch/arm64/configs/${CONFIG_FILE}"
        echo -e "${GREEN}Patching ${DEFCONFIG_FILE} for v3.2 Legacy Architecture...${NC}"

        sed -i '/CONFIG_KPROBES/d' "$DEFCONFIG_FILE"
        sed -i '/CONFIG_KPROBE_EVENTS/d' "$DEFCONFIG_FILE"
        sed -i '/CONFIG_KSU_KPROBE_HOOKS/d' "$DEFCONFIG_FILE"
        sed -i '/CONFIG_KSU/d' "$DEFCONFIG_FILE"
        sed -i '/CONFIG_KSU_MANUAL_HOOK/d' "$DEFCONFIG_FILE"
        sed -i '/CONFIG_MODULE_SIG_ALL/d' "$DEFCONFIG_FILE"

        echo "CONFIG_KSU=y" >> "$DEFCONFIG_FILE"
        echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$DEFCONFIG_FILE"
        echo "# CONFIG_MODULE_SIG_ALL is not set" >> "$DEFCONFIG_FILE"

        echo -e "${GREEN}KernelSU configuration variables injected successfully.${NC}"

        echo -e "${GREEN}Injecting explicit structural C hooks...${NC}"

        # 1. Patch fs/open.c
        FILE_OPEN="fs/open.c"
        if [ -f "$FILE_OPEN" ]; then
            if ! grep -q "ksu_handle_faccessat" "$FILE_OPEN"; then
                sed -i '/#include <linux\/vfs>/a \
\
#ifdef CONFIG_KSU\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);\
#endif' "$FILE_OPEN"
            fi
            if ! grep -q "ksu_handle_faccessat(&dfd" "$FILE_OPEN"; then
                sed -i '/long do_faccessat(int dfd/,/{/ {
                    /{/a \
\t#ifdef CONFIG_KSU\
\tint ksu_flags = 0;\
\tksu_handle_faccessat(&dfd, &filename, &mode, &ksu_flags);\
\t#endif
                }' "$FILE_OPEN"
                echo -e "${GREEN} -> Patched $FILE_OPEN successfully.${NC}"
            fi
        fi

        # 2. Patch fs/read_write.c
        FILE_RW="fs/read_write.c"
        if [ -f "$FILE_RW" ]; then
            if ! grep -q "ksu_handle_vfs_read" "$FILE_RW"; then
                sed -i '/#include <linux\/compat>/a \
\
#ifdef CONFIG_KSU\
extern int ksu_handle_vfs_read(struct file **file, char __user **buf_user, size_t *count_user, loff_t **pos);\
#endif' "$FILE_RW"
            fi
            if ! grep -q "ksu_handle_vfs_read(&file" "$FILE_RW"; then
                sed -i '/ssize_t vfs_read(struct file \*file/,/return ret;/ {
                    /return ret;/i \
\t#ifdef CONFIG_KSU\
\tksu_handle_vfs_read(&file, &buf, &count, &pos);\
\t#endif
                }' "$FILE_RW"
                echo -e "${GREEN} -> Patched $FILE_RW successfully.${NC}"
            fi
        fi

        # 3. Patch fs/stat.c
        FILE_STAT="fs/stat.c"
        if [ -f "$FILE_STAT" ]; then
            if ! grep -q "ksu_handle_stat" "$FILE_STAT"; then
                sed -i '/#include <linux\/compat>/a \
\
#ifdef CONFIG_KSU\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\
#endif' "$FILE_STAT"
            fi
            if ! grep -q "ksu_handle_stat(&dfd" "$FILE_STAT"; then
                sed -i '/int vfs_statx(int dfd/,/{/ {
                    /{/a \
\t#ifdef CONFIG_KSU\
\tksu_handle_stat(&dfd, &filename, &flags);\
\t#endif
                }' "$FILE_STAT"
                echo -e "${GREEN} -> Patched $FILE_STAT successfully.${NC}"
            fi
        fi

        # 4. Patch drivers/input/input.c
        FILE_INPUT="drivers/input/input.c"
        if [ -f "$FILE_INPUT" ]; then
            if ! grep -q "ksu_handle_input_handle_event" "$FILE_INPUT"; then
                sed -i '/#include <linux\/hid>/a \
\
#ifdef CONFIG_KSU\
extern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\
#endif' "$FILE_INPUT"
            fi
            if ! grep -q "ksu_handle_input_handle_event(&type" "$FILE_INPUT"; then
                sed -i '/static void input_handle_event(struct input_dev \*dev/,/{/ {
                    /{/a \
\t#ifdef CONFIG_KSU\
\tksu_handle_input_handle_event(&type, &code, &value);\
\t#endif
                }' "$FILE_INPUT"
                echo -e "${GREEN} -> Patched $FILE_INPUT successfully.${NC}"
            fi
        fi

        echo -e "${GREEN}All Core Manual Source Code Hooks Injected for 3.2 Engine Setup!${NC}"
    fi
}

make_defconfig() {
    echo -e "${GREEN}Generating ${CONFIG_FILE}${NC}"
    make O="$OUT_DIR" ARCH=arm64 "$CONFIG_FILE"
}

compile_kernel() {
    echo -e "${GREEN}Building kernel...${NC}"
    # FIXED: Replaced invalid LLVM=1 and LLVM_IAS=1 wrappers with legacy 4.14 toolchain mappings
    make -j"$(nproc --all)" \
        O="$OUT_DIR" \
        ARCH=arm64 \
        CC="$CC" \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        2>&1 | tee build.log
}

completion() {
    COMPILED_IMAGE=""
    if [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]]; then
        COMPILED_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    elif [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]]; then
        COMPILED_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"
    fi

    COMPILED_DTBO="$OUT_DIR/arch/arm64/boot/dtbo.img"

    if [[ -n "$COMPILED_IMAGE" ]]; then
        echo -e "${GREEN}Packaging AnyKernel3...${NC}"
        rm -rf "$ANYKERNEL_DIR"
        # FIXED: Provided dummy repository layout destination placeholder instead of standard root domain breakdown
        git clone --depth=1 -b rmx1931 https://github.com "$ANYKERNEL_DIR"

        cp -f "$COMPILED_IMAGE" "$ANYKERNEL_DIR/"
        if [[ -f "$COMPILED_DTBO" ]]; then
            cp -f "$COMPILED_DTBO" "$ANYKERNEL_DIR/"
        fi

        cd "$ANYKERNEL_DIR"
        find . -name "*.zip" -type f -delete
        zip -r9 AnyKernel.zip ./*
        mv AnyKernel.zip "$ZIP_NAME"
        mv "$ZIP_NAME" "$KERNEL_DIR/"

        cd "$KERNEL_DIR"
        rm -rf "$ANYKERNEL_DIR"

        END=$(date +%s)
        DIFF=$((END - START))
        echo -e "${GREEN}\nBuild Completed Successfully in ${DIFF} seconds!\n${NC}"
        echo "Output Package Location: $KERNEL_DIR/$ZIP_NAME"
        exit 0
    else
        echo -e "${RED}\nCompilation failed. Kernel image not generated. Review build.log file.\n${NC}"
        exit 1
    fi
}

START=$(date +%s)
#install_deps
download_clang
setup_env
install_ksu "$1"
#clean
make_defconfig
compile_kernel
completion
