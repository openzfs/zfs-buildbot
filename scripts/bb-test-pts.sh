#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildworker; then
	. /etc/buildworker
fi

# Custom test options will be saved in the tests directory.
if test -f "./TEST"; then
	. ./TEST
fi

TEST_PTS_SKIP=${TEST_PTS_SKIP:-"No"}
if echo "$TEST_PTS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
	echo "Skipping disabled test"
	exit 3
fi

ZPOOL=${ZPOOL:-"zpool"}
ZFS=${ZFS:-"zfs"}
PTS=${PTS:-"phoronix-test-suite"}
CONFIG_LOG="$PWD/config.log"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
	# Preserve the results directory for future analysis, as:
	# <zfs-version>/<builder>/pts/pts-<date>.tar.xz
	if test -n "$UPLOAD_DIR"; then
		BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"
		mkdir -p "$UPLOAD_DIR/$BUILDER/pts"

		tar -C "$RESULTS_DIR" -cJ \
	            -f "$UPLOAD_DIR/$BUILDER/pts/${TEST_RESULTS_NAME}.tar.xz" \
		    "$TEST_RESULTS_NAME"
	fi

	sudo modprobe -r brd
	sudo -E $ZFS_SH -u
}
trap cleanup EXIT SIGTERM

set -x

TEST_PTS_URL=${TEST_PTS_URL:-"https://github.com/phoronix-test-suite/phoronix-test-suite/archive/"}
TEST_PTS_VER=${TEST_PTS_VER:-"master.tar.gz"}
TEST_PTS_POOL=${TEST_PTS_POOL:-"perf"}
TEST_PTS_POOL_OPTIONS=${TEST_PTS_POOL_OPTIONS:-""}
TEST_PTS_FS=${TEST_PTS_FS:-"fs"}
TEST_PTS_FS_OPTIONS=${TEST_PTS_FS_OPTIONS:-""}
TEST_PTS_TEST_PROFILE_URL=${TEST_PTS_TEST_PROFILE_URL:-"https://raw.githubusercontent.com/openzfs/zfs-buildbot/master/scripts/"}
TEST_PTS_TEST_PROFILE_VER=${TEST_PTS_TEST_PROFILE_VER:-"pts-test-profiles.tar.gz"}

# Test cases to run.
TEST_PTS_BENCHMARKS=${TEST_PTS_BENCHMARKS:-" \
    zfs/aio-stress \
    zfs/compilebench \
    zfs/dbench \
    zfs/postmark \
    zfs/sqlite \
    zfs/unpack-linux \
"}

set +x

sudo modprobe brd rd_nr=2 rd_size=2097152

# Performance testing is done on an AWS EC2 d2.xlarge instance type:
# 4 vCPUS
# 30.5 GB of Memory
# 3x2TB HDDs (xvdb, xvdc, xvdd)
#
# Ramdisks are used to simulate fast SSDs for log and cache devices:
# 2x2GB SSDs (ram0, ram1)
#
RAIDZS="raidz xvdb xvdc xvdd"
MIRRORS="mirror xvdb xvdc"
LOGS="log ram0"
CACHES="cache ram1"

# Configurations to test.
TEST_PTS_CONFIGS=( \
    "RAIDZ1 1x3-way:$RAIDZS" \
    "RAIDZ1 1x3-way+log+cache:$RAIDZS $LOGS $CACHES" \
    "MIRROR 1x2-way:$MIRRORS" \
    "MIRROR 1x2-way+log+cache:$MIRRORS $LOGS $CACHES" \
)

TEST_DIR="/$TEST_PTS_POOL/$TEST_PTS_FS"
RESULTS_DIR="$HOME/.phoronix-test-suite/test-results/"
PROFILES_DIR="$HOME/.phoronix-test-suite/test-profiles/"

# Install and configure PTS is not already installed.
#
if ! type $PTS > /dev/null 2>&1; then
	case "$BB_NAME" in
	Amazon*)
		sudo yum -y install --enablerepo=epel phoronix-test-suite
		sudo yum -y install popt-devel
		;;
	*)
		wget -qO${TEST_PTS_VER} ${TEST_PTS_URL}${TEST_PTS_VER} || exit 1
		tar -xzf ${TEST_PTS_VER} || exit 1
		rm ${TEST_PTS_VER}

		cd phoronix-test-suite*
		sudo ./install-sh >>$CONFIG_LOG 2>&1 || exit 1
		cd ..
	esac

	$PTS enterprise-setup >>$CONFIG_LOG 2>&1
fi

# Refresh the download cache.
$PTS make-download-cache $TEST_PTS_BENCHMARKS >>CONFIG_LOG 2>&1

# Install the custom zfs test profiles.
rm -Rf $PROFILES_DIR/zfs
wget -qO- ${TEST_PTS_TEST_PROFILE_URL}${TEST_PTS_TEST_PROFILE_VER} | \
    tar xz -C $PROFILES_DIR

# Configure PTS and pool to start with a clean slate
$PTS user-config-set EnvironmentDirectory="$TEST_DIR" >>$CONFIG_LOG 2>&1
$PTS user-config-set ResultsDirectory="$RESULTS_DIR" >>$CONFIG_LOG 2>&1
$PTS user-config-set UploadResults="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set AnonymousUsageReporting="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set AnonymousSoftwareReporting="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set AnonymousHardwareReporting="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set SaveSystemLogs="TRUE" >>$CONFIG_LOG 2>&1
$PTS user-config-set SaveTestLogs="TRUE" >>$CONFIG_LOG 2>&1
$PTS user-config-set PromptForTestIdentifier="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set PromptForTestDescription="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set PromptSaveName="FALSE" >>$CONFIG_LOG 2>&1
$PTS user-config-set Configured="TRUE" >>$CONFIG_LOG 2>&1

case $(uname) in
FreeBSD)
	if ! kldstat -qn openzfs; then
		sudo -E $ZFS_SH
	fi
	;;
Linux)
	if ! test -e /sys/module/zfs; then
		sudo -E $ZFS_SH
	fi
	;;
*)
	sudo -E $ZFS_SH
	;;
esac

# If not given, read the zfs version and trim the hash to 7 characters.
# This ensures that once merged all the test results will be in the same
# directory.  Current git versions truncate to 9 characters by default.
if [ -z "$ZFS_VERSION" ]; then
	ZFS_VERSION="zfs-$(cat /sys/module/zfs/version)"
        if [[ "$ZFS_VERSION" =~ zfs-[0-9.]*-[0-9]*_g[0-9a-f]{9}$ ]]; then
		ZFS_VERSION="${ZFS_VERSION%??}"
	fi
	export ZFS_VERSION
fi

export TEST_RESULTS_NAME="pts-$(date +%Y%m%dt%H%M%S)"
export TEST_RESULTS_DESCRIPTION="Buildbot automated testing results"
export SYSTEM_LOGS="$RESULTS_DIR/$TEST_RESULTS_NAME/system-logs"

rm -Rf "$RESULTS_DIR/*"

for CONFIG in "${TEST_PTS_CONFIGS[@]}"; do
	ID=$(echo "$CONFIG" | cut -f1 -d':')
	VDEVS=$(echo "$CONFIG" | cut -f2 -d':')

	export TEST_RESULTS_IDENTIFIER="${ZFS_VERSION} $ID"

	sudo -E dmesg -c >/dev/null
	set -x
	sudo -E $ZPOOL create -f $TEST_PTS_POOL \
	    $TEST_PTS_POOL_OPTIONS $VDEVS || exit 1
	sudo -E $ZFS create $TEST_PTS_POOL/$TEST_PTS_FS \
	    $TEST_PTS_FS_OPTIONS || exit 1
	sudo -E chmod 777 $TEST_DIR

	$PTS batch-benchmark $TEST_PTS_BENCHMARKS

	LOG_DIR="$SYSTEM_LOGS/$TEST_RESULTS_IDENTIFIER"
	mkdir -p "$LOG_DIR"
	sudo -E $ZPOOL status -v >"$LOG_DIR/zpool-status.log"
	sudo -E $ZPOOL list -v >"$LOG_DIR/zpool-list.log"
	sudo -E $ZPOOL get all >"$LOG_DIR/zpool-get.log"
	sudo -E $ZPOOL iostat -rv >"$LOG_DIR/zpool-iostat-request-histogram.log"
	sudo -E $ZPOOL iostat -wv >"$LOG_DIR/zpool-iostat-latency-histogram.log"
	sudo -E $ZFS list >"$LOG_DIR/zfs-list.log"
	sudo -E $ZFS get all >"$LOG_DIR/zfs-get.log"
	sudo -E $ZPOOL destroy $TEST_PTS_POOL
	set +x

	dmesg >"$LOG_DIR/console.log"
done

exit 0
