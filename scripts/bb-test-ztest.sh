#!/bin/sh

if test -f /etc/buildslave; then
    . /etc/buildslave
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

CONSOLE_LOG="$PWD/console.log"

cleanup()
{
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
}
trap cleanup EXIT TERM

set -x

TEST_ZTEST_OPTIONS=${TEST_ZTEST_OPTIONS:-"-l -m3"}
TEST_ZTEST_TIMEOUT=${TEST_ZTEST_TIMEOUT:-900}
TEST_ZTEST_DIR=${TEST_ZTEST_DIR:-"/mnt"}
TEST_ZTEST_CORE_DIR=${TEST_ZTEST_CORE_DIR:-"/mnt/zloop"}

sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1
sudo -E $ZLOOP_SH $TEST_ZTEST_OPTIONS \
    -t $TEST_ZTEST_TIMEOUT \
    -f $TEST_ZTEST_DIR \
    -c $TEST_ZTEST_CORE_DIR &
CHILD=$!
wait $CHILD
RESULT=$?

if test $RESULT != 0; then
    echo "Exited ztest with error $RESULT"
    exit 1
fi

exit $RESULT
