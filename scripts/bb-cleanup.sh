#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave"
   exit 1
fi

case "$BB_NAME" in
Amazon*)
    sudo yum -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

CentOS*)
    sudo yum -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

Debian*)
    sudo apt-get --yes purge \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-initramfs zfs-dracut zfs-test spl
    ;;

Fedora*)
    sudo dnf -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

RHEL*)
    sudo yum -y remove \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-debuginfo zfs-kmod-debuginfo zfs-dracut  zfs-test \
        spl spl-debuginfo spl-kmod-debuginfo
    ;;

SUSE*)
    sudo zypper --non-interactive remove \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-dracut  zfs-test spl
    ;;

Ubuntu*)
    sudo apt-get --yes purge \
        kmod-zfs-$(uname -r) kmod-zfs-devel-$(uname -r) \
        kmod-spl-$(uname -r) kmod-spl-devel-$(uname -r) \
        libnvpair1 libuutil1 libzfs2 libzpool2 libzfs2-devel \
        zfs zfs-initramfs zfs-dracut zfs-test spl
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
