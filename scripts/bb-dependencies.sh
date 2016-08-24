#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave.  Assuming dependencies are"
   echo "already satisfied and this is a persistent buildslave."
   exit 0
fi

SUDO="sudo -E"

set -x

case "$BB_NAME" in
Amazon*)
    # Required development tools.
    $SUDO yum -y install gcc autoconf libtool gdb

    # Required utilities.
    $SUDO yum -y install git rpm-build wget curl bc \
        lsscsi parted attr dbench watchdog ksh

    # Required development libraries
    $SUDO yum -y install kernel-devel-$(uname -r) \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel
    ;;

CentOS*)
    # Required development tools.
    $SUDO yum -y install gcc make autoconf libtool gdb

    # Required utilities.
    $SUDO yum -y install git rpm-build wget curl bc \
        lsscsi parted attr dbench watchdog ksh

    # Required development libraries
    $SUDO yum -y install kernel-devel \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel
    ;;

Debian*)
    # Required development tools.
    $SUDO apt-get --yes install build-essential autoconf libtool \
        libtool-bin gdb

    # Required utilities.
    $SUDO apt-get --yes install git alien fakeroot wget curl bc \
        lsscsi parted gdebi attr dbench watchdog ksh

    # Required development libraries
    $SUDO apt-get --yes install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev libudev-dev
    ;;

Fedora*)
    # Required development tools.
    $SUDO dnf groupinstall "C Development Tools and Libraries"

    # Required utilities.
    $SUDO dnf -y install git rpm-build wget curl bc \
        lsscsi parted attr dbench watchdog ksh

    # Required development libraries
    $SUDO dnf -y install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel

    # Required testing utilities (for bb-test-bootable-image.sh)
    $SUDO dnf -y install qemu-system-x86 rsync cryptsetup
    ;;

RHEL*)
    if cat /etc/redhat-release | grep -Eq "6."; then
        EXTRA_REPO="--enablerepo=rhui-REGION-rhel-server-releases-optional"
    elif cat /etc/redhat-release | grep -Eq "7."; then
        EXTRA_REPO="--enablerepo=rhui-REGION-rhel-server-optional"
    else
        EXTRA_REPO=""
    fi

    # Required development tools.
    $SUDO yum -y install gcc autoconf libtool gdb

    # Required utilities.
    $SUDO yum -y install git rpm-build wget curl bc \
        lsscsi parted attr dbench watchdog ksh

    # Required development libraries
    $SUDO yum -y $EXTRA_REPO install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel
    ;;

SUSE*)
    # Required development tools.
    $SUDO zypper --non-interactive install gcc autoconf libtool gdb

    # Required utilities.
    $SUDO zypper --non-interactive install git rpm-build wget curl bc \
        lsscsi parted attr ksh

    # Required development libraries
    $SUDO zypper --non-interactive install kernel-devel zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel xfsprogs-devel \
        libattr-devel libacl-devel libudev-devel
    ;;

Ubuntu*)
    # Required development tools.
    $SUDO apt-get --yes install build-essential autoconf libtool gdb

    # Required utilities.
    $SUDO apt-get --yes install git alien fakeroot wget curl bc \
        lsscsi parted gdebi attr dbench watchdog ksh

    # Required development libraries
    $SUDO apt-get --yes install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev libudev-dev
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
