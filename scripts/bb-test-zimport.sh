#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

TEST_ZIMPORT_SKIP=${TEST_ZIMPORT_SKIP:-"No"}
if echo "$TEST_ZIMPORT_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 0
fi

ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZIMPORT=${ZIMPORT:-"zimport.sh"}
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

TEST_ZIMPORT_DIR=${TEST_ZIMPORT_DIR:-"/var/tmp/zimport"}
TEST_ZIMPORT_VERSIONS=${TEST_ZIMPORT_VERSIONS:-"master installed"}
TEST_ZIMPORT_POOLS=${TEST_ZIMPORT_POOLS:-"zol-0.6.1 zol-0.6.2 master installed"}
TEST_ZIMPORT_OPTIONS=${TEST_ZIMPORT_OPTIONS:-"-c"}

sudo -E dmesg -c >/dev/null
mkdir -p $TEST_ZIMPORT_DIR || exit 1
rm -Rf $TEST_ZIMPORT_DIR/src/spl/master || exit 1
rm -Rf $TEST_ZIMPORT_DIR/src/zfs/master || exit 1

sudo -E $ZIMPORT $TEST_ZIMPORT_OPTIONS -f $TEST_ZIMPORT_DIR \
    -s "$TEST_ZIMPORT_VERSIONS" -p "$TEST_ZIMPORT_POOLS" &
CHILD=$!
wait $CHILD
RESULT=$?

exit $RESULT
