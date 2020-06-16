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

TEST_ZFSSTRESS_SKIP=${TEST_ZFSSTRESS_SKIP:-"Yes"}
if echo "$TEST_ZFSSTRESS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

ZFSSTRESS=${ZFSSTRESS:-"./runstress.sh"}
CONSOLE_LOG="$PWD/console.log"
KMEMLEAK_LOG="$PWD/kmemleak.log"
KMEMLEAK_FILE="/sys/kernel/debug/kmemleak"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
    dmesg >$CONSOLE_LOG
    sudo -E $ZPOOL destroy -f $TEST_ZFSSTRESS_POOL &>/dev/null
    sudo -E rm -f /etc/zfs/zpool.cache $TEST_ZFSSTRESS_VDEV
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
}
trap cleanup EXIT

set -x

TEST_ZFSSTRESS_URL=${TEST_ZFSSTRESS_URL:-"https://github.com/zfsonlinux/zfsstress/archive/"}
TEST_ZFSSTRESS_VER=${TEST_ZFSSTRESS_VER:-"master.tar.gz"}
TEST_ZFSSTRESS_RUNTIME=${TEST_ZFSSTRESS_RUNTIME:-300}
TEST_ZFSSTRESS_POOL=${TEST_ZFSSTRESS_POOL:-"tank"}
TEST_ZFSSTRESS_FS=${TEST_ZFSSTRESS_FS:-"fish"}
TEST_ZFSSTRESS_FSOPT=${TEST_ZFSSTRESS_FSOPT:-"-o overlay=on"}
TEST_ZFSSTRESS_VDEV=${TEST_ZFSSTRESS_VDEV:-"/var/tmp/vdev"}
TEST_ZFSSTRESS_DIR=${TEST_ZFSSTRESS_DIR:-"/$TEST_ZFSSTRESS_POOL/$TEST_ZFSSTRESS_FS"}
TEST_ZFSSTRESS_OPTIONS=${TEST_ZFSSTRESS_OPTIONS:-""}

# Tell zfsstress where to search for vdevs when importing its pool
export ZPOOL_IMPORT_OPT="-d `dirname $TEST_ZFSSTRESS_VDEV`"

set +x

wget -qO${TEST_ZFSSTRESS_VER} ${TEST_ZFSSTRESS_URL}${TEST_ZFSSTRESS_VER}||exit 1
tar -xzf ${TEST_ZFSSTRESS_VER} || exit 1
rm ${TEST_ZFSSTRESS_VER}

cd zfsstress*

if $(sudo -E test -e "$KMEMLEAK_FILE"); then
    echo "Kmemleak enabled.  Disabling scan thread and clearing log"
    sudo -E sh -c "echo scan=off >$KMEMLEAK_FILE"
    sudo -E sh -c "echo clear >$KMEMLEAK_FILE"
fi

# Create zpool and start with a clean slate.
sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1
sudo -E $ZPOOL destroy -f $TEST_ZFSSTRESS_POOL &>/dev/null
sudo -E rm -f /etc/zfs/zpool.cache $TEST_ZFSSTRESS_VDEV

dd if=/dev/zero of=$TEST_ZFSSTRESS_VDEV bs=1M count=1 seek=4095 || exit 1
sudo -E $ZPOOL create -f $TEST_ZFSSTRESS_POOL $TEST_ZFSSTRESS_VDEV || exit 1
sudo -E $ZFS create $TEST_ZFSSTRESS_FSOPT \
     $TEST_ZFSSTRESS_POOL/$TEST_ZFSSTRESS_FS || exit 1

sudo -E $ZFSSTRESS $TEST_ZFSSTRESS_OPTIONS $TEST_ZFSSTRESS_RUNTIME &
CHILD=$!
wait $CHILD
RESULT=$?

# Briefly delay to give any processes which are still exiting a chance to
# close any resources in the mount point so it can be cleanly unmounted.
sleep 5

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
