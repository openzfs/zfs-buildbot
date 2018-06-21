#!/bin/sh

if test -f /etc/buildslave; then
    . /etc/buildslave
fi

if test -f ./TEST; then
    . ./TEST
else
    echo "Missing $PWD/TEST configuration file"
    exit 1
fi

TEST_ZFSTESTS_SKIP=${TEST_ZFSTESTS_SKIP:-"No"}
if echo "$TEST_ZFSTESTS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

CONSOLE_LOG="$PWD/console.log"
SUMMARY_LOG="$PWD/summary.log"
TEST_LOG="$PWD/test.log"
KMEMLEAK_LOG="$PWD/kmemleak.log"
KMEMLEAK_FILE="/sys/kernel/debug/kmemleak"
RESULT=0

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
# Generate a summary of results and place them in a different file.
cleanup()
{
    dmesg >$CONSOLE_LOG
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG

    if [ -f "$TEST_LOG" ]; then
        grep -A 1000 "Results Summary" "$TEST_LOG" > $SUMMARY_LOG
        echo "" >> $SUMMARY_LOG
        awk '/\[FAIL\]|\[KILLED\]/{ show=1; print; next; }
            /\[SKIP\]|\[PASS\]/{ show=0; } show' log >> $SUMMARY_LOG
    fi
}
trap cleanup EXIT

set -x

# If our environment specifies a runfile or set of disks, use those.
DEFAULT_ZFSTESTS_RUNFILE=${DEFAULT_ZFSTESTS_RUNFILE:-"linux.run"}
DEFAULT_ZFSTESTS_DISKS=${DEFAULT_ZFSTESTS_DISKS:-""}
DEFAULT_ZFSTESTS_TAGS=${DEFAULT_ZFSTESTS_TAGS:-"functional"}

TEST_ZFSTESTS_DIR=${TEST_ZFSTESTS_DIR:-"/mnt/"}
TEST_ZFSTESTS_DISKS=${TEST_ZFSTESTS_DISKS:-"$DEFAULT_ZFSTESTS_DISKS"}
TEST_ZFSTESTS_DISKSIZE=${TEST_ZFSTESTS_DISKSIZE:-"4G"}
TEST_ZFSTESTS_ITERS=${TEST_ZFSTESTS_ITERS:-"1"}
TEST_ZFSTESTS_OPTIONS=${TEST_ZFSTESTS_OPTIONS:-"-vx"}
TEST_ZFSTESTS_RUNFILE=${TEST_ZFSTESTS_RUNFILE:-"$DEFAULT_ZFSTESTS_RUNFILE"}
TEST_ZFSTESTS_TAGS=${TEST_ZFSTESTS_TAGS:-"$DEFAULT_ZFSTESTS_TAGS"}

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

$ZFS_TESTS_SH $TEST_ZFSTESTS_OPTIONS \
    -d $TEST_ZFSTESTS_DIR \
    -s $TEST_ZFSTESTS_DISKSIZE \
    -r $TEST_ZFSTESTS_RUNFILE \
    -I $TEST_ZFSTESTS_ITERS \
    -T $TEST_ZFSTESTS_TAGS > $TEST_LOG 2>&1
RC=$?

if $(dmesg | grep "oom-killer"); then
    echo "Out-of-memory (OOM) killer invocation detected"
    [ $RESULT -eq 0 ] && RESULT=2
fi

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
