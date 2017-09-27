#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
    . /etc/buildslave
fi

GCOV_KERNEL="/sys/kernel/debug/gcov"
ZFS_BUILD=$(readlink -f ../zfs)

if $(sudo -E test ! -e "$GCOV_KERNEL"); then
    echo "Kernel Gcov disabled.  Skipping test cleanup."
    exit 3
fi

if [ -z "$CODECOV_TOKEN" -o \
     -z "$BUILDER_NAME" -o \
     -z "$BUILD_NUMBER" -o \
     -z "$ZFS_REVISION" -o \
     -z "$BASE_BRANCH" ]; then
    echo "Missing a required environment variable."
    exit 1
fi

function urlencode
{
    python -c "import urllib; print(urllib.quote('$1'));"
}

function echo_build_url
{
    local NAME=$(urlencode "$BUILDER_NAME")
    local NUMBER=$(urlencode "$BUILD_NUMBER")
    echo "http://build.zfsonlinux.org/builders/$NAME/builds/$NUMBER"
}

function upload_codecov_report_with_flag
{
    local PR_OR_BRANCH_OPT

    if [[ -z "$1" ]]; then
        echo "Can't upload Codecov report without a flag."
        exit 1
    fi

    #
    # When a PR number is specified, we prioritized that value, and
    # use the PR number as the branch name. If we don't specify a branch
    # name at all, the Codecov uploader script will automatically detect
    # a branch name to use when performing the upload (and what it
    # auto-detects is incorrect). Codecov support suggested we use
    # "pull/N" as the branch name for pull requests, which is what we're
    # doing here.
    #
    # When uploading a coverage report for a commit on an actual branch
    # of the main project repository, the PR_NUMBER should be the empty
    # string (since it's not a PR commit). Thus, when PR_NUMBER is
    # empty, we specify the branch only, when uploading the report; this
    # way, the commit is properly associated with the correct branch in
    # the Codecov UI.
    #
    if [[ -n "$PR_NUMBER" ]]; then
        PR_OR_BRANCH_OPT="-B pull/$PR_NUMBER -P $PR_NUMBER"
    elif [[ -n "$BASE_BRANCH" ]]; then
        PR_OR_BRANCH_OPT="-B $BASE_BRANCH"
    else
        #
        # We should have already caught this error using the environment
        # variable checking at the start of this cript, but it doesn't
        # hurt to double check that assumption.
        #
        echo "Missing PR_NUMBER or BASE_BRANCH environment variables."
        exit 1
    fi

    make code-coverage-capture
    curl -s https://codecov.io/bash | bash -s - \
        -c -Z -X gcov -X py -X xcode \
        -n "$BUILDER_NAME" \
        -b "$BUILD_NUMBER" \
        -C "$ZFS_REVISION" \
        -F "$1" \
        $PR_OR_BRANCH_OPT
}

function copy_kernel_gcov_data_files
{
    # Allow access to gcov files as a non-root user
    sudo chmod -R a+rx /sys/kernel/debug/gcov
    sudo chmod a+rx /sys/kernel/debug

    #
    # For the kernel modules, the ".gcda" and ".gcno" files will be
    # contained in the debugfs location specified by the $GCOV_KERNEL
    # variable, and then the path to the files will mimic the directory
    # structure used when building the modules.
    #
    # We're copying these gcov data files files out of the debugfs
    # directory, and into the $ZFS_BUILD directory; this way the gcov
    # data files for the kernel modules will be in the build directory
    # just like they are for the userspace files.
    #
    # By doing this, we don't have to differentiate between userspace
    # files and kernel module files when generating the gcov reports.
    #
    # It's important to note that the ".gcno" files will already be
    # contained in the build directory, but sometimes the files will be
    # prefixed with ".tmp_". Thus, we have to be careful when copying
    # these into the build directory, such that:
    #
    #  - If the ".gcno" files *do not* have the ".tmp_" prefix, the
    #    original files (already in the build directory) will not be
    #    replaced.
    #
    #  - If the ".gcno" files *do* have the ".tmp_" prefix, we'll copy
    #    the ".gcno" symlinks contained in the debugfs directory into
    #    the build directory. These symlinks will then point to the
    #    original files with the ".tmp_" prefix.
    #
    pushd "$GCOV_KERNEL$ZFS_BUILD" >/dev/null
    find . -name "*.gcda" -exec sh -c 'cp -v $0 '$ZFS_BUILD'/$0' {} \;
    find . -name "*.gcno" -exec sh -c 'cp -vdn $0 '$ZFS_BUILD'/$0' {} \;
    popd >/dev/null
}

#
# This variable is used when we upload the Codecov report, and allows
# the Codecov UI to link back to the buildbot build.
#
export CI_BUILD_URL=$(echo_build_url)

#
# In order to capture code coverage data about branches, we need to
# explicitly enable it via this environment variable. This will enable
# the "lcov_branch_coverage" option of lcov when we execute the
# "code-coverage-capture" make target later in this script.
#
export CODE_COVERAGE_BRANCH_COVERAGE=1

set -x
cd "${ZFS_BUILD}"

upload_codecov_report_with_flag "user"

#
# Now that we've uploaded the coverage report for the user execution
# (e.g. userspace commands, libraries, etc), we need to upload the
# report for the kernel execution. We remove all the user execution
# ".gcda" files and replace them with the kernel equivalents. This way,
# we can simply use the "make" target to generate the coverage report
# for the kernel files just like we did for the userspace files.
#
# Note, we cannot use the "code-coverage-clean" make target here,
# because that would remove the ".gcno" files that we need when
# generating the kernel coverage report.
#
find . -name '*.gcda' -delete
copy_kernel_gcov_data_files

upload_codecov_report_with_flag "kernel"

exit 0
