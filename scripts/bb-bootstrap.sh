#!/bin/bash

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

set -e
set -x

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
if test ! "$BB_ADMIN"; then
    BB_ADMIN="Automated latent BuildBot slave <buildbot@zfsonlinux.org>"
fi
if test ! "$BB_DIR"; then
    BB_DIR="/var/lib/buildbot/slaves/zfs"
fi
if test ! "$BB_USE_PIP"; then
    BB_USE_PIP=0
fi

if test ! -f /etc/buildslave; then
    echo "BB_MASTER=\"$BB_MASTER\""      > /etc/buildslave
    echo "BB_NAME=\"$BB_NAME\""         >> /etc/buildslave
    echo "BB_PASSWORD=\"$BB_PASSWORD\"" >> /etc/buildslave
    echo "BB_ADMIN=\"$BB_ADMIN\""       >> /etc/buildslave
    echo "BB_DIR=\"$BB_DIR\""           >> /etc/buildslave
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

case "$BB_NAME" in
Amazon*)
    yum -y install deltarpm gcc python-pip python-devel
    easy_install --quiet buildbot-slave
    BUILDSLAVE="/usr/local/bin/buildslave"

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
        echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
        sed -i.bak '/secure_path/d' /etc/sudoers
    fi
    ;;

CentOS*)
    yum -y install deltarpm gcc python-pip python-devel
    easy_install --quiet buildbot-slave
    BUILDSLAVE="/usr/bin/buildslave"

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
        echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
        sed -i.bak '/secure_path/d' /etc/sudoers
    fi
    ;;

Debian*)
    apt-get --yes update

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

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/d' /etc/sudoers
    ;;

Fedora*)
    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        dnf -y install gcc python-pip python-devel
        easy_install --quiet buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
    else
        dnf -y install buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/d' /etc/sudoers
    ;;

Gentoo*)
    emerge-webrsync
    emerge app-admin/sudo dev-util/buildbot-slave
    BUILDSLAVE="/usr/bin/buildslave"

    # User buildbot needs to be added to sudoers and requiretty disabled.
    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    ;;

RHEL*)
    yum -y install deltarpm gcc python-pip python-devel
    easy_install --quiet buildbot-slave
    BUILDSLAVE="/usr/bin/buildslave"

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser buildbot
        echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
        sed -i.bak '/secure_path/d' /etc/sudoers
    fi
    ;;

SUSE*)
    # SLES appears to not always register their repos properly.
    echo "solver.allowVendorChange = true" >>/etc/zypp/zypp.conf
    while ! zypper --non-interactive up; do sleep 10; done
    while ! /usr/sbin/registercloudguest --force-new; do sleep 10; done

    # Zypper auto-refreshes on boot retry to avoid spurious failures.
    zypper --non-interactive install gcc python-devel python-pip
    easy_install --quiet buildbot-slave
    BUILDSLAVE="/usr/bin/buildslave"

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        groupadd buildbot
        useradd -g buildbot buildbot
        echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
        sed -i.bak '/secure_path/d' /etc/sudoers
    fi
    ;;

Ubuntu*)
    apt-get --yes update

    # Relying on the pip version of the buildslave is more portable but
    # slower to bootstrap.  By default prefer the packaged version.
    if test $BB_USE_PIP -ne 0; then
        apt-get --yes install gcc python-pip python-dev
        pip --quiet install buildbot-slave
        BUILDSLAVE="/usr/local/bin/buildslave"
    else
        apt-get --yes install buildbot-slave
        BUILDSLAVE="/usr/bin/buildslave"
    fi

    # User buildbot needs to be added to sudoers and requiretty disabled.
    if ! id -u buildbot >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" buildbot
    fi

    echo "buildbot  ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    sed -i.bak 's/ requiretty/ !requiretty/' /etc/sudoers
    sed -i.bak '/secure_path/d' /etc/sudoers
    ;;

*)
    echo "Unknown distribution, cannot bootstrap $BB_NAME"
    ;;
esac

# Generic buildslave configuration
if test ! -d $BB_DIR; then
    mkdir -p $BB_DIR
    chown buildbot.buildbot $BB_DIR
    sudo -u buildbot $BUILDSLAVE create-slave --umask=022 --usepty=0 $BB_PARAMS
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

# Finally, start it.
sudo -u buildbot $BUILDSLAVE start $BB_DIR

# If all goes well, at this point you should see a buildbot slave joining your
# farm.  You can then manage the rest of the work from the buildbot master.
