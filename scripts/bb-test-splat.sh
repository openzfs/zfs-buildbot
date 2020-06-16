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

TEST_SPLAT_SKIP=${TEST_SPLAT_SKIP:-"Yes"}
if echo "$TEST_SPLAT_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
    echo "Skipping disabled test"
    exit 3
fi

CONSOLE_LOG="$PWD/console.log"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
    dmesg >$CONSOLE_LOG
    sudo -E $ZFS_SH -u
    dmesg >$CONSOLE_LOG
}
trap cleanup EXIT

set -x

TEST_SPLAT_OPTIONS=${TEST_SPLAT_OPTIONS:-"-acvx"}

sudo -E dmesg -c >/dev/null
sudo -E modprobe splat || exit 1
sudo -E $SPLAT $TEST_SPLAT_OPTIONS &
CHILD=$!
wait $CHILD
RESULT=$?

exit $RESULT
