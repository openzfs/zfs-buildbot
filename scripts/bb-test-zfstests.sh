#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

TEST_ZFSTESTS_SKIP=${TEST_ZFSTESTS_SKIP:-"Yes"}
if echo "$TEST_ZFSTESTS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZFSTESTS=${ZFSTESTS:-"zfs-tests.sh"}
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

TEST_ZFSTESTS_DIR=${TEST_ZFSTESTS_DIR:-"/mnt"}
TEST_ZFSTESTS_DISKS=${TEST_ZFSTESTS_DISKS:-""}
TEST_ZFSTESTS_DISKSIZE=${TEST_ZFSTESTS_SIZE:-"2G"}
TEST_ZFSTESTS_OPTIONS=${TEST_ZFSTESTS_OPTIONS:-"-vx"}
TEST_ZFSTESTS_RUNFILE=${TEST_ZFSTESTS_RUNFILE:-"linux.run"}

if [ -n "$TEST_ZFSTESTS_DISKS" ]; then
	DISKS=${TEST_ZFSTESTS_DISKS}
	export DISKS
fi

set +x

sudo -E chmod 777 $TEST_ZFSTESTS_DIR
sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1
$ZFSTESTS $TEST_ZFSTESTS_OPTIONS \
    -d $TEST_ZFSTESTS_DIR \
    -s $TEST_ZFSTESTS_DISKSIZE \
    -r $TEST_ZFSTESTS_RUNFILE &
CHILD=$!

sleep 1
TEST_LOG=$(ls -t /var/tmp/test_results/*/log | head -1)
rm -f log
ln -s $TEST_LOG log

wait $CHILD
RESULT=$?

exit $RESULT
