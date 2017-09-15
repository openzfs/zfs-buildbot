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

function upload_codecov_reports
{
    pushd "${ZFS_BUILD}" >/dev/null
    curl -s https://codecov.io/bash | bash -s - \
        -c -Z -X gcov -X py -X xcode \
        -n "$BUILDER_NAME" \
        -b "$BUILD_NUMBER" \
        -C "$ZFS_REVISION" \
        -B "$BASE_BRANCH" \
        -P "$PR_NUMBER" \
        -F "$1"
    popd >/dev/null
}

function generate_gcov_reports
{
    #
    # The userspace libraries are a little tricky to generate coverage
    # data for them, because they often are compiled from source files
    # that are also included in the kernel modules. For now, to simplify
    # things, we're excluding the libraries from code coverage analysis.
    # Unfortunately, this means that things like ztest and libzpool will
    # not provide us any code coverage information.
    #
    find "$ZFS_BUILD" -name "*.gcno" -type f \
            -not -path "$ZFS_BUILD/lib/*" \
            -not -name ".*" \
            -exec dirname {} \; | sort | uniq | while read DIR; do
        pushd "$DIR" >/dev/null
        gcov -b *.gcno
        popd >/dev/null
    done
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

set -x
copy_kernel_gcov_data_files
generate_gcov_reports
upload_codecov_reports

exit 0
