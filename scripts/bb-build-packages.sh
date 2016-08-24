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

SUDO="sudo -E"

./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1
./configure $CONFIG_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
make $MAKE_OPTIONS pkg >>$MAKE_LOG 2>&1 || exit 1

case "$BB_NAME" in
Amazon*)
    $SUDO rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    $SUDO yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
    ;;

CentOS*)
    $SUDO rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    $SUDO yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
    ;;

Debian*)
    for file in *.deb; do
        $SUDO gdebi -q --non-interactive $file >>$INSTALL_LOG 2>&1 || exit 1
    done
    ;;

Fedora*)
    $SUDO dnf -y install *.$(arch).rpm >>$INSTALL_LOG 2>&1 || exit 1
    ;;

RHEL*)
    $SUDO rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    $SUDO yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
    ;;

SUSE*)
    $SUDO rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
    $SUDO zypper --non-interactive install *.rpm >>$INSTALL_LOG 2>&1 || exit 1
    ;;

Ubuntu*)
    for file in *.deb; do
        $SUDO gdebi -q --non-interactive $file >>$INSTALL_LOG 2>&1 || exit 1
    done
    ;;

*)
    echo "$BB_NAME unknown platform" >>$INSTALL_LOG 2>&1
    ;;
esac

exit 0
