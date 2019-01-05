#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave"
   exit 1
fi

BUILT_PACKAGE=${BUILT_PACKAGE:-""}

set -x

case "$BB_NAME" in
Amazon*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E yum -y remove '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E yum -y remove '(spl-dkms.*|kmod-spl.*)' \
	    spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

CentOS*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E yum -y remove '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E yum -y remove '(spl-dkms.*|kmod-spl.*)' \
            spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

Debian*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E apt-get --yes purge '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-initramfs zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E apt-get --yes purge '(spl-dkms.*|kmod-spl.*)' spl
    fi
    ;;

Fedora*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E dnf -y remove '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E dnf -y remove '(spl-dkms.*|kmod-spl.*)' \
            spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

FreeBSD*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E rm -f /boot/modules/zfs.ko /usr/local/sbin/zpool \
		/usr/local/sbin/zfs /usr/local/sbin/zdb /usr/local/sbin/zhack \
		/usr/local/sbin/ztest /usr/local/sbin/zinject /usr/local/sbin/zstreamdump \
		/usr/local/sbin/fsck.zfs
    fi
    ;;
RHEL*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E yum -y remove '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E yum -y remove '(spl-dkms.*|kmod-spl.*)' \
            spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

SUSE*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E zypper --non-interactive remove \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E zypper --non-interactive remove spl
    fi
    ;;

Ubuntu*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E apt-get --yes purge '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-initramfs zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E apt-get --yes purge '(spl-dkms.*|kmod-spl.*)' spl
    fi
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac

exit  0
