#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

TEST_ZTEST_SKIP=${TEST_ZTEST_SKIP:-"No"}
if echo "$TEST_ZTEST_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZTEST=${ZTEST:-"ztest"}
CONSOLE_LOG="$PWD/console.log"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
    dmesg >$CONSOLE_LOG
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
}
trap cleanup EXIT SIGTERM

set -x

TEST_ZTEST_TIMEOUT=${TEST_ZTEST_TIMEOUT:-900}
TEST_ZTEST_DIR=${TEST_ZTEST_DIR:-"/mnt/"}
TEST_ZTEST_OPTIONS=${TEST_ZTEST_OPTIONS:-"-V"}

sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1
sudo -E $ZTEST $TEST_ZTEST_OPTIONS -T $TEST_ZTEST_TIMEOUT -f $TEST_ZTEST_DIR &
CHILD=$!
wait $CHILD
RESULT=$?

if test $RESULT != 0; then
    echo "Exited ztest with error $RESULT"
    exit 1
fi

exit $RESULT
