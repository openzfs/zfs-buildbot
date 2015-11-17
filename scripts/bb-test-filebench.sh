#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

RND_VA_SPACE=$(cat /proc/sys/kernel/randomize_va_space)
TEST_FILEBENCH_SKIP=${TEST_FILEBENCH_SKIP:-"No"}
if echo "$TEST_FILEBENCH_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

ZPOOL=${ZPOOL:-"zpool"}
ZFS=${ZFS:-"zfs"}
ZFS_SH=${ZFS_SH:-"zfs.sh"}
FILEBENCH=${FILEBENCH:-"./filebench"}
CONFIG_LOG="$PWD/configure.log"
MAKE_LOG="$PWD/make.log"
CONSOLE_LOG="$PWD/console.log"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
    dmesg >$CONSOLE_LOG
    sudo -E sh -c "echo $RND_VA_SPACE >/proc/sys/kernel/randomize_va_space"
    sudo -E $ZPOOL destroy -f $TEST_FILEBENCH_POOL &>/dev/null
    sudo -E rm -f /etc/zfs/zpool.cache $TEST_FILEBENCH_VDEV
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
}
trap cleanup EXIT SIGTERM

set -x

TEST_FILEBENCH_URL=${TEST_FILEBENCH_URL:-"https://github.com/zfsonlinux/filebench/archive/"}
TEST_FILEBENCH_VER=${TEST_FILEBENCH_VER:-"zfs.tar.gz"}
TEST_FILEBENCH_RUNTIME=${TEST_FILEBENCH_RUNTIME:-10}
TEST_FILEBENCH_POOL=${TEST_FILEBENCH_POOL:-"tank"}
TEST_FILEBENCH_FS=${TEST_FILEBENCH_FS:-"filebench"}
TEST_FILEBENCH_VDEV=${TEST_FILEBENCH_VDEV:-"/var/tmp/vdev"}
TEST_FILEBENCH_DIR=${TEST_FILEBENCH_DIR:-"/$TEST_FILEBENCH_POOL/$TEST_FILEBENCH_FS"}
TEST_FILEBENCH_OPTIONS=${TEST_FILEBENCH_OPTIONS:-""}
declare -a TEST_FILEBENCH_WORKLOADS=(
    "compflow_demo"
    "copyfiles"
    "createfiles"
    "filemicro_create"
    "filemicro_createfiles"
    "filemicro_createrand"
    "filemicro_delete"
    "filemicro_rread"
    "filemicro_rwrite"
    "filemicro_rwritedsync"
    "filemicro_rwritefsync"
    "filemicro_seqread"
    "filemicro_seqwrite"
    "filemicro_seqwriterand"
    "filemicro_seqwriterandvargam"
    "filemicro_seqwriterandvartab"
    "filemicro_statfile"
    "filemicro_writefsync"
    "fileserver"
    "fivestreamread"
    "fivestreamwrite"
    "listdirs"
    "makedirs"
    "mongo"
    "netsfs"
    "networkfs"
    "openfiles"
    "randomfileaccess"
    "randomread"
    "randomrw"
    "randomwrite"
    "removedirs"
    "singlestreamread"
    "singlestreamwrite"
    "varmail"
)

wget -q ${TEST_FILEBENCH_URL}${TEST_FILEBENCH_VER} || exit 1
tar -xzf $TEST_FILEBENCH_VER || exit 1
rm $TEST_FILEBENCH_VER

cd filebench*
./configure >>$CONFIG_LOG 2>&1 || exit 1
make -j${nproc} >>$MAKE_LOG 2>&1 || exit 1

# Disable virtual address space randomization for filebench
sudo -E dmesg -c >/dev/null
sudo -E sh -c "echo 0 >/proc/sys/kernel/randomize_va_space"
sudo -E $ZFS_SH || exit 1

dd if=/dev/zero of=$TEST_FILEBENCH_VDEV bs=1M count=1 seek=4095 || exit 1
sudo -E $ZPOOL create -f $TEST_FILEBENCH_POOL $TEST_FILEBENCH_VDEV || exit 1
sudo -E $ZFS create $TEST_FILEBENCH_POOL/$TEST_FILEBENCH_FS || exit 1
sudo -E $ZFS set compression=lz4 $TEST_FILEBENCH_POOL/$TEST_FILEBENCH_FS

set +x

mkdir -p zfs-workloads

for (( i=0; i<${#TEST_FILEBENCH_WORKLOADS[@]}; i++ )); do
    WORKLOAD="${TEST_FILEBENCH_WORKLOADS[$i]}"
    WORKLOAD_FS="$TEST_FILEBENCH_POOL/$TEST_FILEBENCH_FS/${WORKLOAD}"
    WORKLOAD_DIR="$TEST_FILEBENCH_POOL\\/$TEST_FILEBENCH_FS\\/${WORKLOAD}"

    # Generate a customized workload from the given templates.
    sed 's/set $dir=\/tmp/set $dir=\/'$WORKLOAD_DIR'/' workloads/$WORKLOAD.f \
        >zfs-workloads/$WORKLOAD.f
    echo "run $TEST_FILEBENCH_RUNTIME" >>zfs-workloads/$WORKLOAD.f

    echo
    echo
    echo "=========================== ${WORKLOAD} ==========================="
    date

    # Create a new dataset for the test
    set -x
    sudo -E $ZFS create $WORKLOAD_FS || break
    sudo -E $FILEBENCH $TEST_FILEBENCH_OPTIONS -f zfs-workloads/${WORKLOAD}.f &
    CHILD=$!
    wait $CHILD
    RESULT=$?

    if [ $RESULT -ne 0 ]; then
        echo "${WORKLOAD} failed, error $RESULT"
        df -h
        sudo -E $ZFS list
        sudo -E $ZPOOL status
        sudo -E $ZFS destroy $WORKLOAD_FS
        break;
    fi

    sudo -E $ZFS destroy $WORKLOAD_FS || break
    set +x
done

set -x

exit $RESULT
