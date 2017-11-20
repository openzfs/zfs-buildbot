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
    sudo -E yum -y install gcc autoconf libtool gdb lcov

    # Required utilities.
    sudo -E yum -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms
    sudo -E yum -y install --enablerepo=epel cppcheck pax-utils

    # Required development libraries
    sudo -E yum -y install kernel-devel-$(uname -r) \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel elfutils-libelf-devel

    sudo -E pip --quiet install flake8
    ;;

CentOS*)
    # Required development tools.
    sudo -E yum -y install gcc make autoconf libtool gdb lcov

    # Required utilities.
    sudo -E yum -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms

    # Required development libraries
    sudo -E yum -y install kernel-devel \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel

    # Packages that are version dependent and not always available
    if cat /etc/centos-release | grep -Fq 7.; then
        sudo -E yum -y install libasan
    fi
    ;;

Debian*)
    # Required development tools.
    sudo -E apt-get --yes install build-essential autoconf libtool \
        libtool-bin gdb lcov

    # Required utilities.
    sudo -E apt-get --yes install git alien fakeroot wget curl bc fio acl \
        sysstat lsscsi parted gdebi attr dbench watchdog ksh nfs-kernel-server \
        samba rng-tools dkms

    # Required development libraries
    sudo -E apt-get --yes install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev libudev-dev libdevmapper-dev \
        libssl-dev

    # Testing support libraries
    sudo -E apt-get --yes install libasan
    ;;

Fedora*)
    # Required development tools.
    sudo -E dnf -y install gcc autoconf libtool gdb lcov

    # Required utilities.
    sudo -E dnf -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms

    # Required development libraries
    sudo -E dnf -y install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel

    sudo -E yum -y install libasan
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
    sudo -E yum -y install gcc autoconf libtool gdb lcov

    # Required utilities.
    sudo -E yum -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms

    # Required development libraries
    sudo -E yum -y $EXTRA_REPO install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel

    # Packages that are version dependent and not always available
    if cat /etc/redhat-release | grep -Fq 7.; then
        sudo -E yum -y install libasan
    fi

    ;;

SUSE*)
    # Required development tools.
    sudo -E zypper --non-interactive install gcc autoconf libtool gdb lcov

    # Required utilities.
    sudo -E zypper --non-interactive install git rpm-build wget curl bc \
        fio acl sysstat mdadm lsscsi parted attr ksh nfs-kernel-server \
        samba rng-tools dkms

    # Required development libraries
    sudo -E zypper --non-interactive install kernel-devel zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel xfsprogs-devel \
        libattr-devel libacl-devel libudev-devel device-mapper-devel \
        openssl-devel
    ;;

Ubuntu*)
    # Required development tools.
    sudo -E apt-get --yes install build-essential autoconf libtool gdb lcov

    # Required utilities.
    sudo -E apt-get --yes install git alien fakeroot wget curl bc fio acl \
        sysstat mdadm lsscsi parted gdebi attr dbench watchdog ksh \
        nfs-kernel-server samba rng-tools xz-utils dkms

    # Required development libraries
    sudo -E apt-get --yes install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev libudev-dev libdevmapper-dev \
        libssl-dev

    sudo -E apt-get --yes install libasan1

    if test "$BB_MODE" = "STYLE"; then
        sudo -E apt-get --yes install pax-utils shellcheck cppcheck mandoc
        sudo -E pip --quiet install flake8
    fi
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
