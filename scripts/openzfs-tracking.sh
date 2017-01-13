#!/bin/bash
#
# This script will generate markdown describing which OpenZFS have
# been applied to ZFS on Linux and which still must be ported.  The
# script must be run in a git repository with the following remotes.
#
#   zfsonlinux  https://github.com/zfsonlinux/zfs.git
#   openzfs     https://github.com/openzfs/openzfs.git
#
# Initial Setup:
#
# mkdir openzfs-tracking
# cd openzfs-tracking
# git clone -o zfsonlinux https://github.com/zfsonlinux/zfs.git
# cd zfs
# git remote add openzfs https://github.com/openzfs/openzfs.git
#
ZFSONLINUX_BRANCH="zfsonlinux/master"
ZFSONLINUX_GIT="https://github.com/zfsonlinux/zfs/commit"
ZFSONLINUX_EXCEPTIONS="openzfs-exceptions.txt"
ZFSONLINUX_DIR="."

OPENZFS_BRANCH="openzfs/master"
OPENZFS_HASH_START="1af68be"
OPENZFS_HASH_END="HEAD"
OPENZFS_URL="https://www.illumos.org/issues"
OPENZFS_GIT="https://github.com/openzfs/openzfs/commit"

# Only consider commits which modify one of the follow paths.
OPENZFS_PATHS=" \
    usr/src/uts/common/fs/zfs/sys usr/src/uts/common/fs/zfs usr/src/cmd/zdb \
    usr/src/cmd/zfs usr/src/cmd/zhack usr/src/cmd/zinject usr/src/cmd/zpool \
    usr/src/cmd/zstreamdump usr/src/cmd/ztest usr/src/lib/libzfs \
    usr/src/lib/libzfs_core usr/src/lib/libzpool usr/src/man/man1m/zdb.1m \
    usr/src/man/man1m/zfs.1m usr/src/man/man1m/zpool.1m \
    usr/src/man/man1m/zstreamdump.1m usr/src/common/zfs \
    usr/src/uts/common/fs/zfs usr/src/tools/scripts/cstyle.pl"

NUMBER_REGEX='^[0-9]+$'
DATE=$(date)

STATUS_APPLIED="#80ff00"
STATUS_EXCEPTION="#80ff00"
STATUS_MISSING="#ff9999"
STATUS_PR="#ffee3a"

usage() {
cat << EOF
USAGE:
$0 [-h] [-d directory] [-e exceptions]

DESCRIPTION:
	Dynamically generate HTML for the OpenZFS Commit Tracking page
	using the commit logs from both the OpenZFS and ZFS on Linux git
	repositories.

OPTIONS:
	-h		Show this message
	-d directory	Git repo with openzfs and zfsonlinux remotes
	-e exceptions	Exception file

EXAMPLE:

$0 -d ~/openzfs-tracking/zfs \\
    -e ~/zfs-buildbot/scripts/openzfs-exceptions.txt \\
    >~/zfs-buildbot/master/public_html/openzfs-tracking.html

EOF
}

while getopts 'hd:e:' OPTION; do
	case $OPTION in
	h)
		usage
		exit 1
		;;
	d)
		ZFSONLINUX_DIR=$OPTARG
		;;
	e)
		ZFSONLINUX_EXCEPTIONS=$OPTARG
		;;
	esac
done

cat << EOF
<html>
<head>
<title>OpenZFS Tracking</title>
<meta name="keyword" content="zfs, linux"/>
</head>
<body>
<table align="center" width="80%" border="0">
<tr bgcolor='#aaaaaa'>
  <th colspan='4'>OpenZFS Commit Tracking</th>
</tr>
<tr bgcolor='#dddddd'>
  <th>OpenZFS Issue</th>
  <th>OpenZFS Commit</th>
  <th>Linux Commit</th>
  <th>Description</th>
</tr>
EOF

pushd $ZFSONLINUX_DIR >/dev/null
ZFSONLINUX_PRS=$(curl -s https://api.github.com/repos/zfsonlinux/zfs/pulls)

git fetch --all >/dev/null
git log $OPENZFS_HASH_START..$OPENZFS_HASH_END --oneline $OPENZFS_BRANCH \
    -- $OPENZFS_PATHS | while read LINE1;
do
	OPENZFS_HASH=$(echo $LINE1 | cut -f1 -d' ')
	OPENZFS_ISSUE=$(echo $LINE1 | cut -f2 -d' ')
	OPENZFS_DESC=$(echo $LINE1 | cut -f3- -d' ' | \
	    sed 's#Reviewed.*##' | sed 's#Approved.*##')
	ZFSONLINUX_STATUS=""

	# Skip this commit of non-standard form.
	if ! [[ $OPENZFS_ISSUE =~ $NUMBER_REGEX ]]; then
		continue
	fi

	# Match issue against any open pull requests.
	ZFSONLINUX_PR=$(echo $ZFSONLINUX_PRS | jq -r ".[] | select(.title | \
	    contains(\"OpenZFS $OPENZFS_ISSUE\")) | { html_url: .html_url }" | \
	    grep html_url | cut -f2- -d':' | tr -d ' "')
	ZFSONLINUX_REGEX="^(openzfs|illumos)+.*[ #]+$OPENZFS_ISSUE[ ,]+*.*"

	# Commit exceptions reference this Linux commit for an OpenZFS issue.
	EXCEPTION=$(grep -E "^$OPENZFS_ISSUE.+" $ZFSONLINUX_EXCEPTIONS)
	if [ -n "$EXCEPTION" ]; then
		EXCEPTION_HASH=$(echo $EXCEPTION | cut -f2 -d' ')
		if [ "$EXCEPTION_HASH" == "-" ]; then
			continue
		elif [ -n "$EXCEPTION_HASH" ]; then
			ZFSONLINUX_HASH="<a href='$ZFSONLINUX_GIT/$EXCEPTION_HASH'>$EXCEPTION_HASH</a>"
			ZFSONLINUX_STATUS=$STATUS_EXCEPTION
		fi
	elif [ -n "$ZFSONLINUX_PR" ]; then
			ZFSONLINUX_ISSUE=$(basename $ZFSONLINUX_PR)
			ZFSONLINUX_HASH="<a href='$ZFSONLINUX_PR'>PR-$ZFSONLINUX_ISSUE</a>"
			ZFSONLINUX_STATUS=$STATUS_PR
	else
		LINE2=$(git log --regexp-ignore-case --extended-regexp \
		    --no-merges --oneline \
		    --grep="$ZFSONLINUX_REGEX" $ZFSONLINUX_BRANCH)

		MATCH=$(echo $LINE2 | cut -f1 -d' ')
		if [ -n "$MATCH" ]; then
			ZFSONLINUX_HASH="<a href='$ZFSONLINUX_GIT/$MATCH'>$MATCH</a>"
			ZFSONLINUX_STATUS=$STATUS_APPLIED
		else
			ZFSONLINUX_HASH=""
			ZFSONLINUX_STATUS=$STATUS_MISSING
		fi
	fi

	cat << EOF
<tr bgcolor='$ZFSONLINUX_STATUS'>
  <td align='center'><a href='$OPENZFS_URL/$OPENZFS_ISSUE'>$OPENZFS_ISSUE</a></td>
  <td align='center'><a href='$OPENZFS_GIT/$OPENZFS_HASH'>$OPENZFS_HASH</a></td>
  <td align='center'>$ZFSONLINUX_HASH</td>
  <td align='left' width='70%'>$OPENZFS_DESC</td>
</tr>
EOF

done

popd >/dev/null

cat << EOF
<tr bgcolor='#dddddd'>
  <td align='right' colspan='4'>Last Update: $DATE</td>
</tr>
</table>
</body>
</html>
EOF
