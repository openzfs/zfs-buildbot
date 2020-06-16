#!/bin/sh

if test -f /etc/buildworker; then
    . /etc/buildworker
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
FULL_LOG="$PWD/full.log"
KMEMLEAK_LOG="$PWD/kmemleak.log"
KMEMLEAK_FILE="/sys/kernel/debug/kmemleak"
DMESG_PID="0"
RESULT=0

cleanup()
{
    if [ -f "$TEST_LOG" ]; then
        RESULTS_DIR=$(awk '/^Log directory/ { print $3; exit 0 }' "$TEST_LOG")
        if [ -d "$RESULTS_DIR" ]; then
            # Generate a summary of results and place them in a different file.
            grep -A 1000 "Results Summary" "$TEST_LOG" > $SUMMARY_LOG
            echo "" >> $SUMMARY_LOG
            awk '/\[FAIL\]|\[KILLED\]/{ show=1; print; next; }
                /\[SKIP\]|\[PASS\]/{ show=0; } show' $FULL_LOG >> $SUMMARY_LOG

            # Preserve the results directory for future analysis, as:
            # <zfs-version>/<builder>/zts/zts-<runfile>-<date>.tar.xz
            if test -n "$UPLOAD_DIR"; then
                BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"
                mkdir -p "$UPLOAD_DIR/$BUILDER/zts"

                RESULTS_DATE=$(basename $RESULTS_DIR)
                RESULTS_NAME="zts-$TEST_ZFSTESTS_RUNFILE-$RESULTS_DATE"
                RESULTS_DIRNAME=$(dirname $RESULTS_DIR)

                # Rename the results to include the run file name and date.
                # Then compress the renamed directory for upload.
                mv "$RESULTS_DIR" "$RESULTS_DIRNAME/$RESULTS_NAME"
                tar -C "$RESULTS_DIRNAME" -cJ \
                    -f "$UPLOAD_DIR/$BUILDER/zts/$RESULTS_NAME.tar.xz" \
                    "$RESULTS_NAME"
            fi
        fi
    fi

    sudo -E $ZFS_SH -u

    if [ "$DMESG_PID" = "0" ]; then
        dmesg >$CONSOLE_LOG
    else
        kill $DMESG_PID
    fi
}
trap cleanup EXIT TERM

set -x

# If our environment specifies a runfile or set of disks, use those.
DEFAULT_ZFSTESTS_RUNFILE=${DEFAULT_ZFSTESTS_RUNFILE:-""}
DEFAULT_ZFSTESTS_DISKS=${DEFAULT_ZFSTESTS_DISKS:-""}
DEFAULT_ZFSTESTS_DISKSIZE=${DEFAULT_ZFSTESTS_DISKSIZE:-""}
DEFAULT_ZFSTESTS_TAGS=${DEFAULT_ZFSTESTS_TAGS:-"functional"}
DEFAULT_ZFSTESTS_PERF_RUNTIME=${DEFAULT_ZFSTESTS_PERF_RUNTIME:-180}
DEFAULT_ZFSTESTS_PERF_FS_OPTS=${DEFAULT_ZFSTESTS_PERF_FS_OPTS:-"-o recsize=1M -o compress=lz4"}

TEST_ZFSTESTS_DIR=${TEST_ZFSTESTS_DIR:-"/mnt/"}
TEST_ZFSTESTS_DISKS=${TEST_ZFSTESTS_DISKS:-"$DEFAULT_ZFSTESTS_DISKS"}
TEST_ZFSTESTS_DISKSIZE=${TEST_ZFSTESTS_DISKSIZE:-"$DEFAULT_ZFSTESTS_DISKSIZE"}
TEST_ZFSTESTS_ITERS=${TEST_ZFSTESTS_ITERS:-"1"}
TEST_ZFSTESTS_OPTIONS=${TEST_ZFSTESTS_OPTIONS:-"-vx"}
TEST_ZFSTESTS_RUNFILE=${TEST_ZFSTESTS_RUNFILE:-"$DEFAULT_ZFSTESTS_RUNFILE"}
TEST_ZFSTESTS_TAGS=${TEST_ZFSTESTS_TAGS:-"$DEFAULT_ZFSTESTS_TAGS"}
TEST_ZFSTESTS_PROFILE=${TEST_ZFSTESTS_PROFILE:-"No"}

# Environment variables which control the performance test suite.
PERF_RUNTIME=${TEST_ZFSTESTS_PERF_RUNTIME:-$DEFAULT_ZFSTESTS_PERF_RUNTIME}
PERF_FS_OPTS=${TEST_ZFSTESTS_PERF_FS_OPTS:-"$DEFAULT_ZFSTESTS_PERF_FS_OPTS"}

set +x

case $(uname) in
FreeBSD)
	if ! kldstat -qn openzfs; then
		sudo -E $ZFS_SH
	fi
	;;
Linux)
	if ! test -e /sys/module/zfs; then
	    sudo -E $ZFS_SH
	fi
	;;
*)
	sudo -E $ZFS_SH
	;;
esac

# Performance profiling disabled by default due to size of profiling data.
if echo "$TEST_ZFSTESTS_PROFILE" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    case "$BB_NAME" in
    Amazon*)
        sudo yum -y install perf
        ;;
    *)
        echo "Performance profiling with 'perf' disabled."
        ;;
    esac
fi

export PERF_RUNTIME PERF_FS_OPTS

# Default to loopback devices created by zfs-tests.sh when not specified.
# If disks are given then optionally partition them if a size is provided.
if [ -n "$TEST_ZFSTESTS_DISKS" ]; then
    if [ -n "$TEST_ZFSTESTS_DISKSIZE" ]; then
        DISKS=""
        for disk in $TEST_ZFSTESTS_DISKS; do
            set -x
            sudo -E parted --script /dev/$disk mklabel gpt
            sudo -E parted --script /dev/$disk mkpart logical 1MiB $TEST_ZFSTESTS_DISKSIZE
            set +x
            DISKS="$DISKS ${disk}1"
        done
    else
        DISKS="$TEST_ZFSTESTS_DISKS"
    fi
    export DISKS
fi

if $(sudo -E test -e "$KMEMLEAK_FILE"); then
    echo "Kmemleak enabled.  Disabling scan thread and clearing log"
    sudo -E sh -c "echo scan=off >$KMEMLEAK_FILE"
    sudo -E sh -c "echo clear >$KMEMLEAK_FILE"
fi

sudo -E chmod 777 $TEST_ZFSTESTS_DIR
sudo -E dmesg -c >/dev/null

if $(dmesg -h 2>/dev/null | grep -qe '-w'); then
    dmesg -w >$CONSOLE_LOG &
    DMESG_PID=$!
else
    touch $CONSOLE_LOG
fi

ln -s /var/tmp/test_results/current/log $FULL_LOG

set -x
$ZFS_TESTS_SH $TEST_ZFSTESTS_OPTIONS \
    ${TEST_ZFSTESTS_RUNFILE:+-r $TEST_ZFSTESTS_RUNFILE} \
    -d $TEST_ZFSTESTS_DIR \
    -I $TEST_ZFSTESTS_ITERS \
    -T $TEST_ZFSTESTS_TAGS > $TEST_LOG 2>&1
RESULT=$?
set +x

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
