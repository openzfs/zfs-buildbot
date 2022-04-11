#!/bin/bash
#
# This script tries to merge OpenZFS commits to ZoL.
#
# Instruction:
# 
# Repository setup must be similar with openzfs-tracking.sh
# requirements.
#
# Repository setup for valid compilation check:
#	./autogen.sh
#	./configure --enable-debug
#
# mandatory git settings:
#	[merge]
#   	renameLimit = 999999
#	[user]
#       email = mail@gmelikov.ru
#       name = George Melikov
#
# Copyright (c) 2016 George Melikov. All rights reserved.
#

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

REPOSITORY_PATH='.'
TMP_FILE='/tmp/gittmpmessage.txt'

# list with potential OpenZFS commits
UNPORTED_COMMITS_FILE=$SCRIPTDIR'/hashes.txt'

# Next files will generate automatically
# 	list with commits git can't merge automatically
EXCEPTIONS_GIT=$SCRIPTDIR'/exceptions.txt'
#	list with commits which can't be compiled without errors
EXCEPTIONS_COMPILE=$SCRIPTDIR'/uncompiled.txt'
#	list with commits which has cstyle error
EXCEPTIONS_CSTYLE=$SCRIPTDIR'/uncstyled.txt'
#	list with merged
EXCEPTIONS_MERGED=$SCRIPTDIR'/merged.txt'

LGREEN='\033[1;32m'		#  ${LGREEN}
LRED='\033[1;31m'		#  ${LRED}
NORMAL='\033[0m'		#  ${NORMAL} 
COUNT_MERGED=0
LIST_MERGED=
COUNT_COMPILE=0
LIST_COMPILE=
COUNT_CSTYLE=0
LIST_CSTYLE=
PUSH_NEW_BRANCH=0
FAIL_STYLE=0


usage() {
cat << EOF
USAGE:
$0 [-hp] [-d directory] [-i commits.txt] [-c commit hash] [-g commit hash]

DESCRIPTION:
	Auto merge OpenZFS commits to ZFS on Linux git
	repositories.
	Result - git branch with name 'autoport-oz#issue'

OPTIONS:
	-h		Show this message
	-d directory	Git repo with openzfs and zfsonlinux remotes
	-i commits.txt	File with OpenZFS commit hashes to merge
	(one hash per row)
	-c commit hash	Prepare branch and try to merge this commit by hash,
	leaves branch for manual merge if not successfull
	-g commit hash	Generate commit description for existing commit in
	branch generated by -i parameter
	-p		force push new branch to Github
	-s		Fail if style checks do not succeed after merge

EOF
}

clean_unmerged() {
	git cherry-pick --abort
	git checkout master
	git branch -D "autoport-oz$OPENZFS_ISSUE" > /dev/null 2>&1
	rm -f "$TMP_FILE"
}

prepare_git() {
	cd "$REPOSITORY_PATH"
	rm -f "$TMP_FILE"
	git checkout master
	git fetch --all
	git rebase zfsonlinux/master
	git log --remotes=openzfs/master --format=%B -n 1 $OPENZFS_COMMIT > "$TMP_FILE"
	OPENZFS_ISSUE=$(grep -oP '^[^0-9]*\K[0-9]+' -m 1 "$TMP_FILE")
}

push_to_github() {
	if [ $PUSH_NEW_BRANCH -ne 0 ]; then
		git push origin autoport-oz$OPENZFS_ISSUE -f
	fi
}

generate_desc() {
	USER_NAME=$(git config user.name)
	USER_MAIL=$(git config user.email)
	OPENZFS_COMMIT_AUTHOR=$(git log --format="%aN <%aE>" --remotes=openzfs/master -n 1 $OPENZFS_COMMIT)
	sed -i '/^$/d' "$TMP_FILE"

	# handle github keywords
	sed -i '/^closes #\|^close #\|^closed #/Id' "$TMP_FILE"
	sed -i '/^fixes #\|^fix #\|^fixed #/Id' "$TMP_FILE"
	sed -i '/^resolves #\|^resolve #\|^resolved #/Id' "$TMP_FILE"

	sed -i "1s/^$OPENZFS_ISSUE/OpenZFS $OPENZFS_ISSUE -/" "$TMP_FILE"
	sed -i "1 a Authored by: $OPENZFS_COMMIT_AUTHOR" "$TMP_FILE"
	sed -i -e '1a\\' "$TMP_FILE"
	
	echo 'Ported-by: '$USER_NAME' <'$USER_MAIL'>' >> "$TMP_FILE"
	echo '' >> "$TMP_FILE"
	echo 'OpenZFS-issue: https://www.illumos.org/issues/'$OPENZFS_ISSUE >> "$TMP_FILE"
	echo 'OpenZFS-commit: https://github.com/openzfs/openzfs/commit/'$OPENZFS_COMMIT >> "$TMP_FILE"
}

#add description to commit
add_desc_to_commit() {
	git commit --amend -F "$TMP_FILE"
}

# perform cherry-pick of patch
cherry-pick() {
	prepare_git
	
	echo -e "${LGREEN}OpenZFS Issue #$OPENZFS_ISSUE ($OPENZFS_COMMIT)${NORMAL}"
	echo -e "${LGREEN}Checkout new branch${NORMAL}"
	git branch -D "autoport-oz$OPENZFS_ISSUE" > /dev/null 2>&1
	git checkout -b "autoport-oz$OPENZFS_ISSUE"
	
	echo -e "${LGREEN}Performing cherry-pick of ${OPENZFS_COMMIT}${NORMAL}"
	if ! git cherry-pick $OPENZFS_COMMIT; then
		printf 'cherry-pick failed\n' >&2
		echo $OPENZFS_COMMIT >> "$EXCEPTIONS_GIT"
		return 1
	fi

	return 0
}

merge() {
	ERR=0

	if ! cherry-pick ; then
		return 1
	fi
	
	echo -e "${LGREEN}compile... ${NORMAL}"
	if ! make -s -j$(nproc); then
		printf 'compilation failed\n' >&2
		echo $OPENZFS_COMMIT >> "$EXCEPTIONS_COMPILE"
		COUNT_COMPILE=$(($COUNT_COMPILE+1))
		LIST_COMPILE="$LIST_COMPILE
		autoport-oz$OPENZFS_ISSUE"
		ERR=1
	fi
	
	echo -e "${LGREEN}cstyle... ${NORMAL}"
	if ! make cstyle; then
		printf 'style check failed\n' >&2
		echo $OPENZFS_COMMIT >> "$EXCEPTIONS_CSTYLE"
		COUNT_CSTYLE=$(($COUNT_CSTYLE+1))
		LIST_CSTYLE="$LIST_CSTYLE
		autoport-oz$OPENZFS_ISSUE"
		if [ $FAIL_STYLE -ne 0 ]; then
			ERR=1
		fi
	fi
	
	generate_desc
	add_desc_to_commit
	
	if [ "$ERR" -eq "0" ]; then
		push_to_github
		echo $OPENZFS_COMMIT >> $EXCEPTIONS_MERGED
		echo -e "${LGREEN}$OPENZFS_COMMIT merged without warnings${NORMAL}"
		COUNT_MERGED=$(($COUNT_MERGED+1))
		LIST_MERGED="$LIST_MERGED
		autoport-oz$OPENZFS_ISSUE"
	fi

	return 0
}

iterate_merge() {
	while read p; do
		OPENZFS_COMMIT=$p
		
		#if commit wasn't tried earlier
		EXCEPTION=$(grep -s -E "^$OPENZFS_COMMIT" "$EXCEPTIONS_GIT" \
		    "$EXCEPTIONS_COMPILE" "$EXCEPTIONS_CSTYLE" \
		    "$EXCEPTIONS_MERGED")

		if [ -n "$EXCEPTION" ]; then
			continue
		fi
		
		if ! merge ; then
			clean_unmerged
		fi
	done <$UNPORTED_COMMITS_FILE
}

prepare_manual() {
	if ! cherry-pick ; then
		echo -e "${LRED}$OPENZFS_COMMIT has merge conflicts${NORMAL}"
		return 1
	fi

	generate_desc
	add_desc_to_commit
	push_to_github

	echo -e "${LGREEN}$OPENZFS_COMMIT cherry-pick was successful${NORMAL}"
	return 0
}

while getopts 'hpd:i:c:g:s' OPTION; do
	case $OPTION in
	h)
		usage
		exit 1
		;;
	d)
		REPOSITORY_PATH="$OPTARG"
		;;
	i)
		UNPORTED_COMMITS_FILE=$OPTARG
		;;
	c)
		OPENZFS_COMMIT=$OPTARG
		;;
	p)
		PUSH_NEW_BRANCH=1
		;;
	g)
		OPENZFS_COMMIT=$OPTARG
		prepare_git
		git checkout "autoport-oz$OPENZFS_ISSUE"
		generate_desc
		add_desc_to_commit
		push_to_github
		exit 0
		;;
	s)
		FAIL_STYLE=1
		;;
	esac
done

# process the single commit if it was provided
if [ -n "$OPENZFS_COMMIT" ]; then
	if ! prepare_manual ; then
		exit 1
	fi

	exit 0
fi

iterate_merge

rm -f "$TMP_FILE"

#show results
echo ' '
if [ "$COUNT_MERGED" -gt "0" ]; then
	echo -e "${LGREEN}$COUNT_MERGED successfully merged commits:${NORMAL}"
	echo $LIST_MERGED
fi
if [ "$COUNT_COMPILE" -gt "0" ]; then
	echo -e "${LGREEN}$COUNT_COMPILE commits with compile errors:${NORMAL}"
	echo $LIST_COMPILE
fi
if [ "$COUNT_CSTYLE" -gt "0" ]; then
	echo -e "${LGREEN}$COUNT_CSTYLE commits with cstyle warnings:${NORMAL}"
	echo $LIST_CSTYLE
fi
