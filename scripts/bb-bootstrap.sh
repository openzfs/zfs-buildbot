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
if test -f /etc/buildslave; then
    . /etc/buildslave
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
    BB_ADMIN="Automated latent BuildBot slave <buildbot@zfsonlinux.org>"
fi
if test ! "$BB_DIR"; then
    BB_DIR="/var/lib/buildbot/slaves/zfs"
fi
if test ! "$BB_USE_PIP"; then
    BB_USE_PIP=0
fi
if test ! "$BB_KERNEL_TYPE"; then
    BB_KERNEL_TYPE="STD"
fi

if test ! -f /etc/buildslave; then
    echo "BB_MASTER=\"$BB_MASTER\""      > /etc/buildslave
    echo "BB_NAME=\"$BB_NAME\""         >> /etc/buildslave
    echo "BB_PASSWORD=\"$BB_PASSWORD\"" >> /etc/buildslave
    echo "BB_MODE=\"$BB_MODE\""         >> /etc/buildslave
    echo "BB_ADMIN=\"$BB_ADMIN\""       >> /etc/buildslave
    echo "BB_DIR=\"$BB_DIR\""           >> /etc/buildslave
    echo "BB_SHUTDOWN=\"Yes\""          >> /etc/buildslave
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

    if cat /etc/os-release | grep -Eq "Amazon Linux 2"; then
        BUILDSLAVE="/usr/bin/buildslave"
    else
        BUILDSLAVE="/usr/local/bin/buildslave"
    fi

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

    if test "$BB_MODE" != "PERF"; then
        # Standardize ephemeral storage so it's available under /mnt.
        sed -i.bak 's/\/media\/ephemeral0/\/mnt/' /etc/fstab
        if ! blkid /dev/xvdb >/dev/null 2>&1; then
            mkfs.ext4 /dev/xvdb
        fi
    fi

    # Enable partitions for loopback devices, they are disabled by default.
    echo "options loop max_part=15" >/etc/modprobe.d/loop.conf

    # Disable /dev/sda -> /dev/xvda symlinks which conflict with scsi_debug.
    if test -e /etc/udev/rules.d/51-ec2-hvm-devices.rules; then
        rm -f /etc/udev/rules.d/51-ec2-hvm-devices.rules
    fi

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
    sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    if cat /etc/redhat-release | grep -Eq "6."; then
        # The buildbot-slave package isn't available from a common repo.
        BUILDSLAVE_URL="http://build.zfsonlinux.org"
        BUILDSLAVE_RPM="buildbot-slave-0.8.8-2.el6.noarch.rpm"
        yum -y install $BUILDSLAVE_URL/$BUILDSLAVE_RPM
        BUILDSLAVE="/usr/bin/buildslave"
    else
        yum --enablerepo=epel -y install gcc python-pip python-devel
        pip --quiet install buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
    fi

    # Install the latest kernel to reboot on to.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        yum -y update kernel

        # User namespaces must be enabled at boot time for CentOS 7
        if cat /etc/redhat-release | grep -Eq "7."; then
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
    # This is the default.
    ;;

Debian*)
    apt-get --yes update

    # As of Debian 10 buildbot v1.0 is provided from the repository.  This
    # version is incompatible v0.8 on master, so use the older pip version.
    VERSION=$(cut -f1 -d'.' /etc/debian_version)
    if test $VERSION -ge 10; then
        BB_USE_PIP=1
    fi

    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        apt-get --yes install gcc curl python-pip python-dev
        pip --quiet install buildbot-slave
        BUILDSLAVE="/usr/local/bin/buildslave"
    else
        apt-get --yes install curl buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
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

    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        dnf -y install gcc python-pip python-devel
        pip --quiet install buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
    else
        dnf -y install buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
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

        # Ensure crontab is installed to start the build slave post reboot.
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
    # This is the default.
    ;;

FreeBSD*)
    pkg install -y \
        curl \
        git-lite \
        py27-pip \
        sudo
    pip-2.7 --quiet install buildbot-slave
    BUILDSLAVE="/usr/local/bin/buildslave"

    pw useradd buildbot
    echo "buildbot ALL=(ALL) NOPASSWD: ALL" \
        >/usr/local/etc/sudoers.d/buildbot
    ;;

RHEL*)
    # Required repository packages
    if cat /etc/redhat-release | grep -Eq "6."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    elif cat /etc/redhat-release | grep -Eq "7."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    else
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    yum --enablerepo=epel -y install deltarpm gcc python-pip python-devel
    pip --quiet install buildbot-slave
    BUILDSLAVE="/usr/bin/buildslave"

    # Install the latest kernel to reboot on to.
    if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
        yum -y update kernel
    fi

    # Use the debug kernel instead if indicated
    if test "$BB_KERNEL_TYPE" = "DEBUG"; then
        yum -y install kernel-debug
        set_boot_kernel
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
        echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
        sed -i.bak '/secure_path/a\Defaults exempt_group+=buildbot' /etc/sudoers
    fi

    # Standardize ephemeral storage so it's available under /mnt.
    # This is the default.
    ;;

Ubuntu*)
    while [ -s /var/lib/dpkg/lock ]; do sleep 1; done
    apt-get --yes update
    apt-get --yes install gcc python-pip python-dev

    # As of Ubuntu 18.04 buildbot v1.0 is provided from the repository.  This
    # version is incompatible v0.8 on master, so use the older pip version.
    VERSION=$(lsb_release -rs | cut -f1 -d'.')
    if test $VERSION -ge 18; then
        BB_USE_PIP=1
    fi

    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        pip --quiet install buildbot-slave
        BUILDSLAVE="/usr/local/bin/buildslave"
    else
        apt-get --yes install buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
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
    ;;

    # Standardize ephemeral storage so it's available under /mnt.
    # This is the default.

*)
    echo "Unknown distribution, cannot bootstrap $BB_NAME"
    ;;
esac

set +x

# Generic buildslave configuration
if test ! -d $BB_DIR; then
    mkdir -p $BB_DIR
    chown buildbot:buildbot $BB_DIR
    sudo -E -u buildbot $BUILDSLAVE create-slave --umask=022 --usepty=0 $BB_PARAMS
fi

# Extract some of the EC2 meta-data and make it visible in the buildslave
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
# slave joining your farm.  You can then manage the rest of the work from the
# buildbot master.
if test "$BB_MODE" = "BUILD" -o "$BB_MODE" = "STYLE" -o "$(uname)" = "FreeBSD"; then
    sudo -E -u buildbot $BUILDSLAVE start $BB_DIR
else
    echo "@reboot sudo -E -u buildbot $BUILDSLAVE start $BB_DIR" | crontab -
    crontab -l
    sudo -E reboot
fi
