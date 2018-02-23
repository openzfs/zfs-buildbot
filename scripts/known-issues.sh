#!/bin/bash
#
# This script will generate HTML describing which failures have
# been observed by the buildbot when running ZFS Test Suite.  Its
# purpose is to allow developers to quickly assess the prevalence
# of any observed failures.
#

ZFSONLINUX_DIR="/home/buildbot/zfs-buildbot/master/*_TEST_"
ZFSONLINUX_MTIME=30
ZFSONLINUX_MMIN=$((ZFSONLINUX_MTIME*24*60))
ZFSONLINUX_ISSUES=$(curl -s https://api.github.com/search/issues?q=Test%20Case+type:issue+repo:zfsonlinux/zfs)

NUMBER_REGEX='^[0-9]+$'
DATE=$(date)
STATUS_LOW_CUTOFF=5
STATUS_MED_CUTOFF=20

STATUS_LOW="st_low"
STATUS_MED="st_med"
STATUS_HIGH="st_high"
STATUS_PR="st_pr"

STATUS_LOW_COLOR="#ffee3a"
STATUS_MED_COLOR="#ffa500"
STATUS_HIGH_COLOR="#ff9999"
STATUS_PR_COLOR="#f8f8f8"

STATUS_LOW_TEXT="low"
STATUS_MED_TEXT="medium"
STATUS_HIGH_TEXT="high"
STATUS_PR_TEXT=""

usage() {
cat << EOF
USAGE:
$0 [-h] [-d directory] [-m mtime]

DESCRIPTION:
	Dynamically generate HTML for the Known Issue Tracking page
	using the ZFS Test Suite results from the buildbot automated
	testing.

OPTIONS:
	-h		Show this message
	-d directory	Directory containing the buildbot logs
	-m mtime	Include test logs from the last N days.

EXAMPLE:

$0 -d ~/zfs-buildbot/master/*_TEST_ -m 30 \\
    >~/zfs-buildbot/master/public_html/known-issues.html

EOF
}

while getopts 'hd:m:' OPTION; do
	case $OPTION in
	h)
		usage
		exit 1
		;;
	d)
		ZFSONLINUX_DIR=$OPTARG
		;;
	m)
		ZFSONLINUX_MTIME=$OPTARG
		ZFSONLINUX_MMIN=$((ZFSONLINUX_MTIME*24*60))
		;;
	esac
done

cat << EOF
<!DOCTYPE html>
<html>
<head>
<title>Known Issue Tracking</title>
<meta name="keyword" content="zfs, linux"/>
<meta http-equiv="Content-type" content="text/html; charset=utf-8">
<script		  src="https://code.jquery.com/jquery-1.12.4.min.js"
			  integrity="sha256-ZosEbRLbNQzLpnKIkEdrPv7lOy9C27hHQ+Xp8a4MxAQ="
			  crossorigin="anonymous"></script>
<link rel="stylesheet" type="text/css" href="https://cdn.datatables.net/1.10.13/css/jquery.dataTables.min.css">
<script type="text/javascript" language="javascript" src="https://cdn.datatables.net/1.10.13/js/jquery.dataTables.min.js"></script>

<script type="text/javascript" language="javascript" src="https://cdn.datatables.net/plug-ins/1.10.16/sorting/enum.js"></script>

<script type="text/javascript">
\$(document).ready(function() {
	\$.fn.dataTable.enum( [ 'high', 'medium', 'low', '' ] );
	\$('#maintable').DataTable( {
		"columnDefs": [
			{ "visible": false, "targets": 3 }
		],
		"searching": true,
		"order": [[ 3, 'asc' ]],
		"displayLength": 50,
		"drawCallback": function ( settings ) {
			var api = this.api();
			var rows = api.rows( {page:'current'} ).nodes();
			var last=null;
 
			api.column(3, {page:'current'} ).data().each( function ( group, i ) {
				if ( last !== group ) {
					\$(rows).eq( i ).before(
					'<tr class="group"><td colspan="5">'+group+'</td></tr>'
					);
 
				last = group;
				}
			} );
		}
	} );
 
	// Order by the grouping
	\$('#maintable tbody').on( 'click', 'tr.group', function () {
		var currentOrder = table.order()[0];
		if ( currentOrder[0] === 3 && currentOrder[1] === 'asc' ) {
			table.order( [ 3, 'desc' ] ).draw();
		}
		else {
			table.order( [ 3, 'asc' ] ).draw();
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
.st_low {
	background:$STATUS_LOW_COLOR !important;
}
.st_med {
	background:$STATUS_MED_COLOR !important;
}
.st_high {
	background:$STATUS_HIGH_COLOR !important;
}
.st_pr {
	background:$STATUS_PR_COLOR !important;
}
.td_text {
	text-align:left;
	min-width:60%;
}
tr.group,
tr.group:hover {
	background-color: #ddd !important;
}
</style>

</head>
<body>
<h1 align='center'>Known Issue Tracking</h1>
<div id="intro">
<p>This page is updated regularly and contains a list of all ZFS Test Suite
issues observed during automated buildbot testing over the last
<b>$ZFSONLINUX_MTIME days</b>.</p>
<p>Refer to the <a href="https://github.com/zfsonlinux/zfs/labels/Test%20Suite">Test Suite</a> label in the issue tracker for a complete list of known issues.</p>
</div>
<div id='maindiv'>
<table id="maintable" class="display">
<thead>
<tr>
  <th>Issue</th>
  <th>Test Failures</th>
  <th>Test Name</th>
  <th>Origin</th>
  <th>Severity</th>
</tr>
</thead>
<tbody>
EOF

check() {
	git_log="$1-log-git_zfs-stdio"
	test_log="$1-log-shell_8-tests.bz2"

	# Ignore incomplete builds
	[[ ! -e "$git_log" ]] && return 1
	[[ ! -e "$test_log" ]] && return 1

	# Annotate pull requests vs branch commits
	if grep -q "refs/pull" "$git_log"; then
		origin=$(grep -m1 "git fetch" "$git_log" | \
		    cut -f5 -d' ' | cut -d '/' -f3)
	else
		origin=$(grep -m1 "git clone --branch" "$git_log" | \
		    cut -f4 -d' ')
	fi

	# Strip and print the failed test cases
	bzgrep -e '\[FAIL\]' "$test_log" | \
	    awk -F"zfs-tests/" '{print $2}' | \
	    cut -d' ' -f1 | sed "s/^/$origin	/"
}
export -f check

find $ZFSONLINUX_DIR -type f -mmin -$ZFSONLINUX_MMIN -regex ".*/[0-9]*" \
    -exec bash -c 'check "$0"' {} \; | \
    sort | uniq -c | sort -nr | while read LINE1;
do
	ZFSONLINUX_ISSUE=""
	ZFSONLINUX_FAIL=$(echo $LINE1 | cut -f1 -d' ')
	ZFSONLINUX_NAME=$(echo $LINE1 | cut -f3 -d' ')
	ZFSONLINUX_ORIGIN=$(echo $LINE1 | cut -f2 -d' ')
	ZFSONLINUX_STATUS=""

	# Test failure was from an open pull request or branch.
	if [[ $ZFSONLINUX_ORIGIN =~ $NUMBER_REGEX ]]; then
		pr="https://github.com/zfsonlinux/zfs/pull/$ZFSONLINUX_ORIGIN"
		ZFSONLINUX_ISSUE="<a href='$pr'>PR-$ZFSONLINUX_ORIGIN</a>"
		ZFSONLINUX_STATUS=$STATUS_PR
		ZFSONLINUX_STATUS_TEXT=$STATUS_PR_TEXT
		ZFSONLINUX_ORIGIN="Pull Requests"
	else
		ZFSONLINUX_ORIGIN="Branch: $ZFSONLINUX_ORIGIN"

		# Match test case name against open issues.  For an issue
		# to be matched it must contain "Test Case" in the title
		# and the base name of the failing test case.
		base=$(basename $ZFSONLINUX_NAME)
		issue=$(echo "$ZFSONLINUX_ISSUES" | jq ".items[] | \
		    select(.title | contains(\"$base\")) | \
		     {html_url, number }")
		url=$(echo "$issue"|grep html_url|cut -f2- -d':'|tr -d ' ",')
		number=$(echo "$issue"|grep number|cut -f2- -d':'|tr -d ' ",')
		ZFSONLINUX_ISSUE="<a href='$url'>$number</a>"

		if [[ $ZFSONLINUX_FAIL -le $STATUS_LOW_CUTOFF ]]; then
			ZFSONLINUX_STATUS=$STATUS_LOW
			ZFSONLINUX_STATUS_TEXT=$STATUS_LOW_TEXT
		elif [[ $ZFSONLINUX_FAIL -le $STATUS_MED_CUTOFF ]]; then
			ZFSONLINUX_STATUS=$STATUS_MED
			ZFSONLINUX_STATUS_TEXT=$STATUS_MED_TEXT
		else
			ZFSONLINUX_STATUS=$STATUS_HIGH
			ZFSONLINUX_STATUS_TEXT=$STATUS_HIGH_TEXT
		fi
	fi

	cat << EOF
<tr class='$ZFSONLINUX_STATUS'>
  <td>$ZFSONLINUX_ISSUE</td>
  <td>$ZFSONLINUX_FAIL</td>
  <td class='td_text'>$ZFSONLINUX_NAME</td>
  <td>$ZFSONLINUX_ORIGIN</td>
  <td>$ZFSONLINUX_STATUS_TEXT</td>
</tr>
EOF

done

cat << EOF
</tbody>
</table>
<div id="f_date">Last Update: $DATE by <a href="https://github.com/zfsonlinux/zfs-buildbot/blob/master/scripts/known-issues.sh">known-issues.sh</a></div>
</div>
</body>
</html>
EOF
