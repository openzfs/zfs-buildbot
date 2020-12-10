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
    ;;

CentOS*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E yum -y remove '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi
    ;;

Debian*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E apt-get --yes purge '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-initramfs zfs-dracut zfs-test
    fi
    ;;

Fedora*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E dnf -y remove '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut zfs-test
    fi
    ;;

Ubuntu*)
    if test "$BUILT_PACKAGE" = "zfs"; then
        sudo -E apt-get --yes purge '(zfs-dkms.*|kmod-zfs.*)' \
            libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
            zfs zfs-initramfs zfs-dracut zfs-test
    fi
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac

exit  0
