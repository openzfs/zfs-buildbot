#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildworker; then
    . /etc/buildworker
else
   echo "Missing configuration /etc/buildworker.  Assuming dependencies are"
   echo "already satisfied and this is a persistent buildworker."
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

# Temporary workaround for FreeBSD pkg db locking race
pkg_install () {
    local pkg_pid=$(pgrep pkg 2>/dev/null)
    if [ -n  "${pkg_pid}" ]; then
        pwait ${pkg_pid}
    fi
    sudo -E pkg install "${@}"
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
        libffi-devel libaio-devel libmount-devel pam-devel \
        python-devel python-setuptools python-cffi
    ;;

CentOS*)
    # Required repository packages
    if cat /etc/centos-release | grep -Eq "release 6."; then
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    elif cat /etc/centos-release | grep -Eq "release 7."; then
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    elif cat /etc/centos-release | grep -Eq "release 8."; then
        sudo -E yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    else
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sudo -E sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    # Required development tools.
    sudo -E yum -y --skip-broken install gcc make autoconf libtool gdb \
        kernel-rpm-macros kernel-abi-whitelists

    # Required utilities.
    sudo -E yum -y --skip-broken install --enablerepo=epel git rpm-build \
        wget curl bc fio acl sysstat mdadm lsscsi parted attr dbench watchdog \
        ksh nfs-utils samba rng-tools dkms pamtester

    # Required development libraries
    sudo -E yum -y --skip-broken install kernel-devel \
        zlib-devel libuuid-devel libblkid-devel libselinux-devel \
        xfsprogs-devel libattr-devel libacl-devel libudev-devel \
        openssl-devel libffi-devel pam-devel libaio-devel

    # Packages that are version dependent and not always available
    if cat /etc/centos-release | grep -Eq "release 7."; then
        sudo -E yum -y --skip-broken install --enablerepo=epel libasan \
            python-devel python-setuptools python-cffi \
            python36 python36-devel python36-setuptools python36-cffi
    elif cat /etc/centos-release | grep -Eq "release 8."; then
        sudo -E yum -y --skip-broken install libasan libtirpc-devel \
            python3-devel python3-setuptools python3-cffi
    fi

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
        libpam0g-dev pamtester python-dev python-setuptools python-cffi \
        python3 python3-dev python3-setuptools python3-cffi

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
        libaio-devel libmount-devel pam-devel pamtester python-devel python-setuptools \
        python-cffi python3 python3-devel python3-setuptools python3-cffi

    # Testing support libraries
    sudo -E dnf -y install libasan
    ;;

FreeBSD*)
    # Temporary workaround for pkg db locking race
    pkg_pid=$(pgrep pkg 2>/dev/null)
    if [ -n "${pkg_pid}" ]; then
	pwait ${pkg_pid}
    fi
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
    pkg_install -y --no-repo-update \
        autoconf \
        automake \
        autotools \
        bash \
        gmake \
        libtool

    # Testing support utilities
    pkg_install -y --no-repo-update \
        base64 \
        fio \
        ksh93 \
        python \
        python3 \
        samba410 \
        gdb \
        pamtester \
        lcov

    # Python support libraries
    pkg_install -y --no-repo-update \
        py37-cffi \
        py37-sysctl
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
        libpam0g-dev pamtester python-dev python-setuptools python-cffi \
        python3 python3-dev python3-setuptools python3-cffi

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
