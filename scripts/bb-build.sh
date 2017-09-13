#!/bin/sh

# Check for a local cached configuration.
if test -f /etc/buildslave; then
	. /etc/buildslave
else
	echo "Missing configuration /etc/buildslave"
	exit 1
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
./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1

if [ "$INSTALL_METHOD" = "packages" ]; then
	make pkg >>$MAKE_LOG 2>&1 || exit 1

	case "$BB_NAME" in
	Amazon*)
		sudo -E rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
		sudo -E yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
		;;

	CentOS*)
		sudo -E rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
		sudo -E yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
		;;

	Debian*)
		for file in *.deb; do
			sudo -E gdebi -q --non-interactive $file \
			    >>$INSTALL_LOG 2>&1 || exit 1
		done
		;;

	Fedora*)
		sudo -E rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
		sudo -E dnf -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
		;;

	RHEL*)
		sudo -E rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
		sudo -E yum -y localinstall *.rpm >>$INSTALL_LOG 2>&1 || exit 1
		;;

	SUSE*)
		sudo -E rm *.src.rpm *.noarch.rpm >>$INSTALL_LOG 2>&1
		sudo -E zypper --non-interactive install *.rpm \
		    >>$INSTALL_LOG 2>&1 || exit 1
		;;

	Ubuntu*)
		for file in *.deb; do
		sudo -E gdebi -q --non-interactive $file \
		    >>$INSTALL_LOG 2>&1 || exit 1
		done
		;;

	*)
		echo "$BB_NAME unknown platform" >>$INSTALL_LOG 2>&1
		;;
	esac
elif [ "$INSTALL_METHOD" = "in-tree" ]; then
	make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
	./scripts/zfs-tests.sh -cv >>$INSTALL_LOG 2>&1
	sudo -E scripts/zfs-helpers.sh -iv >>$INSTALL_LOG 2>&1
elif [ "$INSTALL_METHOD" = "none" ]; then
	make $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
else
	echo "Unknown INSTALL_METHOD: $INSTALL_METHOD"
	exit 1
fi

exit 0
