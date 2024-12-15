#! /usr/bin/env bash

#
# Rissu Kernel Project
#

if [ -d /rsuntk ]; then
export CROSS_COMPILE=/rsuntk/toolchains/aarch64-linux-android/bin/aarch64-linux-android-
export PATH=/rsuntk/toolchains/clang-11/bin:$PATH
fi

setconfig() { # fmt: setconfig enable/disable <CONFIG_NAME>
	if [ -d $(pwd)/scripts ]; then
		./scripts/config --file ./out/.config --`echo $1` CONFIG_`echo $2`
	else
		pr_err "Folder scripts not found!"
	fi
}

if [[ $KERNELSU = "true" ]]; then
    curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main
else
    echo -e "KernelSU is disabled. Add 'KERNELSU=true' or 'export KERNELSU=true' to enable"
fi

# generate simple c file
if [ ! -e utsrelease.c ]; then
echo "/* Generated file by `basename $0` */
#include <stdio.h>
#include \"out/include/generated/utsrelease.h\"

char utsrelease[] = UTS_RELEASE;

int main() {
	printf(\"%s\n\", utsrelease);
	return 0;
}" > utsrelease.c
fi

usage() {
	echo -e "Usage: bash `basename $0` <build_target> <-j | --jobs> <(job_count)> <defconfig>"
	printf "\tbuild_target: kernel, config\n"
	printf "\t-j or --jobs: <int>\n"
	printf "\tavailable defconfig: `ls arch/arm64/configs`\n"
	echo ""
	printf "NOTE: Run: \texport CROSS_COMPILE=\"<PATH_TO_ANDROID_CC>\"\n"
	printf "\t\texport PATH=\"<PATH_TO_LLVM>\"\n"
	printf "before running this script!\n"
	exit;
}

if [ $# != 4 ]; then
	usage;
fi

pr_invalid() {
	echo -e "Invalid args: $@"
	exit
}

BUILD_TARGET="$1"
FIRST_JOB="$2"
JOB_COUNT="$3"
DEFCONFIG="$4"

if [ "$BUILD_TARGET" = "kernel" ]; then
	BUILD="kernel"
elif [ "$BUILD_TARGET" = "defconfig" ]; then
	BUILD="defconfig"
elif [ "$BUILD_TARGET" = "clean" ]; then
	if [ -d $(pwd)/out ]; then
		rm -rf out
		exit
	elif [ -f $(pwd)/.config ]; then
		make clean
		make mrproper
		exit
	else
		echo -e "All clean."
		exit
	fi
else
	pr_invalid $1
fi

if [ "$FIRST_JOB" = "-j" ] || [ "$FIRST_JOB" = "--jobs" ]; then
	if [ ! -z $JOB_COUNT ]; then
		ALLOC_JOB=$JOB_COUNT
	else
		pr_invalid $3
	fi
else
	pr_invalid $2
fi

if [ ! -z "$DEFCONFIG" ]; then
	BUILD_DEFCONFIG="$DEFCONFIG"
else
	pr_invalid $4
fi

DEFAULT_ARGS="
CONFIG_BUILD_ARM64_DT_OVERLAY=y
CONFIG_SECTION_MISMATCH_WARN_ONLY=y
ARCH=arm64
"
IMAGE="$(pwd)/out/arch/arm64/boot/Image"

if [ "$LLVM" = "1" ]; then
	LLVM_="true"
	DEFAULT_ARGS+=" LLVM=1"
	export LLVM=1
	if [ "$LLVM_IAS" = "1" ]; then
		LLVM_IAS_="true"
		DEFAULT_ARGS+=" LLVM_IAS=1"
		export LLVM_IAS=1
	fi
else
	LLVM_="false"
	if [ "$LLVM_IAS" != "1" ]; then
		LLVM_IAS_="false"
	fi
fi

export PROJECT_NAME="a23"
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export DTC_EXT=$(pwd)/tools/dtc

pr_sum() {
	if [ -z $KBUILD_BUILD_USER ]; then
		KBUILD_BUILD_USER="`whoami`"
	fi
	if [ -z $KBUILD_BUILD_HOST ]; then
		KBUILD_BUILD_HOST="`hostname`"
	fi
	
	echo ""
	echo -e "Host Arch: `uname -m`"
	echo -e "Host Kernel: `uname -r`"
	echo -e "Host gnumake: `make -v | grep -e "GNU Make"`"
	echo ""
	echo -e "Linux version: `make kernelversion`"
	echo -e "Kernel builder user: $KBUILD_BUILD_USER"
	echo -e "Kernel builder host: $KBUILD_BUILD_HOST"
	echo -e "Build date: `date`"
	echo -e "Build target: `echo $BUILD`"
	echo -e "Arch: $ARCH"
	echo -e "Defconfig: $BUILD_DEFCONFIG"
	echo -e "Allocated core: $ALLOC_JOB"
	echo -e ""
	echo -e "LLVM: $LLVM_"
	echo -e "LLVM_IAS: $LLVM_IAS_"
	echo -e ""
}

# call summary
pr_sum

pr_post_build() {
	echo ""
	echo -e "## Build $@ at `date` ##"
	echo ""
	
	if [ "$@" = "failed" ]; then
		exit
	fi
}

post_build() {
	DATE=$(date +'%Y%m%d%H%M%S')
	if [ -d $(pwd)/.git ]; then
		GITSHA=$(git rev-parse --short HEAD)
	else
		GITSHA="localbuild"
	fi
	AK3="$(pwd)/AnyKernel3"
	ZIP="AnyKernel3-`echo $DEVICE`_$GITSHA-$DATE"
	if [[ "$QCA_IS_MODULE" = "true" ]]; then
		sed -i "s/do\.modules=.*/do.modules=1/" "$(pwd)/AnyKernel3/anykernel.sh"
		## qca_cld3_wlan.ko strip code start
		echo "- Stripping wlan.ko"
		llvm-strip $(pwd)/out/drivers/staging/qcacld-3.0/wlan.ko --strip-unneeded
		## create copy of wlan.ko code start
		cp $(pwd)/out/drivers/staging/qcacld-3.0/wlan.ko $AK3/modules/vendor/lib/modules/qca_cld3_wlan.ko
		## create copy of wlan.ko code end
		## qca_cld3_wlan.ko strip code end
		## copy .ko to anykernel3 code start
		cp $(pwd)/out/drivers/staging/qcacld-3.0/wlan.ko $AK3/modules/vendor/lib/modules
		## copy .ko to anykernel3 code end
	fi
	if [ -d $AK3 ]; then
		echo "- Creating AnyKernel3"
		gcc -CC utsrelease.c -o getutsrel
		UTSRELEASE=$(./getutsrel)
		sed -i "s/kernel\.string=.*/kernel.string=$UTSRELEASE/" "$(pwd)/AnyKernel3/anykernel.sh"
		cp $IMAGE $AK3
		cd $AK3
		zip -r9 ../`echo $ZIP`.zip *
		# CI will clean itself post-build, so we don't need to clean
		# Also avoid small AnyKernel3 zip issue!
		if [ $IS_CI != "true" ]; then
			echo "- Host is not Automated CI, cleaning dirs"
			rm $AK3/Image && rm getutsrel && rm utsrelease.c
		fi
	fi
}

# build target
if [ "$BUILD" = "kernel" ]; then
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS` `echo $BUILD_DEFCONFIG`
	if [ "$KERNELSU" = "true" ]; then		
    		setconfig enable KSU
	fi
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS`
	if [ -e $IMAGE ]; then
		pr_post_build "completed"
		post_build
	else
		pr_post_build "failed"
	fi
elif [ "$BUILD" = "defconfig" ]; then
	make -j`echo $ALLOC_JOB` -C $(pwd) O=$(pwd)/out `echo $DEFAULT_ARGS` `echo $BUILD_DEFCONFIG`
fi