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

# Track if we need to reboot before starting buildbot
REBOOT=0

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

enable_local_gpg_check () {
	# Make sure any F31 package we directly "yum install https://...."
	# does a signature check.
	echo "localpkg_gpgcheck=1" >> /etc/yum.conf
	echo "localpkg_gpgcheck=1" >> /etc/dnf/dnf.conf
}

disable_local_gpg_check () {
	sed -i 's/localpkg_gpgcheck=1/localpkg_gpgcheck=0/g' /etc/yum.conf /etc/dnf/dnf.conf
}

# Install the Fedora 31 RPM signing keys and verify they're correct.
# This is needed to install F31 python RPMs (and others) for workarounds
install_f31_keys () {
	if [ ! -e /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-31-x86_64 ] ; then
		yum -y install https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/31/Everything/x86_64/os/Packages/f/fedora-gpg-keys-31-1.noarch.rpm
	fi
	gpg --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-31-x86_64

	# Sanity check the signature we're importing
	# (From https://getfedora.org/security/)
	if ! gpg --fingerprint | sed 's/  / /g' 2>&1  | grep -q '7D22 D586 7F2A 4236 474B F7B8 50CB 390B 3C33 59C4' ; then
		echo "not correct F31 signature"
		exit 1
	fi
	enable_local_gpg_check
	rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-31-x86_64
}

# Hacks to install Python 2.7
#
# Only used on Almalinux 9
install_python2_from_source () {
	dnf -y install zlib-devel bzip2-devel ncurses-devel sqlite-devel gcc wget tar rpm cpio || true
	install_f31_keys

	# Python 2.7 can't build against the older openssl versions, so need
	# to install an older one.  The best canidate is to use the
	# Fedora 31 packages (which install without issue).
	dnf -y install alternatives || true
	dnf -y install https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/31/Everything/x86_64/os/Packages/c/compat-openssl10-1.0.2o-8.fc31.x86_64.rpm
	dnf -y install https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/31/Everything/x86_64/os/Packages/c/compat-openssl10-devel-1.0.2o-8.fc31.x86_64.rpm

	# Get the python source from the F31 src RPM.  The src RPM is signed
	# by Fedora, so we know it's valid.
	wget https://archives.fedoraproject.org/pub/archive/fedora/linux/releases/31/Everything/source/tree/Packages/p/python2-2.7.16-4.fc31.src.rpm

	# Sanity: check for Fedora key
	if ! rpm -K -v 'python2-2.7.16-4.fc31.src.rpm' | grep -q 'key ID' ; then
		echo "No key for package"
		exit 1
	fi
	# Verify key
	if ! rpm -K 'python2-2.7.16-4.fc31.src.rpm' ; then
		echo "Signature doesn't match"
		exit 1
	fi

	# Extract source
	rpm2cpio python2-2.7.16-4.fc31.src.rpm | cpio -idmv
	cp Python-2.7.16.tar.xz /opt

	cd /opt
	tar xf Python-2.7.16.tar.xz
	cd Python-2.7.16

	./configure --prefix=/usr --enable-shared --enable-unicode=ucs4 --with-ensurepip=install
	make -j
	make -j altinstall

	sudo update-alternatives --install /usr/bin/python python /usr/bin/python2.7 1
	sudo update-alternatives --install /usr/bin/python python2 /usr/bin/python2.7 1
	sudo alternatives --set python /usr/bin/python2.7
	sudo alternatives --set python2 /usr/bin/python2.7

	if [ ! -e /usr/bin/python2 ] ; then
		ln -s /usr/bin/python2.7 /usr/bin/python2
	fi

	echo "/usr/lib/python2.7" > /etc/ld.so.conf.d/python2.7-x86_64.conf
	echo "/usr/lib/python2.7" > /etc/ld.so.conf.d/python2-x86_64.conf
	echo "/usr/lib/python2.7" > /etc/ld.so.conf.d/pip2.7-x86_64.conf
	export LD_LIBRARY_PATH=/usr/lib/python2.7:$LD_LIBRARY_PATH
	ldconfig

	# Note that when we install the newly built zfs-dkms later on, it will
	# bring in kernel-devel as a dependency, which in turn brings in
	# openssl-devel as a dependency, which conflicts with
	# compat-openssl10-devel.  Now that we are done building python2, we
	# can remove compat-openssl10-devel to solve the problem.
	dnf -y remove compat-openssl10-devel

	# Disable localinstall rpm gpg check since we will be doing a
	# localinstall of our built packages later on (which are not signed).
	disable_local_gpg_check
}

# Standardize unused instance storage under /mnt.  Either the first unused
# NVMe device found, or any ephemeral storage specified in the block mapping.
# Passing /dev/null for inst_dev will result in the default AMI behavior.
standardize_storage () {
    inst_dev="$1"
    nvme_dev="$(ls -1 /dev/disk/by-id/*NVMe_Instance_Storage* | head -1)"

    if test -b "$nvme_dev"; then
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
    yum -y update kernel
    REBOOT=1

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
    if cat /etc/redhat-release | grep -Eq "release 6."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    elif cat /etc/redhat-release | grep -Eq "release 7."; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    elif cat /etc/redhat-release | grep -Eq "release 8"; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        yum -y install gcc
        yum -y module install python27
        alternatives --set python /usr/bin/python2
    elif cat /etc/redhat-release | grep -Eq "release 9."; then
	dnf config-manager --set-enabled crb
	dnf -y install epel-release
	yum --enablerepo=epel -y install deltarpm gcc
    else
        echo "No extra repo packages to install..."
    fi

    # To minimize EPEL leakage, disable by default...
    sed -e "s/enabled=1/enabled=0/g" -i /etc/yum.repos.d/epel.repo

    # The cloud-init-19.4-7.el7 package broke rebooting instances due to
    # an incorrect dependency on NetworkManager.  Apply a workaround:
    # https://bugzilla.redhat.com/show_bug.cgi?id=1748015
    if cat /etc/redhat-release | grep -Eq "release 7."; then
        sed --in-place '/reload-or-try-restart NetworkManager.service/d' /etc/systemd/system/cloud-init.target.wants/cloud-final.service
    fi

    if cat /etc/redhat-release | grep -Eq "release 6."; then
        # The buildbot-slave package isn't available from a common repo.
        BUILDSLAVE_URL="http://build.zfsonlinux.org"
        BUILDSLAVE_RPM="buildbot-slave-0.8.8-2.el6.noarch.rpm"
        yum -y install $BUILDSLAVE_URL/$BUILDSLAVE_RPM
    elif cat /etc/redhat-release | grep -Eq "release 7."; then
        yum --enablerepo=epel -y install gcc python-pip python-devel

        # python2 pip support has ended, install last version released
        # https://stackoverflow.com/questions/65896334/python-pip-broken-wiith-sys-stderr-writeferror-exc
        pip install --upgrade "pip < 21.0"

        pip --quiet install buildbot-slave
    elif cat /etc/redhat-release | grep -Eq "release 8"; then
        if which pip2 > /dev/null ; then
            pip2 install buildbot-slave
        elif which pip > /dev/null ; then
            pip install buildbot-slave
        else
            pip3 install buildbot-slave
        fi
    elif cat /etc/redhat-release | grep -Eq "release 9."; then
        install_python2_from_source
        pip2.7 install pathlib
        pip2.7 install twisted
        pip2.7 install buildbot-slave==0.8.14
    else
        echo "Unknown CentOS release:"
        cat /etc/redhat-release
    fi

    # Install the latest kernel to reboot on to.
    yum -y update kernel
    REBOOT=1

    # User namespaces must be enabled at boot time for CentOS 7
    if cat /etc/redhat-release | grep -Eq "release 7."; then
        grubby --args="user_namespace.enable=1" \
            --update-kernel="$(grubby --default-kernel)"
        grubby --args="namespace.unpriv_enable=1" \
            --update-kernel="$(grubby --default-kernel)"
        echo "user.max_user_namespaces=3883" > /etc/sysctl.d/99-userns.conf
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

    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        apt-get --yes install gcc curl python-pip python-dev
        pip --quiet install buildbot-slave
    else
        apt-get --yes install curl buildbot-slave
    fi

    # Install the latest kernel to reboot on to.
    ARCH=$(dpkg --print-architecture)
    apt-get --yes install --only-upgrade linux-image-$ARCH
    REBOOT=1

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

    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then

        # Python 2 has been removed from Fedora 32.  The required pip2
        # pacakages are still provided by the UnitedRPMs repository.
        if test $VERSION -ge 32; then
            yum -y install --skip-broken \
                https://kojipkgs.fedoraproject.org/packages/python-pip/19.1.1/7.fc31/noarch/python2-pip-19.1.1-7.fc31.noarch.rpm \
                https://kojipkgs.fedoraproject.org/packages/python-setuptools/41.6.0/1.fc31/noarch/python2-setuptools-41.6.0-1.fc31.noarch.rpm
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
    if grep -q "Rawhide" /etc/fedora-release; then
        dnf config-manager --add-repo=http://dl.fedoraproject.org/pub/alt/rawhide-kernel-nodebug/fedora-rawhide-kernel-nodebug.repo
        dnf update
        dnf -y --enablerepo=fedora-rawhide-kernel-nodebug \
            update kernel-core kernel-devel
    else
        dnf -y update kernel-core kernel-devel
    fi

    REBOOT=1

    # Ensure crontab is installed to start the build slave post reboot.
    dnf -y install cronie

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
        python27 \
        sudo
    python2.7 -m ensurepip
    pip --quiet install buildbot-slave

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
        nvmepart=$(gpart add -t freebsd-ufs ${nvme} | awk '{ print $1 }')
        newfs ${nvmepart}
        mount -o noatime /dev/${nvmepart} /mnt
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

    # Relying on the pip version of the buildslave is more portable but
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
    apt-get --yes install --only-upgrade linux-image-generic
    REBOOT=1

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
    BUILDSLAVE="/usr/bin/buildslave"
else
    BUILDSLAVE="/usr/local/bin/buildslave"
fi

# Generic buildslave configuration
if test ! -d $BB_DIR; then
    mkdir -p $BB_DIR/info
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
if test $REBOOT -eq 0; then
    sudo -E -u buildbot $BUILDSLAVE start $BB_DIR
else
    echo "@reboot sudo -E -u buildbot $BUILDSLAVE start $BB_DIR" | crontab -
    crontab -l
    sudo -E reboot
fi
