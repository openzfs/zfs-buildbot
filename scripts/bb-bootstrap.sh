#!/bin/sh

# Copyright 2011 Henrik Ingo <henrik.ingo@openlife.cc>
# License = GPLv2 or later
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; version 2 or later of the License.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Check for a local cached configuration.
if test -f /etc/buildworker; then
    . /etc/buildworker
fi

# These parameters should be set and exported in the user-data script that
# calls us.  If they are not there, we set some defaults but they almost
# certainly will not work.
if test ! "$BB_MASTER"; then
    BB_MASTER="build.zfsonlinux.org:9989"
fi
if test ! "$BB_NAME"; then
    BB_NAME=$(hostname)
fi
if test ! "$BB_PASSWORD"; then
    BB_PASSWORD="password"
fi
if test ! "$BB_MODE"; then
    BB_MODE="BUILD"
fi
if test ! "$BB_ADMIN"; then
    BB_ADMIN="Automated latent BuildBot worker <buildbot@zfsonlinux.org>"
fi
if test ! "$BB_DIR"; then
    BB_DIR="/var/lib/buildbot/workers/zfs"
fi
if test ! "$BB_USE_PIP"; then
    BB_USE_PIP=0
fi
if test ! "$BB_KERNEL_TYPE"; then
    BB_KERNEL_TYPE="STD"
fi

if test ! -f /etc/buildworker; then
    echo "BB_MASTER=\"$BB_MASTER\""      > /etc/buildworker
    echo "BB_NAME=\"$BB_NAME\""         >> /etc/buildworker
    echo "BB_PASSWORD=\"$BB_PASSWORD\"" >> /etc/buildworker
    echo "BB_MODE=\"$BB_MODE\""         >> /etc/buildworker
    echo "BB_ADMIN=\"$BB_ADMIN\""       >> /etc/buildworker
    echo "BB_DIR=\"$BB_DIR\""           >> /etc/buildworker
    echo "BB_SHUTDOWN=\"Yes\""          >> /etc/buildworker
fi


BB_PARAMS="${BB_DIR} ${BB_MASTER} ${BB_NAME} ${BB_PASSWORD}"
echo "$0: BB_PARAMS is now $BB_PARAMS"

# Magic IP address from where to obtain EC2 metadata
METAIP="169.254.169.254"
METAROOT="http://${METAIP}/latest"
# Don't print 404 error documents. Don't print progress information.
CURL="curl --fail --silent"


testbin () {
    BIN_PATH="$(which ${1})"
    if [ ! -x "${BIN_PATH}" -o -z "${BIN_PATH}" ]; then
            return 1
    fi
    return 0
}

set_boot_kernel () {
	if [ -f /boot/grub2/grub.cfg ]; then
		entry=$(awk -F "'" '
			/^menuentry.*x86_64.debug/ {
				print $2; exit
			};' /boot/grub2/grub.cfg)
		sed --in-place "s/^saved_entry=.*/saved_entry=${entry}/" /boot/grub2/grubenv
	fi

	if [ -f /boot/grub/grub.conf ]; then
		entry=$(awk '
			BEGIN {entry=0};
			/^title.*debug/ {print entry; exit};
			/^title/ {entry++}
			' /boot/grub/grub.conf)
		sed --in-place "s/^default=.*/default=${entry}/" /boot/grub/grub.conf
	fi
}

# Standardize unused instance storage under /mnt.  Either the first unused
# NVMe device found, or any ephemeral storage specified in the block mapping.
# Passing /dev/null for inst_dev will result in the default AMI behavior.
standardize_storage () {
    inst_dev="$1"
    nvme_dev="$(ls -1 /dev/disk/by-id/*NVMe_Instance_Storage* | head -1)"

    if test -b $nvme_dev; then
        echo "$nvme_dev /mnt ext4 defaults,noatime" >>/etc/fstab
        mkfs.ext4 $nvme_dev
    elif test -b $inst_dev; then
        sed -i.bak '/ephemeral/d' /etc/fstab
        echo "$inst_dev /mnt ext4 defaults,noatime" >>/etc/fstab
        if ! blkid $inst_dev >/dev/null 2>&1; then
            mkfs.ext4 $inst_dev
        fi
    fi
}

# Temporary workaround for FreeBSD pkg db locking race
pkg_install () {
    local pkg_pid=$(pgrep pkg 2>/dev/null)
    if [ -n  "${pkg_pid}" ]; then
        pwait ${pkg_pid}
    fi
    pkg install "${@}"
}

set -x

case "$BB_NAME" in
Amazon*)
    # Required repository packages
    if cat /etc/os-release | grep -Eq "Amazon Linux 2"; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    else
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    yum -y install deltarpm gcc python-pip python-devel
    easy_install --quiet buildbot-slave

    # Install the latest kernel to reboot on to.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        yum -y update kernel
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
        echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
        sed -i.bak '/secure_path/a\Defaults    exempt_group += buildbot' /etc/sudoers
        sed -i.bak '/env_keep = /a\Defaults    env_keep += "PERF_FS_OPTS PERF_RUNTIME PERF_REGRESSION_WEEKLY"' /etc/sudoers
    fi

    # Enable partitions for loopback devices, they are disabled by default.
    echo "options loop max_part=15" >/etc/modprobe.d/loop.conf

    if test "$BB_MODE" != "PERF"; then
        standardize_storage /dev/xvdb
    fi
    ;;

CentOS*)
    yum -y update
    yum -y upgrade

    # Required repository packages
    if cat /etc/centos-release | grep -Eq "release 6."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    elif cat /etc/centos-release | grep -Eq "release 7."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    elif cat /etc/centos-release | grep -Eq "release 8."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        yum -y install gcc
        yum -y module install python27
        alternatives --set python /usr/bin/python2
    else
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    if cat /etc/redhat-release | grep -Eq "release 6."; then
        # The buildbot-slave package isn't available from a common repo.
        BUILDWORKER_URL="http://build.zfsonlinux.org"
        BUILDWORKER_RPM="buildbot-slave-0.8.8-2.el6.noarch.rpm"
        yum -y install $BUILDWORKER_URL/$BUILDWORKER_RPM
    elif cat /etc/redhat-release | grep -Eq "release 7."; then
        yum --enablerepo=epel -y install gcc python-pip python-devel
        pip --quiet install buildbot-slave
    elif cat /etc/centos-release | grep -Eq "release 8."; then
        if which pip2 > /dev/null ; then
            pip2 install buildbot-slave
        elif which pip > /dev/null ; then
            pip install buildbot-slave
        else
            pip3 install buildbot-slave
        fi
    else
        echo "Unknown CentOS release:"
        cat /etc/centos-release
    fi

    # Install the latest kernel to reboot on to.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        yum -y update kernel

        # User namespaces must be enabled at boot time for CentOS 7
        if cat /etc/redhat-release | grep -Eq "release 7."; then
            grubby --args="user_namespace.enable=1" \
                --update-kernel="$(grubby --default-kernel)"
            grubby --args="namespace.unpriv_enable=1" \
                --update-kernel="$(grubby --default-kernel)"
            echo "user.max_user_namespaces=3883" > /etc/sysctl.d/99-userns.conf
        fi
    fi

    # Use the debug kernel instead if indicated
    if test "$BB_KERNEL_TYPE" = "DEBUG"; then
        yum -y install kernel-debug
        set_boot_kernel
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/a\Defaults exempt_group+=buildbot' /etc/sudoers

    # Standardize ephemeral storage so it's available under /mnt.
    standardize_storage /dev/null
    ;;

Debian*)
    apt-get --yes update

    # As of Debian 10 buildbot v1.0 is provided from the repository.  This
    # version is incompatible v0.8 on master, so use the older pip version.
    VERSION=$(cut -f1 -d'.' /etc/debian_version)
    if test $VERSION -ge 10; then
        BB_USE_PIP=1
    fi

    # Relying on the pip version of the buildworker is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        apt-get --yes install gcc curl python-pip python-dev
        pip --quiet install buildbot-slave
    else
        apt-get --yes install curl buildbot-slave
    fi

    # Install the latest kernel to reboot on to.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        apt-get --yes install --only-upgrade linux-image-amd64
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo "Defaults umask = 0000" >> /etc/sudoers
    echo "Defaults umask_override" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/a\Defaults exempt_group+=buildbot' /etc/sudoers

    # Standardize ephemeral storage so it's available under /mnt.
    standardize_storage /dev/null

    sed -i.bak 's/nobootwait/nofail/' /etc/fstab

    # Allow normal users to read dmesg, restricted by default.
    mkdir -p /etc/sysctl.d/
    echo "kernel.dmesg_restrict = 0" >> /etc/sysctl.d/10-local.conf
    sysctl kernel.dmesg_restrict=0
    ;;

Fedora*)
    # As of Fedora 28 buildbot v1.0 is provided from the repository.  This
    # version is incompatible v0.8 on master, so use the older pip version.
    VERSION=$(cut -f3 -d' ' /etc/fedora-release)
    if test $VERSION -ge 28; then
        BB_USE_PIP=1
    fi

    # Relying on the pip version of the buildworker is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then

        # Python 2 has been removed from Fedora 32.  The required pip2
        # pacakages are still provided by the UnitedRPMs repository.
        if test $VERSION -ge 32; then
            rpm --import https://raw.githubusercontent.com/UnitedRPMs/unitedrpms/master/URPMS-GPG-PUBLICKEY-Fedora
            dnf -y install https://github.com/UnitedRPMs/unitedrpms/releases/download/17/unitedrpms-$(rpm -E %fedora)-17.fc$(rpm -E %fedora).noarch.rpm
        fi

        dnf -y install gcc python2 python2-devel python2-pip
        if which pip2 > /dev/null ; then
            pip2 install buildbot-slave
        elif which pip > /dev/null ; then
            pip install buildbot-slave
        else
            pip3 install buildbot-slave
        fi
    else
        dnf -y install buildbot-slave
    fi

    # Install the latest kernel to reboot on to.  When testing on Rawhide
    # always install the nodebug kernel rather than the default kernel.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        if grep -q "Rawhide" /etc/fedora-release; then
            dnf config-manager --add-repo=http://dl.fedoraproject.org/pub/alt/rawhide-kernel-nodebug/fedora-rawhide-kernel-nodebug.repo
            dnf update
            dnf -y --enablerepo=fedora-rawhide-kernel-nodebug \
                update kernel-core kernel-devel
        else
            dnf -y update kernel-core kernel-devel
        fi

        # Ensure crontab is installed to start the build worker post reboot.
        dnf -y install cronie
    fi

    # Use the debug kernel instead if indicated
    if test "$BB_KERNEL_TYPE" = "DEBUG"; then
        dnf -y install kernel-debug kernel-debug-devel
    else
        dnf -y remove kernel-debug kernel-debug-devel
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/a\Defaults exempt_group+=buildbot' /etc/sudoers

    # Standardize ephemeral storage so it's available under /mnt.
    standardize_storage /dev/null

    # Set python2 as the default so buildbot works
    #
    alternatives --install /usr/bin/python python /usr/bin/python3.7 2
    alternatives --install /usr/bin/python python /usr/bin/python2.7 1
    alternatives --set python /usr/bin/python2.7
    python --version
    ;;

FreeBSD*)
    cat >>/usr/local/etc/pkg.conf <<EOF

# OpenZFS buildbot bootstrap needs pkg to succeed when we ask it to install
# packages.  If that means waiting for other pkg installs to complete, fine.
# We wait 60 seconds per try, and retry up to 5 times.
LOCK_RETRIES = 5;
LOCK_WAIT = 60;

DEBUG_LEVEL = 1;
EOF

    pkg_install -y \
        curl \
        git-lite \
        py27-pip \
        sudo
    pip-2.7 --quiet install buildbot-slave

    pw useradd buildbot
    echo "buildbot ALL=(ALL) NOPASSWD: ALL" \
        >/usr/local/etc/sudoers.d/buildbot

    echo "fdescfs /dev/fd fdescfs rw 0 0" >> /etc/fstab
    mount /dev/fd

    if [ -c /dev/nda1 ]; then
        nvme=nda1
    elif [ -c /dev/nvd1 ]; then
        nvme=nvd1
    else
        nvme=""
    fi
    if [ -n "$nvme" ]; then
        gpart create -s gpt ${nvme}
        gpart add -t freebsd-ufs ${nvme}
        newfs ${nvme}p1
        echo "/dev/${nvme}p1 /mnt ufs rw,noatime" >> /etc/fstab
        mount /mnt
    fi
    ;;

Ubuntu*)
    while [ -s /var/lib/dpkg/lock ]; do sleep 1; done
    apt-get --yes update

    # As of Ubuntu 18.04 buildbot v1.0 is provided from the repository.  This
    # version is incompatible v0.8 on master, so use the older pip version.
    VERSION=$(lsb_release -rs | cut -f1 -d'.')
    if test $VERSION -ge 18; then
        BB_USE_PIP=1
    fi

    # Relying on the pip version of the buildworker is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then

        # Python 2 has been removed from Ubuntu 20.04.  The required pip2
        # packages are provided by https://pip.pypa.io/en/stable/installing/
        if test $VERSION -eq 18; then
            apt-get --yes install gcc python-pip python-dev
        else
            apt-get --yes install gcc python2 python2-dev
            curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
            python2 ./get-pip.py
        fi

        pip --quiet install buildbot-slave
    else
        apt-get --yes install buildbot-slave
    fi

    # Install the latest kernel to reboot on to.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        apt-get --yes install --only-upgrade linux-image-generic
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    # Set the sudo umask to 0000, this ensures that all .gcda profiling files
    # will be modifiable by the buildbot user even when created under sudo.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    echo "Defaults umask = 0000" >> /etc/sudoers
    echo "Defaults umask_override" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/a\Defaults exempt_group+=buildbot' /etc/sudoers
    sed -i.bak 's/updates/extra updates/' /etc/depmod.d/ubuntu.conf

    # Standardize ephemeral storage so it's available under /mnt.
    standardize_storage /dev/null
    ;;

*)
    echo "Unknown distribution, cannot bootstrap $BB_NAME"
    ;;
esac

set +x

if [ -x /usr/bin/buildslave ]; then
    BUILDWORKER="/usr/bin/buildslave"
else
    BUILDWORKER="/usr/local/bin/buildslave"
fi

# Generic buildworker configuration
if test ! -d $BB_DIR; then
    mkdir -p $BB_DIR
    chown buildbot:buildbot $BB_DIR
    sudo -E -u buildbot $BUILDWORKER create-slave --umask=022 --usepty=0 $BB_PARAMS
fi

# Extract some of the EC2 meta-data and make it visible in the buildworker
echo $BB_ADMIN > $BB_DIR/info/admin
$CURL "${METAROOT}/meta-data/public-hostname" > $BB_DIR/info/host
echo >> $BB_DIR/info/host
$CURL "${METAROOT}/meta-data/instance-type" >> $BB_DIR/info/host
echo >> $BB_DIR/info/host
$CURL "${METAROOT}/meta-data/ami-id" >> $BB_DIR/info/host
echo >> $BB_DIR/info/host
$CURL "${METAROOT}/meta-data/instance-id" >> $BB_DIR/info/host
echo >> $BB_DIR/info/host
uname -a >> $BB_DIR/info/host
grep MemTotal /proc/meminfo >> $BB_DIR/info/host
grep 'model name' /proc/cpuinfo >> $BB_DIR/info/host
grep 'processor' /proc/cpuinfo >> $BB_DIR/info/host

set -x

# Finally, start it.  If all goes well, at this point you should see a buildbot
# worker joining your farm.  You can then manage the rest of the work from the
# buildbot master.
if test "$BB_MODE" = "BUILD" -o "$BB_MODE" = "STYLE" -o "$(uname)" = "FreeBSD"; then
    sudo -E -u buildbot $BUILDWORKER start $BB_DIR
else
    echo "@reboot sudo -E -u buildbot $BUILDWORKER start $BB_DIR" | crontab -
    crontab -l
    sudo -E reboot
fi
