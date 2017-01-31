#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
	. /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
	. ../TEST
fi

TEST_ZFSTESTS_SKIP=${TEST_ZFSTESTS_SKIP:-"No"}
if echo "$TEST_ZFSTESTS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
	echo "Skipping disabled test"
	exit 3
fi

ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZFSTESTS=${ZFSTESTS:-"zfs-tests.sh"}
CONSOLE_LOG="$PWD/console.log"
KMEMLEAK_LOG="$PWD/kmemleak.log"
KMEMLEAK_FILE="/sys/kernel/debug/kmemleak"
RESULT=0

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

# If our environment specifies a runfile or set of disks, use those.
DEFAULT_ZFSTESTS_RUNFILE=${DEFAULT_ZFSTESTS_RUNFILE:-"linux.run"}
DEFAULT_ZFSTESTS_DISKS=${DEFAULT_ZFSTESTS_DISKS:-""}

TEST_ZFSTESTS_DIR=${TEST_ZFSTESTS_DIR:-"/mnt/"}
TEST_ZFSTESTS_DISKS=${TEST_ZFSTESTS_DISKS:-"$DEFAULT_ZFSTESTS_DISKS"}
TEST_ZFSTESTS_DISKSIZE=${TEST_ZFSTESTS_SIZE:-"4G"}
TEST_ZFSTESTS_OPTIONS=${TEST_ZFSTESTS_OPTIONS:-"-vx"}
TEST_ZFSTESTS_RUNFILE=${TEST_ZFSTESTS_RUNFILE:-"$DEFAULT_ZFSTESTS_RUNFILE"}

if [ -n "$TEST_ZFSTESTS_DISKS" ]; then
	DISKS=${TEST_ZFSTESTS_DISKS}
	export DISKS
fi

set +x

if $(sudo -E test -e "$KMEMLEAK_FILE"); then
	echo "Kmemleak enabled.  Disabling scan thread and clearing log"
	sudo -E sh -c "echo scan=off >$KMEMLEAK_FILE"
	sudo -E sh -c "echo clear >$KMEMLEAK_FILE"
fi

sudo -E chmod 777 $TEST_ZFSTESTS_DIR
sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1

ln -s /var/tmp/test_results/current/log log

$ZFSTESTS $TEST_ZFSTESTS_OPTIONS \
    -d $TEST_ZFSTESTS_DIR \
    -s $TEST_ZFSTESTS_DISKSIZE \
    -r $TEST_ZFSTESTS_RUNFILE

# FAILURE: One or more test cases failed.
grep "\[FAIL\]" log && RESULT=1

if $(sudo -E test -e "$KMEMLEAK_FILE"); then
	# Scan must be run twice to ensure all leaks are detected.
	sudo -E sh -c "echo scan >$KMEMLEAK_FILE"
	sudo -E sh -c "echo scan >$KMEMLEAK_FILE"
	sudo -E cat $KMEMLEAK_FILE >$KMEMLEAK_LOG

	if [ -s "$KMEMLEAK_LOG" ]; then
		echo "Kmemleak detected see $KMEMLEAK_LOG"
		[ $RESULT -eq 0 ] && RESULT=2
	else
		echo "Kmemleak detected no leaks" >$KMEMLEAK_LOG
	fi
fi

exit $RESULT
