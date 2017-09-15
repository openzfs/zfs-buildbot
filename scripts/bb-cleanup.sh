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
        sudo -E yum -y remove \
            kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E yum -y remove \
            kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
            spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

CentOS*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E yum -y remove \
            kmod-zfs kmod-zfs-devel \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E yum -y remove \
            kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
            spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

Debian*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E apt-get --yes purge \
            kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-initramfs zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E apt-get --yes purge \
            kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) spl
    fi
    ;;

Fedora*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E dnf -y remove \
            kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E dnf -y remove \
            kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
            spl spl-debuginfo spl-kmod-debuginfo
    fi
    ;;

RHEL*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E yum -y remove \
            kmod-zfs kmod-zfs-devel \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E yum -y remove \
            kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
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
        sudo -E apt-get --yes purge \
            kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-initramfs zfs-dracut zfs-test
    fi

    if test "$BUILT_PACKAGE" = "spl"; then
        sudo -E apt-get --yes purge \
            kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) spl
    fi
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac

exit  0
