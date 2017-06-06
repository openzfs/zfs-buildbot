#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

TEST_PREPARE_SKIP=${TEST_PREPARE_SKIP:-"No"}
if echo "$TEST_PREPARE_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

CONSOLE_LOG="$PWD/console.log"

SPL_DIR="../spl"
ZFS_DIR="../zfs"
TEST_DIR="$PWD"
TEST_FILE="${TEST_DIR}/TEST"

SUDO="sudo -E"

set -x

# Attempt to set oom_score_adj for buildslave to prevent
# it from being targeted by the oom-killer
if test -f "$BB_DIR/twistd.pid"; then
    pid=$(cat "$BB_DIR/twistd.pid")
    if test -f "/proc/${pid}/oom_score_adj"; then
        $SUDO echo -1000 > /proc/${pid}/oom_score_adj
    fi
fi

# Create a TEST file which includes parameters which may appear in a top
# level TEST file or the most recent git commit message.
rm -f $TEST_FILE
echo "#!/bin/sh" >>$TEST_FILE
echo >>$TEST_FILE
echo "# Custom buildbot test options." >>$TEST_FILE

if test -d "$SPL_DIR"; then
    cd "$SPL_DIR"

    if test -f TEST; then
        cat TEST >>$TEST_FILE
    fi

    git log -1 | sed "s/^ *//g" | grep ^TEST_ >>$TEST_FILE
    cd "$TEST_DIR"
fi

if test -d "$ZFS_DIR"; then
    cd "$ZFS_DIR"

    if test -f TEST; then
        cat TEST >>$TEST_FILE
    fi

    git log -1 | sed "s/^ *//g" | grep ^TEST_ >>$TEST_FILE
    cd "$TEST_DIR"
fi

. $TEST_FILE

# Start the Linux kernel watchdog so the system will panic in the case of a
# lockup.  This helps prevent one bad test run from stalling the builder.
TEST_PREPARE_WATCHDOG=${TEST_PREPARE_WATCHDOG:-"Yes"}
if echo "$TEST_PREPARE_WATCHDOG" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    case "$BB_NAME" in
    Amazon*)
        $SUDO /etc/init.d/watchdog start
        ;;

    CentOS*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            $SUDO /etc/init.d/watchdog start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            $SUDO systemctl start watchdog
        fi
        ;;

    Debian*)
        $SUDO systemctl start watchdog
        ;;

    Fedora*)
        $SUDO systemctl start watchdog
        ;;

    RHEL*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            $SUDO /etc/init.d/watchdog start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            $SUDO systemctl start watchdog
        fi
        ;;

    SUSE*)
        $SUDO systemctl start watchdog
        ;;

    Ubuntu*)
        $SUDO apt-get install watchdog
        $SUDO service watchdog start
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
        $SUDO /etc/init.d/rpcbind start
        $SUDO /etc/init.d/nfs start
        $SUDO /etc/init.d/smb start
        ;;

    CentOS*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            $SUDO /etc/init.d/rpcbind start
            $SUDO /etc/init.d/nfs start
            $SUDO /etc/init.d/smb start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            $SUDO systemctl start nfs-server
            $SUDO systemctl start smb
        fi
        ;;

    Debian*)
        $SUDO systemctl start nfs-kernel-server
        $SUDO systemctl start samba
        ;;

    Fedora*)
        $SUDO systemctl start nfs-server
        $SUDO systemctl start smb
        ;;

    RHEL*)
        if cat /etc/redhat-release | grep -Eq "6."; then
            $SUDO /etc/init.d/rpcbind start
            $SUDO /etc/init.d/nfs start
            $SUDO /etc/init.d/smb start
        elif cat /etc/redhat-release | grep -Eq "7."; then
            $SUDO systemctl start nfs-server
            $SUDO systemctl start smb
        fi
        ;;

    SUSE*)
        $SUDO systemctl start nfsserver
        $SUDO systemctl start smb
        ;;

    Ubuntu*)
        $SUDO service nfs-kernel-server start
        $SUDO service smbd start
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
                $SUDO parted --script /dev/$disk mklabel gpt
                $SUDO parted --script /dev/$disk mkpart logical 1MiB 64GiB
                $SUDO dd if=/dev/zero of=/dev/${disk}1 bs=1M &
            done

            wait
        fi
        ;;
esac

exit 0
