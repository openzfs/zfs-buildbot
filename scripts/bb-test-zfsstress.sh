#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

TEST_ZFSSTRESS_SKIP=${TEST_ZFSSTRESS_SKIP:-"No"}
if echo "$TEST_ZFSSTRESS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

ZPOOL=${ZPOOL:-"zpool"}
ZFS=${ZFS:-"zfs"}
ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZFSSTRESS=${ZFSSTRESS:-"./runstress.sh"}
CONSOLE_LOG="$PWD/console.log"

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
trap cleanup EXIT SIGTERM

set -x

TEST_ZFSSTRESS_URL=${TEST_ZFSSTRESS_URL:-"https://github.com/zfsonlinux/zfsstress/archive/"}
TEST_ZFSSTRESS_VER=${TEST_ZFSSTRESS_VER:-"master.tar.gz"}
TEST_ZFSSTRESS_RUNTIME=${TEST_ZFSSTRESS_RUNTIME:-300}
TEST_ZFSSTRESS_POOL=${TEST_ZFSSTRESS_POOL:-"tank"}
TEST_ZFSSTRESS_FS=${TEST_ZFSSTRESS_FS:-"fish"}
TEST_ZFSSTRESS_VDEV=${TEST_ZFSSTRESS_VDEV:-"/var/tmp/vdev"}
TEST_ZFSSTRESS_DIR=${TEST_ZFSSTRESS_DIR:-"/$TEST_ZFSSTRESS_POOL/$TEST_ZFSSTRESS_FS"}
TEST_ZFSSTRESS_OPTIONS=${TEST_ZFSSTRESS_OPTIONS:-""}

wget -qO${TEST_ZFSSTRESS_VER} ${TEST_ZFSSTRESS_URL}${TEST_ZFSSTRESS_VER}||exit 1
tar -xzf ${TEST_ZFSSTRESS_VER} || exit 1
rm ${TEST_ZFSSTRESS_VER}

cd zfsstress*

# Create zpool and start with a clean slate.
sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1
sudo -E $ZPOOL destroy -f $TEST_ZFSSTRESS_POOL &>/dev/null
sudo -E rm -f /etc/zfs/zpool.cache $TEST_ZFSSTRESS_VDEV

dd if=/dev/zero of=$TEST_ZFSSTRESS_VDEV bs=1M count=1 seek=4095 || exit 1
sudo -E $ZPOOL create -f $TEST_ZFSSTRESS_POOL $TEST_ZFSSTRESS_VDEV || exit 1
sudo -E $ZFS create $TEST_ZFSSTRESS_POOL/$TEST_ZFSSTRESS_FS || exit 1

sudo -E $ZFSSTRESS $TEST_ZFSSTRESS_OPTIONS $TEST_ZFSSTRESS_RUNTIME &
CHILD=$!
wait $CHILD
RESULT=$?

# Briefly delay to give any processes which are still exiting a chance to
# close any resources in the mount point so it can be cleanly unmounted.
sleep 5

exit $RESULT
