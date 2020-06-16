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

TEST_XFSTESTS_SKIP=${TEST_XFSTESTS_SKIP:-"Yes"}
if echo "$TEST_XFSTESTS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

XFSTESTS=${XFSTESTS:-"./check"}
CONFIG_LOG="$PWD/configure.log"
MAKE_LOG="$PWD/make.log"
CONSOLE_LOG="$PWD/console.log"
KMEMLEAK_LOG="$PWD/kmemleak.log"
KMEMLEAK_FILE="/sys/kernel/debug/kmemleak"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
    dmesg >$CONSOLE_LOG
    sudo -E $ZPOOL destroy -f $TEST_XFSTESTS_POOL &>/dev/null
    sudo -E rm -f /etc/zfs/zpool.cache $TEST_XFSTESTS_VDEV
    sudo -E rm -Rf $TEST_DIR $SCRATCH_MNT
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
}
trap cleanup EXIT

set -x

TEST_XFSTESTS_URL=${TEST_XFSTESTS_URL:-"https://github.com/zfsonlinux/xfstests/archive/"}
TEST_XFSTESTS_VER=${TEST_XFSTESTS_VER:-"zfs.tar.gz"}
TEST_XFSTESTS_POOL=${TEST_XFSTESTS_POOL:-"tank"}
TEST_XFSTESTS_FS=${TEST_XFSTESTS_FS:-"xfstests"}
TEST_XFSTESTS_VDEV=${TEST_XFSTESTS_VDEV:-"/var/tmp/vdev"}
TEST_XFSTESTS_OPTIONS=${TEST_XFSTESTS_OPTIONS:-""}

# Exported for use by xfstests.
export TEST_DEV="$TEST_XFSTESTS_POOL/$TEST_XFSTESTS_FS"
export TEST_DIR="/$TEST_XFSTESTS_POOL/$TEST_XFSTESTS_FS"
export SCRATCH_DEV="$TEST_XFSTESTS_POOL/$TEST_XFSTESTS_FS-scratch"
export SCRATCH_MNT="/$TEST_XFSTESTS_POOL/$TEST_XFSTESTS_FS-scratch"

set +x

wget -qO${TEST_XFSTESTS_VER} ${TEST_XFSTESTS_URL}${TEST_XFSTESTS_VER} || exit 1
tar -xzf ${TEST_XFSTESTS_VER} || exit 1
rm ${TEST_XFSTESTS_VER}

cd xfstests*
autoheader >>$CONFIG_LOG 2>&1 || exit 1
autoconf >>$CONFIG_LOG 2>&1 || exit 1
./configure >>$CONFIG_LOG 2>&1 || exit 1
make -j$(nproc) >>$MAKE_LOG 2>&1 || exit 1

if $(sudo -E test -e "$KMEMLEAK_FILE"); then
    echo "Kmemleak enabled.  Disabling scan thread and clearing log"
    sudo -E sh -c "echo scan=off >$KMEMLEAK_FILE"
    sudo -E sh -c "echo clear >$KMEMLEAK_FILE"
fi

# Create zpool and start with a clean slate
sudo -E dmesg -c >/dev/null
sudo -E mkdir -p $TEST_DIR $SCRATCH_MNT
sudo -E $ZFS_SH || exit 1
dd if=/dev/zero of=$TEST_XFSTESTS_VDEV bs=1M count=1 seek=4095 || exit 1
sudo -E $ZPOOL create -m legacy -O acltype=posixacl \
    -f $TEST_XFSTESTS_POOL $TEST_XFSTESTS_VDEV || exit 1

#
# Run xfstests skipping tests are currently unsupported
# -zfs Filesystem type 'zfs'
# -x aio      - Skip aio tests until xfstest is updated
# -x dio      - Skip dio tests not yet implemented
# -x sendfile - Skip sendfile tests not yet implemented
#
sudo -E $XFSTESTS -zfs -x aio -x dio -x sendfile -x user &
CHILD=$!
wait $CHILD
RESULT=$?

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
