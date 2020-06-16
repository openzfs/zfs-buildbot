#!/bin/sh

if test -f /etc/buildworker; then
	. /etc/buildworker
fi

case "$BB_NAME" in
FreeBSD*)
	MAKE=gmake
	NCPU=$(sysctl -n hw.ncpu)
	;;
Amazon*|CentOS*|Debian*|Fedora*|SUSE*|Ubuntu*)
	MAKE=make
	NCPU=$(nproc)
	;;
*)
	echo "Unknown BB_NAME, assuming Linux"
	MAKE=make
	NCPU=$(nproc)
	;;
esac

LINUX_OPTIONS=${LINUX_OPTIONS:-""}
CONFIG_OPTIONS=${CONFIG_OPTIONS:-""}
MAKE_OPTIONS=${MAKE_OPTIONS:-"-j$NCPU"}
MAKE_TARGETS_KMOD=${MAKE_TARGETS_KMOD:-"pkg-kmod pkg-utils"}
MAKE_TARGETS_DKMS=${MAKE_TARGETS_DKMS:-"pkg-dkms pkg-utils"}
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

	./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1

	case "$INSTALL_METHOD" in
	packages|kmod|pkg-kmod)
		$MAKE $MAKE_TARGETS_KMOD >>$MAKE_LOG 2>&1 || exit 1
		;;
	dkms|pkg-dkms)
		$MAKE $MAKE_TARGETS_DKMS >>$MAKE_LOG 2>&1 || exit 1
		;;
	esac

	sudo -E rm *.src.rpm

	# Preserve TEST and PERF packages which may be needed to investigate
	# test failures.  BUILD packages are discarded.
	if test "$BB_MODE" = "TEST" -o "$BB_MODE" = "PERF"; then
		if test -n "$UPLOAD_DIR"; then
			BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"
			mkdir -p "$UPLOAD_DIR/$BUILDER/packages"
			cp *.deb *.rpm $UPLOAD_DIR/$BUILDER/packages
		fi
	fi

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
	$MAKE $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
	./scripts/zfs-tests.sh -cv >>$INSTALL_LOG 2>&1
	sudo -E scripts/zfs-helpers.sh -iv >>$INSTALL_LOG 2>&1
	;;
system)
	./configure $CONFIG_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
	$MAKE $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
	sudo -E $MAKE install >>$INSTALL_LOG 2>&1 || exit 1
	;;
none)
	./configure $CONFIG_OPTIONS $LINUX_OPTIONS >>$CONFIG_LOG 2>&1 || exit 1
	$MAKE $MAKE_OPTIONS >>$MAKE_LOG 2>&1 || exit 1
	;;
*)
	echo "Unknown INSTALL_METHOD: $INSTALL_METHOD"
	exit 1
	;;
esac

exit 0
