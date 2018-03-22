#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
	. /etc/buildslave
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
	sudo -E $ZPOOL destroy -f $TEST_PTS_POOL &>/dev/null
	if echo "$TEST_PTS_LOAD_KMODS" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
		sudo -E zfs.sh -uv
	fi
}
trap cleanup EXIT SIGTERM

set -x

TEST_PTS_URL=${TEST_PTS_URL:-"https://github.com/phoronix-test-suite/phoronix-test-suite/archive/"}
TEST_PTS_VER=${TEST_PTS_VER:-"master.tar.gz"}
TEST_PTS_POOL=${TEST_PTS_POOL:-"perf"}
TEST_PTS_POOL_OPTIONS=${TEST_PTS_POOL_OPTIONS:-""}
TEST_PTS_FS=${TEST_PTS_FS:-"fs"}
TEST_PTS_FS_OPTIONS=${TEST_PTS_FS_OPTIONS:-""}
TEST_PTS_LOAD_KMODS=${TEST_PTS_LOAD_KMODS:-"Yes"}
TEST_PTS_TEST_PROFILE_URL=${TEST_PTS_TEST_PROFILE_URL:-"https://raw.githubusercontent.com/zfsonlinux/zfs-buildbot/master/scripts/"}
TEST_PTS_TEST_PROFILE_VER=${TEST_PTS_TEST_PROFILE_VER:-"pts-test-profiles.tar.gz"}

# Test cases to run.
TEST_PTS_BENCHMARKS=${TEST_PTS_BENCHMARKS:-" \
    zfs/aio-stress \
    zfs/compilebench \
    zfs/dbench \
    zfs/fio \
    zfs/postmark \
    zfs/sqlite \
    zfs/unpack-linux \
"}

RAIDZS="raidz virtio-D00 virtio-D01 virtio-D02 virtio-D03 virtio-D04 virtio-D05"
MIRROR1="mirror virtio-D00 virtio-D01"
MIRROR2="mirror virtio-D02 virtio-D03"
MIRROR3="mirror virtio-D04 virtio-D05"
MIRRORS="$MIRROR1 $MIRROR2 $MIRROR3"
LOGS="log virtio-L00"
CACHES="cache virtio-C00"

# Configurations to test.
TEST_PTS_CONFIGS=( \
    "RAIDZ1 1x6-way:$RAIDZS" \
    "RAIDZ1 1x6-way+log+cache:$RAIDZS $LOGS $CACHES" \
    "MIRROR 3x2-way:$MIRRORS" \
    "MIRROR 3x2-way+log+cache:$MIRRORS $LOGS $CACHES" \
)

TEST_DIR="/$TEST_PTS_POOL/$TEST_PTS_FS"
RESULTS_DIR="$HOME/.phoronix-test-suite/test-results/"
PROFILES_DIR="$HOME/.phoronix-test-suite/test-profiles/"

set +x

# Install and configure PTS is not already installed.
#
if ! type $PTS > /dev/null 2>&1; then
	wget -qO${TEST_PTS_VER} ${TEST_PTS_URL}${TEST_PTS_VER} || exit 1
	tar -xzf ${TEST_PTS_VER} || exit 1
	rm ${TEST_PTS_VER}

	cd phoronix-test-suite*
	sudo -E ./install-sh >>$CONFIG_LOG 2>&1 || exit 1
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

if echo "$TEST_PTS_LOAD_KMODS" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
	set -x
	# Populate src/zfs/bin directory.
	zfs-tests.sh -c

	sudo -E zfs.sh -vu >/dev/null 2>&1
	sudo -E zfs.sh -v || exit 1

	set +x
fi

export ZFS_VERSION="$(cat /sys/module/zfs/version)"
export TEST_RESULTS_NAME="zfs-$(echo $ZFS_VERSION | tr '._' '-')"
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

if echo "$TEST_PTS_LOAD_KMODS" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
	sudo -E zfs.sh -uv
fi

exit 0
