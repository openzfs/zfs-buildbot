#!/bin/sh -x

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

CONFIG_LOG="configure.log"
CONFIG_OPTIONS="--enable-debug"
MAKE_LOG="make.log"
MAKE_OPTIONS="-j$(nproc)"

./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1
./configure $CONFIG_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1

exit 0
