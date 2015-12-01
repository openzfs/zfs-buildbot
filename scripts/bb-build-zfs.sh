#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

CONFIG_LOG="configure.log"
CONFIG_OPTIONS=${CONFIG_OPTIONS:-"--enable-debug"}
MAKE_LOG="make.log"
MAKE_OPTIONS=${MAKE_OPTIONS:-"-j$(nproc)"}

# Expect a custom Linux build in the ../linux/ directory.
if test "$LINUX_CUSTOM" = "yes"; then
    LINUX_DIR=$(readlink -f ../linux)
    LINUX_OPTIONS="--with-linux=$LINUX_DIR --with-linux-obj=$LINUX_DIR"
fi

set -x

./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1
./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1

exit 0
