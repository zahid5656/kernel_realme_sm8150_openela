#!/bin/bash

# DEFINE COLORS
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
 
rm -rf out
make clean && make mrproper

kernel_dir="${PWD}"
CCACHE=$(command -v ccache)
objdir="${kernel_dir}/out"
anykernel=$kernel_dir/anykernel
builddir="${kernel_dir}/build"
ZIMAGE=$kernel_dir/out/arch/arm64/boot/Image.gz
kernel_name="samurai-4.14.357"
zip_name="$kernel_name-$(date +"%d%m%Y-%H%M")-KSU.zip"

CONFIG_FILE="samurai_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST=samurai
export KBUILD_BUILD_USER=titan
export KBUILD_BUILD_VERSION=1
# DEFINE VARIABLES & CLANG TOOLCHAIN
TC_DIR=${KERNEL_DIR}/toolchain
CLANG_DIR=$TC_DIR/clang-r522817
TC_CLONE_FILE=${KERNEL_DIR}/toolchain.sh

##Check if CLANG_DIR exists........
if ! [ -d "$TC_DIR" ]; then
    echo -e "${LRD}Toolchain not found! Cloning to $TC_DIR...${NC}"
    if ! bash $TC_CLONE_FILE-; then
        echo -e "${RED}Cloning failed! Aborting...${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Using clang directory: $CLANG_DIR${NC}"
export PATH="$CLANG_DIR/bin:$PATH"

##SYNC SUBMODULE
git submodule update --init --recursive

#Installing necessary components
! sudo apt-get install bc git gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig libssl-dev ccache cpio

# If KernelSU-Next Enabled
install_ksu() {

    if [[ "$1" == "ksu" ]]; then

        echo -e "${LGR}Installing KernelSU-Next...${NC}"

        curl -LSs \
        "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" \
        | bash -s legacy

        DEFCONFIG_FILE="arch/arm64/configs/${CONFIG_FILE}"

        echo -e "${LGR}Patching ${DEFCONFIG_FILE}${NC}"

        grep -qxF "CONFIG_KPROBES=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KPROBES=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KPROBE_EVENTS=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KPROBE_EVENTS=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KSU_KPROBE_HOOKS=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KSU_KPROBE_HOOKS=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KSU=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KSU=y" >> "$DEFCONFIG_FILE"

        echo -e "${LGR}KernelSU config added${NC}"
        echo -e "${LGR}KernelSU-Next installed${NC}"
    fi
}

make_defconfig()
{
    START=$(date +"%s")
    echo -e ${LGR} "########### Generating ${CONFIG_FILE}############${NC}"
    make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE}
#   make -s ARCH=${ARCH} O=${objdir} menuconfig
}

compile()
{
    cd ${kernel_dir}
    echo -e ${LGR} "######### Compiling kernel #########${NC}"
    make -j$(nproc --all) \
    O=out \
    ARCH=${ARCH}\
    CC="ccache clang" \
    CLANG_TRIPLE="aarch64-linux-gnu-" \
    CROSS_COMPILE="aarch64-linux-gnu-" \
    CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
    LLVM=1 \
    LLVM_IAS=1
}

completion()
{
    cd ${objdir}
    COMPILED_IMAGE=arch/arm64/boot/Image.gz
    COMPILED_DTBO=arch/arm64/boot/dtbo.img
    if [[ -f ${COMPILED_IMAGE} && ${COMPILED_DTBO} ]]; then
    
        git clone --depth=1 https://github.com/zahid5656/AnyKernel3.git $anykernel

        mv -f $ZIMAGE ${COMPILED_DTBO} $anykernel

        cd $anykernel
        find . -name "*.zip" -type f
        find . -name "*.zip" -type f -delete
        zip -r AnyKernel.zip *
        mv AnyKernel.zip $zip_name
        mv $anykernel/$zip_name $kernel_dir/$zip_name
        rm -rf $anykernel
        END=$(date +"%s")
        DIFF=$(($END - $START))
        echo -e ${LGR} "############################################"
        echo -e ${LGR} "########  Compiled Successfully!!  #########"
        echo -e ${LGR} "############################################${NC}"
        exit 0
    else
        echo -e ${RED} "############################################"
        echo -e ${RED} "##        ERROR!!! Unsccessfull :'(       ##"
        echo -e ${RED} "############################################${NC}"
        exit 1
    fi
}
install_ksu "$1"
make_defconfig
compile
completion
cd ${kernel_dir}