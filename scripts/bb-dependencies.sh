#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
   echo "Missing configuration /etc/buildslave.  Assuming dependencies are"
   echo "already satisfied and this is a persistent buildslave."
   exit 0
fi

# a function to wait for an apt-get upgrade to finish
apt_get_install () {
    while true; do
        sudo -E apt-get --yes install "$@"

        # error code 11 indicates that a lock file couldn't be obtained
        # keep retrying until we don't see an error code of 11
        [ $? -ne 11 ] && break

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
        sudo -E yum -y install \
            python3 python3-devel python3-setuptools python3-cffi
    fi

    # Required development libraries
    sudo -E yum -y install kernel-devel-$(uname -r) \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel elfutils-libelf-devel \
        libffi-devel libaio-devel libmount-devel \
        python-devel python-setuptools python-cffi ncurses-devel
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
        libaio-devel python-setuptools python-cffi libyaml-devel ncurses-devel

    # Packages that are version dependent and not always available
    if cat /etc/centos-release | grep -Eq "7."; then
        sudo -E yum -y install libasan libmount-devel
    fi

    # Testing support libraries and tools
    sudo -E yum -y install --enablerepo=epel fio \
        python36 python36-devel python36-setuptools python36-cffi
    ;;

Debian*)
    export DEBIAN_FRONTEND=noninteractive

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
        libssl-dev libaio-dev libffi-dev libelf-dev libmount-dev \
        python-dev python-setuptools python-cffi \
        python3 python3-dev python3-setuptools python3-cffi libncurses-dev

    # Testing support libraries
    sudo -E apt-get --yes install libasan4
    ;;

Fedora*)
    # Always test with the latest packages on Fedora.
    sudo -E dnf -y upgrade

    # Required development tools.
    sudo -E dnf -y install gcc make autoconf libtool gdb lcov

    # Required utilities.
    sudo -E dnf -y install git rpm-build wget curl bc fio acl sysstat \
        mdadm lsscsi parted attr dbench watchdog ksh nfs-utils samba \
        rng-tools dkms

    # Required development libraries
    sudo -E dnf -y install kernel-devel zlib-devel \
        libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        device-mapper-devel openssl-devel libtirpc-devel libffi-devel \
        libaio-devel libmount-devel python-devel python-setuptools \
        python-cffi python3 python3-devel python3-setuptools python3-cffi \
        ncurses-devel

    # Testing support libraries
    sudo -E dnf -y install libasan
    ;;

FreeBSD*)
    # Always test with the latest packages on FreeBSD.
    sudo -E pkg upgrade -y --no-repo-update

    # Kernel source
    (
        ABI=$(uname -p)
        VERSION=$(freebsd-version -r)
        cd /tmp
        fetch https://download.freebsd.org/ftp/snapshots/${ABI}/${VERSION}/src.txz
        sudo tar xpf src.txz -C /
        rm src.txz
    )

    # Required development tools
    sudo -E pkg install -y --no-repo-update \
        autoconf \
        automake \
        autotools \
        bash \
        gmake \
        libtool

    # Testing support utilities
    sudo -E pkg install -y --no-repo-update \
        base64 \
        fio \
        hs-ShellCheck \
        ksh93 \
        py36-flake8 \
        samba410

    sudo ln -sf /usr/local/bin/python3 /usr/local/bin/python
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
        python-devel python-setuptools python-cffi ncurses-devel

    # Packages that are version dependent and not always available
    if cat /etc/redhat-release | grep -Eq "7."; then
        sudo -E yum -y install libasan libmount-devel
    fi

    # Testing support libraries and tools
    sudo -E yum -y install --enablerepo=epel fio \
        python36 python36-devel python36-setuptools python36-cffi
    ;;

Ubuntu*)
    # Required development tools.
    apt_get_install build-essential autoconf libtool gdb lcov

    # Required utilities.
    apt_get_install git alien fakeroot wget curl bc fio acl \
        sysstat mdadm lsscsi parted gdebi attr dbench watchdog ksh \
        nfs-kernel-server samba rng-tools xz-utils dkms

    # Required development libraries
    apt_get_install linux-headers-$(uname -r) \
        zlib1g-dev uuid-dev libblkid-dev libselinux-dev \
        xfslibs-dev libattr1-dev libacl1-dev libudev-dev libdevmapper-dev \
        libssl-dev libffi-dev libaio-dev libelf-dev libmount-dev \
        python-dev python-setuptools python-cffi \
        python3 python3-dev python3-setuptools python3-cffi libncurses-dev

    if test "$BB_MODE" = "STYLE"; then
        apt_get_install pax-utils shellcheck cppcheck mandoc
        sudo -E pip --quiet install flake8
    fi

    # Testing support libraries
    apt_get_install python3
    ;;

*)
    echo "$BB_NAME unknown platform"
    ;;
esac
