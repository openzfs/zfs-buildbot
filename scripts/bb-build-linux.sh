#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

CONFIG_LOG="configure.log"
CONFIG_FILE=".config"
MAKE_LOG="make.log"
MAKE_OPTIONS=${MAKE_OPTIONS:-"-j$(nproc)"}

# Customize the kernel for a minimal ZFS build.
sed -i '/EXTRAVERSION = / s/$/.zfs/' Makefile
make mrproper >>$CONFIG_LOG 2>&1 || exit 1
make defconfig >>$CONFIG_LOG 2>&1 || exit 1
cat >>$CONFIG_FILE <<EOF
CONFIG_CRYPTO_PCOMP=y
CONFIG_CRYPTO_ZLIB=y
CONFIG_ZLIB_DEFLATE=y
CONFIG_KALLSYMS=y
CONFIG_EFI_PARTITION=y
EOF

# Expect a spl and zfs directory to apply source from.
if test "$LINUX_BUILTIN" = "yes"; then
    LINUX_DIR=$(readlink -f ../linux)
    LINUX_OPTIONS="--with-linux=$LINUX_DIR --with-linux-obj=$LINUX_DIR"
    CONFIG_OPTIONS="--enable-linux-builtin"

    set -x
    make prepare scripts >>$CONFIG_LOG 2>&1 || exit 1
    cd ../spl >>$CONFIG_LOG 2>&1 || exit 1
    sh ./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1
    ./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
    ./copy-builtin $LINUX_DIR >>$CONFIG_LOG 2>&1 || exit 1
    cd ../zfs >>$CONFIG_LOG 2>&1 || exit 1
    sh ./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1
    ./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
    ./copy-builtin $LINUX_DIR >>$CONFIG_LOG 2>&1 || exit 1
    cd ../linux >>$CONFIG_LOG 2>&1 || exit 1
    echo "CONFIG_SPL=y" >>$CONFIG_FILE
    echo "CONFIG_ZFS=y" >>$CONFIG_FILE
fi

set -x

make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
make $MAKE_OPTIONS modules >>$MAKE_LOG 2>&1 || exit 1

exit 0
