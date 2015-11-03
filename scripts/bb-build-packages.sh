#!/bin/sh -x

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
else
    echo "Missing configuration /etc/buildslave"
    exit 1
fi

CONFIG_LOG="configure.log"
case "$BB_NAME" in
CentOS*|RHEL*)
    # CentOS/RHEL provide a stable kabi use weak modules.
    CONFIG_OPTIONS="--enable-debug --with-spec=redhat"
    ;;
*)
    # Default build these packages are tied to this exact kernel version.
    CONFIG_OPTIONS="--enable-debug"
    ;;
esac
MAKE_LOG="make.log"
MAKE_OPTIONS=""
INSTALL_LOG="install.log"

./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1
./configure $CONFIG_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
make $MAKE_OPTIONS pkg >>$MAKE_LOG 2>&1 || exit 1

case "$BB_NAME" in
Amazon*)
    sudo rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    sudo yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1
    ;;

CentOS*)
    sudo rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    sudo yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1
    ;;

Debian*)
    for file in *.deb; do
        sudo gdebi --quiet --non-interactive $file >>$INSTALL_LOG 2>&1
    done
    ;;

Fedora*)
    sudo rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    sudo dnf -y localinstall *.rpm >>$INSTALL_LOG 2>&1
    ;;

RHEL*)
    sudo rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    sudo yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1
    ;;

SUSE*)
    sudo rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    sudo zypper --non-interactive install *.rpm >>$INSTALL_LOG 2>&1
    ;;

Ubuntu*)
    for file in *.deb; do
        sudo gdebi --quiet --non-interactive $file >>$INSTALL_LOG 2>&1
    done
    ;;

*)
    echo "$BB_NAME unknown platform" >>$INSTALL_LOG 2>&1
    ;;
esac

exit 0
