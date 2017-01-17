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
SCRIPTPATH=`pwd -P`
ZFSONLINUX_BRANCH="zfsonlinux/master"
ZFSONLINUX_GIT="https://github.com/zfsonlinux/zfs/commit"
ZFSONLINUX_EXCEPTIONS=$SCRIPTPATH/"openzfs-exceptions.txt"
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
    usr/src/tools/scripts/cstyle.pl"

NUMBER_REGEX='^[0-9]+$'
DATE=$(date)

STATUS_APPLIED_COLOR="#80ff00"
STATUS_EXCEPTION_COLOR="#80ff00"
STATUS_MISSING_COLOR="#ff9999"
STATUS_PR_COLOR="#ffee3a"
STATUS_NONAPPLICABLE_COLOR="#DDDDDD"

STATUS_APPLIED="st_appl"
STATUS_EXCEPTION="st_exc"
STATUS_MISSING="st_mis"
STATUS_PR="st_pr"
STATUS_NONAPPLICABLE="st_na"

STATUS_APPLIED_TEXT="Applied"
STATUS_EXCEPTION_TEXT="Applied"
STATUS_MISSING_TEXT="No existing pull request"
STATUS_PR_TEXT="Pull request"
STATUS_NONAPPLICABLE_TEXT="Not applicable to Linux"

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
<!DOCTYPE html>
<html>
<head>
<title>OpenZFS Tracking</title>
<meta name="keyword" content="zfs, linux"/>
<meta http-equiv="Content-type" content="text/html; charset=utf-8">
<script		  src="https://code.jquery.com/jquery-1.12.4.min.js"
			  integrity="sha256-ZosEbRLbNQzLpnKIkEdrPv7lOy9C27hHQ+Xp8a4MxAQ="
			  crossorigin="anonymous"></script>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.13/css/jquery.dataTables.min.css">
<script type="text/javascript" language="javascript" src="https://cdn.datatables.net/1.10.13/js/jquery.dataTables.min.js"></script>

<script type="text/javascript">
\$(document).ready(function() {
	\$('#maintable').DataTable( {
		"bPaginate": false,
		"order": [],
		sDom: "lrtip",
		initComplete: function () {
				var column = this.api().column(4);
				var select = \$('<select><option value=""></option></select>')
					.appendTo( \$(column.header()).empty() )
					.on( 'change', function () {
						var val = $.fn.dataTable.util.escapeRegex(
							\$(this).val()
						);

						column
							.search( val ? '^'+val+'$' : '', true, false )
							.draw();
					} );

				column.data().unique().sort().each( function ( d, j ) {
					select.append( '<option value="'+d+'">'+d+'</option>' )
				} );
		}
	} );
} );
</script>

<style>
#maindiv {
	width:90%;
	display: table;
	margin: 0 auto;
}
#intro {
	text-align:center;
	padding:20px;	
}
#f_date {
	text-align:right;
}
#maintable {
	text-align:center;
	border:0px;	
}
.st_appl {
	background:$STATUS_APPLIED_COLOR !important;
}
.st_exc {
	background:$STATUS_EXCEPTION_COLOR !important;
}
.st_mis {
	background:$STATUS_MISSING_COLOR !important;
}
.st_pr {
	background:$STATUS_PR_COLOR !important;
}
.st_na {
	background:$STATUS_NONAPPLICABLE_COLOR !important;
}
.td_text {
	text-align:left;
	min-width:60%;
}
</style>

</head>
<body>
<h1 align='center'>OpenZFS Commit Tracking</h1>
<div id="intro">
This page is updated regularly and shows a list of OpenZFS commits and their status in regard to the ZFS on Linux master branch. See <a href="https://github.com/zfsonlinux/zfs/wiki/OpenZFS-Patches">wiki</a> for more information about OpenZFS patches.
</div>
<div id='maindiv'>
<table id="maintable" class="display">
<thead>
<tr>
  <th>OpenZFS Issue</th>
  <th>OpenZFS Commit</th>
  <th>Linux Commit</th>
  <th class='td_text'>Description</th>
  <th>Status</th>
</tr>
</thead>
<tbody>
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
	EXCEPTION=$(grep -E "^$OPENZFS_ISSUE.+" "$ZFSONLINUX_EXCEPTIONS")
	if [ -n "$EXCEPTION" ]; then
		EXCEPTION_HASH=$(echo $EXCEPTION | cut -f2 -d' ')
		if [ "$EXCEPTION_HASH" == "-" ]; then
			ZFSONLINUX_HASH="-"
			ZFSONLINUX_STATUS=$STATUS_NONAPPLICABLE
			ZFSONLINUX_STATUS_TEXT=$STATUS_NONAPPLICABLE_TEXT
		elif [ -n "$EXCEPTION_HASH" ]; then
			ZFSONLINUX_HASH="<a href='$ZFSONLINUX_GIT/$EXCEPTION_HASH'>$EXCEPTION_HASH</a>"
			ZFSONLINUX_STATUS=$STATUS_EXCEPTION
			ZFSONLINUX_STATUS_TEXT=$STATUS_EXCEPTION_TEXT
		fi
	elif [ -n "$ZFSONLINUX_PR" ]; then
			ZFSONLINUX_ISSUE=$(basename $ZFSONLINUX_PR)
			ZFSONLINUX_HASH="<a href='$ZFSONLINUX_PR'>PR-$ZFSONLINUX_ISSUE</a>"
			ZFSONLINUX_STATUS=$STATUS_PR
			ZFSONLINUX_STATUS_TEXT=$STATUS_PR_TEXT
	else
		LINE2=$(git log --regexp-ignore-case --extended-regexp \
		    --no-merges --oneline \
		    --grep="$ZFSONLINUX_REGEX" $ZFSONLINUX_BRANCH)

		MATCH=$(echo $LINE2 | cut -f1 -d' ')
		if [ -n "$MATCH" ]; then
			ZFSONLINUX_HASH="<a href='$ZFSONLINUX_GIT/$MATCH'>$MATCH</a>"
			ZFSONLINUX_STATUS=$STATUS_APPLIED
			ZFSONLINUX_STATUS_TEXT=$STATUS_APPLIED_TEXT
		else
			ZFSONLINUX_HASH=""
			ZFSONLINUX_STATUS=$STATUS_MISSING
			ZFSONLINUX_STATUS_TEXT=$STATUS_MISSING_TEXT
		fi
	fi

	cat << EOF
<tr class='$ZFSONLINUX_STATUS'>
  <td><a href='$OPENZFS_URL/$OPENZFS_ISSUE'>$OPENZFS_ISSUE</a></td>
  <td><a href='$OPENZFS_GIT/$OPENZFS_HASH'>$OPENZFS_HASH</a></td>
  <td>$ZFSONLINUX_HASH</td>
  <td class='td_text'>$OPENZFS_DESC</td>
  <td>$ZFSONLINUX_STATUS_TEXT</td>
</tr>
EOF

done

popd >/dev/null

cat << EOF
</tbody>
</table>
<div id="f_date">Last Update: $DATE by <a href="https://github.com/zfsonlinux/zfs-buildbot/blob/master/scripts/openzfs-tracking.sh">openzfs-tracking.sh</a></div>
</div>
</body>
</html>
EOF
