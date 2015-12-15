#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave"
   exit 1
fi

SUDO="sudo -E"

set -x

case "$BB_NAME" in
Amazon*)
    $SUDO yum -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

CentOS*)
    $SUDO yum -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

Debian*)
    $SUDO apt-get --yes purge \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-initramfs zfs-dracut zfs-test spl
    ;;

Fedora*)
    $SUDO dnf -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

RHEL*)
    $SUDO yum -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

SUSE*)
    $SUDO zypper --non-interactive remove \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-dracut  zfs-test spl
    ;;

Ubuntu*)
    $SUDO apt-get --yes purge \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-initramfs zfs-dracut zfs-test spl
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
