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

# Lustre servers are only officially supported on CentOS 7.
case "$BB_NAME" in
CentOS*)
    if cat /etc/centos-release | grep -Eq "7."; then
        DEFAULT_TEST_LUSTRE_SKIP="No"
    else
        DEFAULT_TEST_LUSTRE_SKIP="Yes"
    fi
    ;;
*)
    DEFAULT_TEST_LUSTRE_SKIP="Yes"
    ;;
esac

TEST_LUSTRE_SKIP=${TEST_LUSTRE_SKIP:-$DEFAULT_TEST_LUSTRE_SKIP}
if echo "$TEST_LUSTRE_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

CONSOLE_LOG="$PWD/console.log"
LLMOUNT_SH="/usr/lib64/lustre/tests/llmount.sh"
LLMOUNTCLEANUP_SH="/usr/lib64/lustre/tests/llmountcleanup.sh"

cleanup()
{
    sudo -E $LLMOUNTCLEANUP_SH
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
    rm -f $MDSDEV1 $OSTDEV1 $OSTDEV2
}
trap cleanup EXIT

set -x

#
# By default only minimal testing is performed using llmount.sh.  The kernel
# modules are loaded and a Lustre system is created and mounted.
#
# A full list of available test scripts can be found at:
# - http://wiki.lustre.org/Test_Descriptions
#
TEST_LUSTRE_SCRIPT=${TEST_LUSTRE_SCRIPT:-$LLMOUNT_SH}
TEST_LUSTRE_DEVICE_SIZE=${TEST_LUSTRE_DEVICE_SIZE=131072}	# In kiB
TEST_LUSTRE_DEVICE_DIR="/var/tmp"

set +x

sudo -E dmesg -c >/dev/null

export FSTYPE="zfs"
export MDSSIZE=$TEST_LUSTRE_DEVICE_SIZE
export OSTSIZE=$TEST_LUSTRE_DEVICE_SIZE
export MDSDEV1="$TEST_LUSTRE_DEVICE_DIR/lustre-mdt1"
export OSTDEV1="$TEST_LUSTRE_DEVICE_DIR/lustre-ost1"
export OSTDEV2="$TEST_LUSTRE_DEVICE_DIR/lustre-ost2"

truncate -s ${MDSSIZE}k ${MDSDEV1}
truncate -s ${OSTSIZE}k ${OSTDEV1} ${OSTDEV2}

sudo -E $TEST_LUSTRE_SCRIPT
RESULT=$?

exit $RESULT
