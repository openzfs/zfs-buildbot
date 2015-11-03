#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

TEST_ZILTEST_SKIP=${TEST_ZILTEST_SKIP:-"No"}
if echo "$TEST_ZILTEST_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 0
fi

ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZILTEST=${ZILTEST:-"ziltest.sh"}
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

TEST_ZILTEST_OPTIONS=${TEST_ZILTEST_OPTIONS:-""}

sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1
sudo -E $ZILTEST $TEST_ZILTEST_OPTIONS &
CHILD=$!
wait $CHILD
RESULT=$?

exit $RESULT
