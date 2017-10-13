#!/bin/sh

if test -f /etc/buildslave; then
	. /etc/buildslave
fi

LINUX_OPTIONS=${LINUX_OPTIONS:-""}
CONFIG_OPTIONS=${CONFIG_OPTIONS:-""}
MAKE_OPTIONS=${MAKE_OPTIONS:-"-j$(nproc)"}
INSTALL_METHOD=${INSTALL_METHOD:-"none"}

CONFIG_LOG="configure.log"
MAKE_LOG="make.log"
INSTALL_LOG="install.log"

# Expect a custom Linux build in the ../linux/ directory.
if [ "$LINUX_CUSTOM" = "yes" ]; then
	LINUX_DIR=$(readlink -f ../linux)
	LINUX_OPTIONS="$LINUX_OPTIONS --with-linux=$LINUX_DIR " \
	    "--with-linux-obj=$LINUX_DIR"
fi

set -x

sh ./autogen.sh >>$CONFIG_LOG 2>&1 || exit 1

case "$INSTALL_METHOD" in
packages|kmod|pkg-kmod|dkms|dkms-kmod)
	case "$INSTALL_METHOD" in
	packages|kmod|pkg-kmod)
		./configure $CONFIG_OPTIONS $LINUX_OPTIONS \
		    >>$CONFIG_LOG 2>&1 || exit 1
		make pkg-kmod >>$MAKE_LOG 2>&1 || exit 1
		;;
	dkms|pkg-dkms)
		./configure --with-config=srpm $CONFIG_OPTIONS $LINUX_OPTIONS \
		    >>$CONFIG_LOG 2>&1 || exit 1
		make pkg-dkms >>$MAKE_LOG 2>&1 || exit 1
		;;
	esac

	make pkg-utils >>$MAKE_LOG 2>&1 || exit 1
	sudo -E rm *.src.rpm

	case "$BB_NAME" in
	Amazon*)
		sudo -E yum -y localinstall *.rpm >$INSTALL_LOG 2>&1 || exit 1
		;;
	CentOS*)
		sudo -E yum -y localinstall *.rpm >$INSTALL_LOG 2>&1 || exit 1
		;;
	Debian*)
		sudo -E apt-get -y install ./*.deb >$INSTALL_LOG 2>&1 || exit 1
		;;
	Fedora*)
		sudo -E dnf -y localinstall *.rpm >$INSTALL_LOG 2>&1 || exit 1
		;;
	RHEL*)
		sudo -E yum -y localinstall *.rpm >$INSTALL_LOG 2>&1 || exit 1
		;;
	SUSE*)
		sudo -E zypper --non-interactive install *.rpm \
		    >$INSTALL_LOG 2>&1 || exit 1
		;;
	Ubuntu-14.04*)
		for file in *.deb; do
			sudo -E gdebi -n $file >$INSTALL_LOG 2>&1 || exit 1
		done
		;;
	Ubuntu*)
		sudo -E apt-get -y install ./*.deb >$INSTALL_LOG 2>&1 || exit 1
		;;
	*)
		echo "$BB_NAME unknown platform" >$INSTALL_LOG 2>&1
		;;
	esac
	;;
in-tree)
	./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
	make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
	./scripts/zfs-tests.sh -cv >>$INSTALL_LOG 2>&1
	sudo -E scripts/zfs-helpers.sh -iv >>$INSTALL_LOG 2>&1
	;;
none)
	./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
	make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
	;;
*)
	echo "Unknown INSTALL_METHOD: $INSTALL_METHOD"
	exit 1
	;;
esac

exit 0
