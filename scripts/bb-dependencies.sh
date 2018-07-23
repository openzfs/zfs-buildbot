#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave.  Assuming dependencies are"
   echo "already satisfied and this is a persistent buildslave."
   exit 0
fi

# a function to wait for an apt-get upgrade to finish
function apt-get-install
{
    while true; do
        sudo -E apt-get --yes install "$@"

        # error code 11 indicates that a lock file couldn't be obtained
        # keep retrying until we don't see an error code of 11
        [[ $? -ne 11 ]] && break

        sleep 0.5
    done 
}

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
    fi

    # Required development libraries
    sudo -E yum -y install kernel-devel-$(uname -r) \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel elfutils-libelf-devel libffi-devel \
        libaio-devel python-devel python-setuptools python-cffi

    sudo -E pip --quiet install flake8
    ;;

CentOS*)
    # Required repository packages
    if cat /etc/centos-release | grep -Eq "6."; then
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    elif cat /etc/centos-release | grep -Eq "7."; then
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    else
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sudo -E sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

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
        libaio-devel python-setuptools python-cffi libyaml-devel

    # Packages that are version dependent and not always available
    if cat /etc/centos-release | grep -Fq 7.; then
        sudo -E yum -y install libasan
    fi

    # Testing support libraries and tools
    sudo -E yum -y install --enablerepo=epel python34 fio
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
        libssl-dev libaio-dev python-dev libffi-dev python-setuptools \
        python-cffi libelf-dev

    # Testing support libraries
    sudo -E apt-get --yes install libasan3 python3
    ;;

Fedora*)
    # Required development tools.
    sudo -E dnf -y install gcc make autoconf libtool gdb lcov

    # Required utilities.
    sudo -E dnf -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms

    # Required development libraries
    sudo -E dnf -y install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel libtirpc-devel libffi-devel \
        libaio-devel python-devel python-setuptools python-cffi

    sudo -E dnf -y install libasan python3
    ;;

RHEL*)
    # Required repository packages
    if cat /etc/redhat-release | grep -Eq "6."; then
        EXTRA_REPO="--enablerepo=rhui-REGION-rhel-server-releases-optional"
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    elif cat /etc/redhat-release | grep -Eq "7."; then
        EXTRA_REPO="--enablerepo=rhui-REGION-rhel-server-optional"
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    else
        EXTRA_REPO=""
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sudo -E sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    # Required development tools.
    sudo -E yum -y install gcc make autoconf libtool gdb lcov

    # Required utilities.
    sudo -E yum -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms

    # Required development libraries
    sudo -E yum -y $EXTRA_REPO install kernel-devel-$(uname -r) zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel libffi-devel libaio-devel \
        python-devel python-setuptools python-cffi

    # Packages that are version dependent and not always available
    if cat /etc/redhat-release | grep -Fq 7.; then
        sudo -E yum -y install libasan
    fi

    # Testing support libraries and tools
    sudo -E yum -y install --enablerepo=epel python34 fio
    ;;

SUSE*)
    # Required development tools.
    sudo -E zypper --non-interactive install gcc make autoconf libtool gdb lcov

    # Required utilities.
    sudo -E zypper --non-interactive install git rpm-build wget curl bc \
        fio acl sysstat mdadm lsscsi parted attr ksh nfs-kernel-server \
        samba rng-tools dkms

    # Required development libraries
    sudo -E zypper --non-interactive install kernel-devel zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel xfsprogs-devel \
        libattr-devel libacl-devel libudev-devel device-mapper-devel \
        openssl-devel libffi-devel libaio-devel python-devel \
        python-setuptools python-cffi
    ;;

Ubuntu*)
    # Required development tools.
    apt-get-install build-essential autoconf libtool gdb lcov

    # Required utilities.
    apt-get-install git alien fakeroot wget curl bc fio acl \
        sysstat mdadm lsscsi parted gdebi attr dbench watchdog ksh \
        nfs-kernel-server samba rng-tools xz-utils dkms

    # Required development libraries
    apt-get-install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev libudev-dev libdevmapper-dev \
        libssl-dev libffi-dev libaio-dev python-dev python-setuptools \
        python-cffi libelf-dev

    if test "$BB_MODE" = "STYLE"; then
        apt-get-install pax-utils shellcheck cppcheck mandoc
        sudo -E pip --quiet install flake8
    fi

    # Testing support libraries
    apt-get-install python3
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
