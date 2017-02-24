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
    sudo -E yum -y install gcc autoconf libtool gdb lcov bison flex

    # Required utilities.
    sudo -E yum -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms php php-gd php-dom php-curl php-zip php-posix php-cli \
        php-xml php-sqlite3

    if cat /etc/os-release | grep -Eq "Amazon Linux 2"; then
        sudo -E amazon-linux-extras install python3
    else
        sudo -E yum -y install --enablerepo=epel cppcheck pax-utils
    fi

    $SUDO yum -y install --enablerepo=epel cppcheck pax-utils

    # Required development libraries
    sudo -E yum -y install kernel-devel-$(uname -r) \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel elfutils-libelf-devel libffi-devel \
        python-devel python-setuptools python-cffi

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
        device-mapper-devel openssl-devel libffi-devel python-devel \
        python-setuptools python-cffi

    # Packages that are version dependent and not always available
    if cat /etc/centos-release | grep -Fq 7.; then
        sudo -E yum -y install libasan
    fi

    # Testing support libraries
    sudo -E yum -y install --enablerepo=epel python34
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
        libssl-dev python-dev libffi-dev python-setuptools python-cffi

    # Testing support libraries
    sudo -E apt-get --yes install libasan1 python3
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
        device-mapper-devel openssl-devel libtirpc-devel libffi-devel \
        python-devel python-setuptools python-cffi

    sudo -E dnf -y install libasan python3
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
        device-mapper-devel openssl-devel libffi-devel python-devel \
        python-setuptools python-cffi

    # Packages that are version dependent and not always available
    if cat /etc/redhat-release | grep -Fq 7.; then
        sudo -E yum -y install libasan
    fi

    # Testing support libraries
    sudo -E yum -y install --enablerepo=epel python34
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
        openssl-devel libffi-devel python-devel python-setuptools python-cffi
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
        libssl-dev libffi-dev python-dev python-setuptools python-cffi

    if test "$BB_MODE" = "STYLE"; then
        sudo -E apt-get --yes install pax-utils shellcheck cppcheck mandoc
        sudo -E pip --quiet install flake8
    fi

    # Testing support libraries
    sudo -E apt-get --yes install python3
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
