#!/bin/sh

if test -f /etc/buildworker; then
    . /etc/buildworker
fi

if test -f ./TEST; then
    . ./TEST
else
    echo "Missing $PWD/TEST configuration file"
    exit 1
fi

TEST_ZTEST_SKIP=${TEST_ZTEST_SKIP:-"No"}
if echo "$TEST_ZTEST_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

cleanup()
{
    # Preserve the results directory for future analysis, as:
    # <zfs-version>/<builder>/ztest/ztest-<date>.tar.xz
    if test -n "$UPLOAD_DIR"; then
        BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"
        mkdir -p "$UPLOAD_DIR/$BUILDER/ztest"

        # Optionally remove the zloop-run directory, normally this contains
        # logs and vdev from successful runs and thus is removed by default.
        if echo "$TEST_ZTEST_KEEP_RUN_DIR" | grep -Eiq "^no$|^off$|^false$|^0$"; then
            rm -Rf "$TEST_ZTEST_DIR/zloop-run"
        fi

        # Optionally remove the core directory, this contains logs and vdevs
        # from failed run and is kept by default.
        if echo "$TEST_ZTEST_KEEP_CORE_DIR"|grep -Eiq "^no$|^off$|^false$|^0$"; then
            sudo -E rm -Rf "$TEST_ZTEST_DIR/core"
        fi

        # Convenience symlinks will no longer reference the correct locations
        # and are removed so they're not included in the archive.
        rm -f $TEST_ZTEST_DIR/ztest.core.*
        sudo -E mv ztest.* "$TEST_ZTEST_DIR"

        sudo -E tar -C "$(dirname $TEST_ZTEST_DIR)" -cJ \
            -f "$UPLOAD_DIR/$BUILDER/ztest/$(basename $TEST_ZTEST_DIR).tar.xz" \
            "$(basename $TEST_ZTEST_DIR)"
    fi

    sudo -E $ZFS_SH -u
}
trap cleanup EXIT TERM

DATE="$(date +%Y%m%dT%H%M%S)"
set -x

TEST_ZTEST_OPTIONS=${TEST_ZTEST_OPTIONS:-"-l -m3"}
TEST_ZTEST_TIMEOUT=${TEST_ZTEST_TIMEOUT:-900}
TEST_ZTEST_DIR=${TEST_ZTEST_DIR:-"/mnt/ztest-${DATE}"}
TEST_ZTEST_KEEP_RUN_DIR="No"
TEST_ZTEST_KEEP_CORE_DIR="Yes"

set +x

case $(uname) in
FreeBSD)
	if ! kldstat -qn openzfs; then
		sudo -E $ZFS_SH
	fi
	sudo -E sysctl kern.threads.max_threads_per_proc=5000 >/dev/null
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

sudo -E mkdir -p "$TEST_ZTEST_DIR"
sudo -E $ZLOOP_SH $TEST_ZTEST_OPTIONS \
    -t $TEST_ZTEST_TIMEOUT \
    -f $TEST_ZTEST_DIR \
    -c $TEST_ZTEST_DIR/core
RESULT=$?

sudo -E chown -R $USER "$TEST_ZTEST_DIR"

if test $RESULT != 0; then
    echo "Exited ztest with error $RESULT"
    exit 1
fi

exit $RESULT
