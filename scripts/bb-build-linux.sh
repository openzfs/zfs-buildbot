#!/bin/sh
#
# Example usage:
#
# export LINUX_DIR="$HOME/src/linux"
# export ZFS_DIR="$HOME/src/zfs"
# ./bb-build-linux.sh
#

LINUX_DIR=${LINUX_DIR:-$(readlink -f .)}
ZFS_DIR=${ZFS_DIR:-$(readlink -f ../zfs)}
MAKE_LOG="$LINUX_DIR/make.log"

set -x
cd $LINUX_DIR

# Configure the kernel for a default build.
sed -i '/EXTRAVERSION = / s/$/.zfs/' Makefile
make mrproper >>$MAKE_LOG 2>&1 || exit 1
make defconfig >>$MAKE_LOG 2>&1 || exit 1

# Enable ZFS and additional dependencies.
cat >>.config <<EOF
CONFIG_CRYPTO_DEFLATE=y
CONFIG_ZLIB_DEFLATE=y
CONFIG_KALLSYMS=y
CONFIG_EFI_PARTITION=y
EOF

# Prepare the kernel source.
make prepare >>$MAKE_LOG 2>&1 || exit 1

# Configure ZFS and add it to the kernel tree.
cd $ZFS_DIR
sh ./autogen.sh >>$MAKE_LOG 2>&1 || exit 1
./configure --enable-linux-builtin --with-linux=$LINUX_DIR \
    --with-linux-obj=$LINUX_DIR >>$MAKE_LOG 2>&1 || exit 1
./copy-builtin $LINUX_DIR >>$MAKE_LOG 2>&1 || exit 1

# Build the kernel.
cd $LINUX_DIR
# if we don't do this, make prints a warning
grep -v 'CONFIG_ZFS' .config > .tmpconfig
mv .tmpconfig .config
cat >> .config << EOF
CONFIG_ZFS=y
EOF
make -j$(nproc) >>$MAKE_LOG 2>&1 || exit 1
make -j$(nproc) modules >>$MAKE_LOG 2>&1 || exit 1

exit 0
