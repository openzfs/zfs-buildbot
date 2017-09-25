#!/bin/sh

if test -f /etc/buildslave; then
    . /etc/buildslave
fi

TEST_PREPARE_SKIP=${TEST_PREPARE_SKIP:-"No"}
if echo "$TEST_PREPARE_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

SPL_BUILD_DIR=$(readlink -f ../spl)
ZFS_BUILD_DIR=$(readlink -f ../zfs)
TEST_DIR="$PWD"
TEST_FILE="${TEST_DIR}/TEST"

# Attempt to set oom_score_adj for buildslave to prevent
# it from being targeted by the oom-killer
if test -f "$BB_DIR/twistd.pid"; then
    pid=$(cat "$BB_DIR/twistd.pid")
    if test -f "/proc/${pid}/oom_score_adj"; then
        sudo -E echo -1000 > /proc/${pid}/oom_score_adj
    fi
fi

# Create a TEST file which includes parameters which may appear in a top
# level TEST file or the most recent git commit message.
rm -f $TEST_FILE

if test -d "$SPL_BUILD_DIR"; then
    cd "$SPL_BUILD_DIR"

    if test -f TEST; then
        cat TEST >>$TEST_FILE
    fi

    git log -1 | sed "s/^ *//g" | grep ^TEST_ >>$TEST_FILE
    cd "$TEST_DIR"
fi

if test -d "$ZFS_BUILD_DIR"; then
    cd "$ZFS_BUILD_DIR"

    if test -f TEST; then
        cat TEST >>$TEST_FILE
    fi

    git log -1 | sed "s/^ *//g" | grep ^TEST_ >>$TEST_FILE
    cd "$TEST_DIR"
fi

cat << EOF >> $TEST_FILE

###
#
# Additional environment variables for use by bb-test-* scripts.
#
SPL_BUILD_DIR=$SPL_BUILD_DIR
ZFS_BUILD_DIR=$ZFS_BUILD_DIR
TEST_DIR=$TEST_DIR

TEST_METHOD=$TEST_METHOD

EOF

# Add environment variables for "packages" or "in-tree" testing.
TEST_METHOD=${TEST_METHOD:-"packages"}
if [ "$TEST_METHOD" = "packages" ]; then
    cat << EOF >> $TEST_FILE
SPLAT=${SPLAT:-"splat"}
ZPOOL=${ZPOOL:-"zpool"}
ZFS=${ZFS:-"zfs"}

ZFS_SH=${ZFS_SH:-"zfs.sh"}
ZFS_TESTS_SH=${ZFS_TESTS_SH:-"zfs-tests.sh"}
ZIMPORT_SH=${ZIMPORT_SH:-"zimport.sh"}
ZLOOP_SH=${ZLOOP_SH:-"zloop.sh"}
EOF
elif [ "$TEST_METHOD" = "in-tree" ]; then
    cat << EOF >> $TEST_FILE
SPLAT=${SPLAT:-"\$SPL_BUILD_DIR/bin/splat"}
ZPOOL=${ZPOOL:-"\$ZFS_BUILD_DIR/bin/zpool"}
ZFS=${ZFS:-"\$ZFS_BUILD_DIR/bin/zfs"}

ZFS_SH=${ZFS_SH:-"\$ZFS_BUILD_DIR/scripts/zfs.sh"}
ZFS_TESTS_SH=${ZFS_TESTS_SH:-"\$ZFS_BUILD_DIR/scripts/zfs-tests.sh"}
ZIMPORT_SH=${ZIMPORT_SH:-"\$ZFS_BUILD_DIR/scripts/zimport.sh"}
ZLOOP_SH=${ZLOOP_SH:-"\$ZFS_BUILD_DIR/scripts/zloop.sh"}
EOF
else
    cat << EOF >> $TEST_FILE
echo "Unknown TEST_METHOD: $TEST_METHOD"
exit 1
EOF
fi

. $TEST_FILE

# Start the Linux kernel watchdog so the system will panic in the case of a
# lockup.  This helps prevent one bad test run from stalling the builder.
TEST_PREPARE_WATCHDOG=${TEST_PREPARE_WATCHDOG:-"Yes"}
if echo "$TEST_PREPARE_WATCHDOG" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    case "$BB_NAME" in
    Amazon*)
        sudo -E /etc/init.d/watchdog start
        ;;

    CentOS*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            sudo -E /etc/init.d/watchdog start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            sudo -E systemctl start watchdog
        fi
        ;;

    Debian*)
        sudo -E systemctl start watchdog
        ;;

    Fedora*)
        sudo -E systemctl start watchdog
        ;;

    RHEL*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            sudo -E /etc/init.d/watchdog start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            sudo -E systemctl start watchdog
        fi
        ;;

    SUSE*)
        sudo -E systemctl start watchdog
        ;;

    Ubuntu*)
        sudo -E apt-get install watchdog
        sudo -E service watchdog start
        ;;

    *)
        echo "$BB_NAME unknown platform"
        ;;
     esac
fi

# Start both NFS and Samba servers, needed by the ZFS Test Suite to run
# zfs_share and zfs_unshare scripts.
TEST_PREPARE_SHARES=${TEST_PREPARE_SHARES:-"Yes"}
if echo "$TEST_PREPARE_SHARES" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    case "$BB_NAME" in
    Amazon*)
        sudo -E /etc/init.d/rpcbind start
        sudo -E /etc/init.d/nfs start
        sudo -E /etc/init.d/smb start
        ;;

    CentOS*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            sudo -E /etc/init.d/rpcbind start
            sudo -E /etc/init.d/nfs start
            sudo -E /etc/init.d/smb start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            sudo -E systemctl start nfs-server
            sudo -E systemctl start smb
        fi
        ;;

    Debian*)
        sudo -E systemctl start nfs-kernel-server
        sudo -E systemctl start samba
        ;;

    Fedora*)
        sudo -E systemctl start nfs-server
        sudo -E systemctl start smb
        ;;

    RHEL*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            sudo -E /etc/init.d/rpcbind start
            sudo -E /etc/init.d/nfs start
            sudo -E /etc/init.d/smb start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            sudo -E systemctl start nfs-server
            sudo -E systemctl start smb
        fi
        ;;

    SUSE*)
        sudo -E systemctl start nfsserver
        sudo -E systemctl start smb
        ;;

    Ubuntu*)
        sudo -E service nfs-kernel-server start
        sudo -E service smbd start
        ;;

    *)
        echo "$BB_NAME unknown platform"
        ;;
     esac
fi

# Other test environment prep by distro
case "$BB_NAME" in
    Amazon*)
        if test "$BB_MODE" = "PERF"; then
            for disk in $AVAILABLE_DISKS; do
                sudo -E parted --script /dev/$disk mklabel gpt
                sudo -E parted --script /dev/$disk mkpart logical 1MiB 64GiB
                sudo -E dd if=/dev/zero of=/dev/${disk}1 bs=1M &
            done

            wait
        fi
        ;;
esac

# Schedule a shutdown for all distros other than CentOS 6, Ubuntu 14.04,
# and Amazon based distros
case "$BB_NAME" in
    Amazon*|CentOS-6*|Ubuntu-14.04*)
        echo "Skipping scheduled shutdown"
        ;;
    *)
        echo "Scheduling shutdown"
        sudo -E shutdown +600
        ;;
esac

exit 0
