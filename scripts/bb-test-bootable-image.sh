#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
    . ../TEST
fi

TEST_BOOTABLE_IMAGE_SKIP=${TEST_BOOTABLE_IMAGE_SKIP:-"No"}
if echo "$TEST_BOOTABLE_IMAGE_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

ZFS_SH=${ZFS_SH:-"zfs.sh"}
CONSOLE_LOG="$PWD/console.log"
OUTPUT_LOG="$PWD/output.log"

case "$BB_NAME" in
Fedora*)
    true
    ;;

*)
    echo "$BB_NAME unknown platform, skipping image test" >>$OUTPUT_LOG 2>&1
    exit 3
    ;;
esac

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

TEST_BOOTABLE_IMAGE_URL=${TEST_BOOTABLE_IMAGE_URL:-"https://github.com/Rudd-O/zfs-fedora-installer/archive/master.tar.gz"}
TEST_BOOTABLE_IMAGE_TAR=${TEST_BOOTABLE_IMAGE_TAR:-"zfs-fedora-installer.tar.gz"}
TEST_BOOTABLE_IMAGE_POOL=${TEST_BOOTABLE_IMAGE_POOL:-"bootable_image"}
TEST_BOOTABLE_IMAGE_VDEV=${TEST_BOOTABLE_IMAGE_VDEV:-"/var/tmp/bootable_image.img"}
TEST_BOOTABLE_IMAGE_OPTIONS=${TEST_BOOTABLE_IMAGE_OPTIONS:-""}

echo -n >$OUTPUT_LOG 2>&1

sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1

wget -qO${TEST_BOOTABLE_IMAGE_TAR} ${TEST_BOOTABLE_IMAGE_URL} || exit 1
tar -xz --strip-components=1 -f ${TEST_BOOTABLE_IMAGE_TAR} || exit 1
rm -f ${TEST_BOOTABLE_IMAGE_TAR}

rm -rf rpms/                            >>$OUTPUT_LOG 2>&1
mkdir -p rpms/                          >>$OUTPUT_LOG 2>&1
cp -Rv ../../spl/*.rpm ../../zfs/*.rpm rpms/  >>$OUTPUT_LOG 2>&1

sudo -E ./install-fedora-on-zfs \
    "$TEST_BOOTABLE_IMAGE_VDEV" \
    --pool-name="$TEST_BOOTABLE_IMAGE_POOL" \
    --root-password=password \
    --luks-password=password \
    --use-prebuilt-rpms="$PWD/rpms" \
    >>$OUTPUT_LOG 2>&1
RESULT=$?

exit $RESULT
