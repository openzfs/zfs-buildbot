#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave.  Assuming dependencies are"
   echo "already satisfied and this is a persistent buildslave."
   exit 0
fi

set -x

case "$BB_NAME" in
Amazon*)
    # Required development tools.
    sudo yum -y install gcc autoconf libtool

    # Required utilties.
    sudo yum -y install git rpm-build wget curl lsscsi parted attr dbench \
        watchdog

    # Required development libraries
    sudo yum -y install kernel-devel-$(uname -r) \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel
    ;;

CentOS*)
    # Required development tools.
    sudo yum -y install gcc make autoconf libtool

    # Required utilties.
    sudo yum -y install git rpm-build wget curl lsscsi parted attr dbench \
        watchdog

    # Required development libraries
    sudo yum -y install kernel-devel zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel
    ;;

Debian*)
    # Required development tools.
    sudo apt-get --yes install build-essential autoconf libtool libtool-bin

    # Required utilties.
    sudo apt-get --yes install git alien fakeroot wget curl bc \
        lsscsi parted gdebi attr dbench watchdog

    # Required development libraries
    sudo apt-get --yes install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev
    ;;

Fedora*)
    # Required development tools.
    sudo dnf -y install gcc autoconf libtool

    # Required utilties.
    sudo dnf -y install git rpm-build wget curl lsscsi parted attr dbench \
        watchdog

    # Required development libraries
    sudo dnf -y install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel
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
    sudo yum -y install gcc autoconf libtool

    # Required utilties.
    sudo yum -y install git rpm-build wget curl lsscsi parted attr dbench \
        watchdog

    # Required development libraries
    sudo yum -y $EXTRA_REPO install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel
    ;;

SUSE*)
    # Required development tools.
    sudo zypper --non-interactive install gcc autoconf libtool

    # Required utilties.
    sudo zypper --non-interactive install git rpm-build wget curl \
        lsscsi parted attr

    # Required development libraries
    sudo zypper --non-interactive install kernel-devel zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel xfsprogs-devel \
        libattr-devel libacl-devel
    ;;

Ubuntu*)
    # Required development tools.
    sudo apt-get --yes install build-essential autoconf libtool

    # Required utilties.
    sudo apt-get --yes install git alien fakeroot wget curl \
        lsscsi parted gdebi attr dbench watchdog

    # Required development libraries
    sudo apt-get --yes install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
