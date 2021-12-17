# The OpenZFS Buildbot Configuration

Welcome, this is the buildbot CI infrastructure used by the
[OpenZFS project](https://github.com/openzfs/zfs).  It's used to automate
the process of testing [pull requests](https://github.com/openzfs/zfs/pulls).
If you would like to contribute to improving our testing infrastructure
please open a pull request against this GitHub repository.

## Build and Test Strategy

### Pull Requests

The OpenZFS project relies on GitHub pull requests to track proposed
changes.  Your pull request will be automatically tested by the buildbot and
updated to reflect the results of the testing.  As you fix the code and push
revisions to your branch at GitHub those changes will queued for testing.
There is no need to close a pull request and open a new one.  However, it is
strongly recommended that when refreshing a pull request you rebase it against
the latest code to avoid merge conflicts.

Once a pull request passes all the automated regression testing it will be
reviewed for inclusion by at least two OpenZFS developers.  Normally they
will provide review feedback on the change and may ask you to modify your
pull request.  Please provide a timely responses for reviewers (within weeks,
not months) otherwise your submission could be postponed or even rejected.

When all of the required builders report as passed, and the reviewers have
added their signed-off-by the pull request can be merged.  After being merged
the buildbot tests the change again to ensure nothing was overlooked.  This is
done to ensure the buildbot always stays green.

In the unlikely event that this final round of testing reveals an issue the
merge may be reverted and the pull request reopened.  Please continue
iterating with the OpenZFS developers in a new pull request until the issue
is resolved the changes can be merged.

By default, the top most commit in your PR will be functionally tested on
a subset of required builders.  Furthermore, the top five commits in your
PR be compile tested.

Individual builders may be requested on a per-commit basis by including
the `Requires-builders:` directive in the commit message.  When requesting
specific builders they should be enumerated as a comma separated list.

* Supported Builders (Platforms / Distributions):

  * __amazon2__: Amazon Linux 2 (x86_64)
  * __centos6__: CentOS 6 (x86_64)
  * __centos7__: CentOS 7 (x86_64)
  * __centos8__: AlmaLinux 8 (x86_64)
  * __centos8stream__: CentOS 8 Stream (x86_64)
  * __debian8__: Debian 8 (armel, ppc64)
  * __debian10__: Debian 10 (x86_64, arm64)
  * __debian11__: Debian 11 (x86_64, arm64)
  * __fedora34__: Fedora 34 (x86_64)
  * __ubuntu16__: Ubuntu 16.04 LTS (i386)
  * __ubuntu18__: Ubuntu 18.04 LTS (x86_64)
  * __ubuntu20__: Ubuntu 20.04 LTS (x86_64)
  * __freebsd12__: FreeBSD 12 (x86_64)
  * __freebsd13__: FreeBSD 13 (x86_64)
  * __freebsd14__: FreeBSD 14 (x86_64)

* Additional Builders:

  * __arch__: Build for all supported architectures.
  * __builtin__: Build OpenZFS in to the latest (unreleased) Linux kernel.
  * __coverage__: Perform a code coverage analysis (ztest, ZTS).
  * __none__: Disable testing on all builders.
  * __perf__: Perform baseline performance testing.
  * __style__: Perform all required style checks.

* Examples:

  * `Requires-builders: arch,style,amazon2,coverage`
  * `Requires-builders: none`

### Builder Types

When a new pull request is opened it is queued up for testing on all of the
available builders.  There are four primary types of builders:

* STYLE: These builders are responsible for performing static analysis.
  Currently, style checking and linting is performed for each submitted
  change. Changes are required to pass static analysis before being
  accepted.

* BUILD: These builders are responsible for verifying that a change
  doesn't break the build on a given platform.  Every commit in the pull
  request is built and reported on individually.  This helps guarantee that
  developers never accidentally break the build.

  To maximize coverage the are builders for major Linux distributions and
  FreeBSD.  This allows us to catch distribution specific issues and to
  verify the build on a wide range of kernels.

  Additional builders are maintained to test alternate architectures.  If
  you're interested in setting up a builder for your distribution or
  architecture see the 'Adding a Builder' section below.

  No elevated permissions are required for this type of builder.  However,
  it is assumed that all required development tools and headers are already
  installed on the system.

* TEST: These builders are responsible for testing a change.  This is
  accomplished by first building new packages, installing those packages,
  and finally running a standard battery of tests.  Due to the time
  involved in running the entire suite of tests only the last commit in the
  pull request will be tested.

* PERF: These builders are responsible for running performance regression
  tests for a change. These builders are not used by default and are only used
  when `perf` is provided as an option to `Requires-builders` in a commit
  message.

Reliable test results are obtained by using ec2 latent builders.  This is
important because when testing kernel modules it is not uncommon for a flaw in
the patch to cause the system to panic.  In this case the build slave will be
suddenly disconnected and the master must be able to terminate the instance
and continue on testing the next pull request.

Therefore, for each pull request a new pristine ec2 instance is created and
the system is bootstrapped to start a new build slave.  This new slave needs
be configured such that the buildbot user is allowed to run the `sudo` command
without a password.  This ensures the build slave can install packages, load
the new kernel modules, and run other administrative commands.  Once all
testing has completed the instance is immediately terminated.

### Build Steps and the `runurl` Utility

The OpenZFS project's buildbot makes extensive use of the `runurl`
utility.  This small script takes as its sole argument the URL of a script to
execute.  This allows us to configure a build step which references a trusted
URL with the desired script.  This means the logic for a particular build step
can be separated from the `master.cfg` which has some advantages:

* Minimizes the disruption caused by restarting the buildbot to make
  changes live.  This is only required when modifying the `master.cfg`.
  For example, when adding/removing a builder or adding a test suite.

* Build and tests scripts can be run independently making it easy for
  developers to locally test proposed changes before submitting them.

* Allows for per-builder and per-build customization via the environment.
  Each script can optionally source the following files to influence its
  behavior.

  * `/etc/buildslave` - This file is dynamically generated by the
    `bb-bootstrap.sh` script and is run at boot time by the ec2 user data
    facility.  It includes all the information required to configure and
    start a latent buildslave.  Most importabtly for scripts this includes
    the `BB_NAME` variable which is set to the build slave name.

  * `<builddir>/TEST` - This file is dynamically generated by the
    `bb-test-prepare.sh` script which is run before any of the test suites.
    It contains the contents of the TEST file from the ZFS source tree being
    tested.  Additionally, all lines in your commit message which begin with
    `TEST_` are appended to it.  This allows for the commit message to control
    the exact testing being performed.

* Provides a consistent way to trap and handle signals from the buildbot
  master.  This is particularly helpful when attempting to collect debug
  information prior to terminating an instance.

### Test Suites

To perform comprehensive testing binary packages are built, installed, and
used by all the test suites.  This helps catch both packaging mistakes and
ensures we are testing in a realistic environment.  However, some
customization of the environment is required and that is the job of the
`bb-test-prepare.sh` script.  It dynamically generates the TEST file
described above and may further customize the environment as needed.

After the environment has been prepared all of the registered test suites are
run as separate build steps using `runurl`.  By convention each of these
scripts is named `bb-test-*` and expected to exit with zero on success.  An
exit value of 1 indicates failure, 2 indicates a warning, and 3 indicates the
step was skipped.  If a build step fails the entire build is consider a failure.
However, individual steps may exit with a warning or skipped exit code without
failing the build.  These steps are color coded in the waterfall and console
views so they are easy to identify.  A test script is expected to attempt to
cleanup the environment so subsequent test suites can be run.  Depending on the
severity of the failure this may not be possible and additional test results
should be treated skeptically.

A `bb-test-*` script should be designed to be as self-contained, flexible, and
resilient as possible.  A good example of this is the `bb-test-ztest.sh`
script which can be found in the `scripts/` directory.  It is laid out as
follows:

* Source the `/etc/buildslave` and `TEST` files to pick up the build slave
  configuration and any per-build customization to the environment.

* Check if the test suite should be skipped.  By convention a `TEST_*_SKIP`
  variable is used and when set to "Yes" the test is skipped.  Environment
  variables which can be overridden should try to follow the same naming
  convention: `TEST_<test-suite>_<variable>`.

* Conditionally apply default values for environment variables which have
  not been explicitly specified.  This makes is easy to skim the script and
  determine what options are available and what the defaults setting are.

* Add a trap which attempts to cleanup the test environment on EXIT.  This
  way if the script unexpectedly exits subsequent tests may still be able to
  run successfully.  This is also a good opportunity to collect useful debug
  output such as the contents of the  `dmesg` log.  Trapping SIGTERM is useful
  because the build master is configured to raise this signal before
  terminating a script which reaches its maximum timeout.

* At the core of the test script it should configure the environment as
  needed and then run the tests.  This will likely involve loading the kernel
  modules, setting up disks or files to be used as vdevs and invoking the
  actual test suite.  It's advisable to run the test suite as a subprocess
  and wait for it to complete.  This allows the parent process to continue
  to handle any signals it receives.

* Finally make sure your test script leaves the system as it found it.  In
  many case this can be handled by the existing EXIT trap but this should be
  kept in mind.

## Configuring the Master

### Credentials

The `master/passwords.py` file contains the credentials required for the
buildbot to interact with ec2 and GitHub.  It stores static passwords for
non-ec2 build slaves, the web interface and `buildbot try`.  See the
`master/passwords.py.sample` file for a complete description.

### Adding a Builder

The process for adding a new builder varies slightly depending on the type
(BUILD or TEST) and if it's a standard or latent builder.  In all cases the
process begins by adding the new builder and slave to the `master.cfg` file.
One important thing to be aware of is that each builder can potentially have
multiple build slaves.  However, the OpenZFS project configures each
builder to have exactly one build slave.

The first step is to determine what kind of slave your setting up.  Both
standard and latent build slaves are supported but only latent build slaves
are suitable for use by TEST builders.  Again this is because test slaves
expect a pristine test environment for every build and this can only be
reliably accomplished by using a new instance for every test run.

Once you've settled on the type of slave add a line to the `c['slaves']`
array in the BUILDSLAVES section of the `master.cfg`.  Use the functions
`mkEC2BuildSlave`, `mkEC2TestSlave`, or `mkBuildSlave` as appropriate.

* mkEC2BuildSlave(name, ami) - Takes a user defined `name` and available
  `ami` identifier.  When using this type of slave a new on-demand ec2
  instance will be substantiated and bootstrapped using the ec2 user data
  interface.  Make sure the `bb-bootstrap.sh` script has been updated to be
  aware of how to install and start the build slave based the `name` provided.
  The name normally includes the distribution and version to make is easy to
  install and start the build slave.  Once running this type of slave won't be
  terminated until the builders pending queue has been empty for 30 minutes.
  This allows for multiple builds to be handled in quick succession.

* mkEC2TestSlave(name, ami) - An ec2 test slave is virtually the same as
  an ec2 build slave but they do differ in a few important ways.  Most
  importantly a test slave creates a large ec2 spot instance.  Large instances
  with multiple processors aren't required for building but they are needed to
  expose concurrency issues.  Test instances are terminated and re-instantiated
  between every build to guarantee reproducible results.

* mkBuildSlave(name) - Used to create a normal dedicated build slave with
  the given `name`.  Build slaves of this type must be manually configured to
  connect to the build master at `build.openzfs.org:9989` using a prearranged
  password.  This password is stored along with the slave name in the
  `master/passwords.py` file.  The build slave must be available 24/7 to run
  jobs and have all required ZFS build dependencies installed.  This kind of
  builder is best suited for testing non-x86 architectures which are
  unsupported by ec2.

Now that you've created a build slave a builder needs to be created which owns
it.  Jump down to the `c['builders']` array in the BUILDERS section and add a
`BuilderConfig` entry to the appropriate section.  Each builder must have a
unique `name` and your slave must be added to the list of `slavenames`.  Set
the `factory` to `build_factory` for BUILD type builders and use the
`test_factory` for TEST builders.  Then set `properties`, `tags` and
`mergeRequests` options as appropriate.

Next add the builder by name to either the `build_builders` or `test_builders`
list in the SCHEDULERS section.  These describe which builders should react to
incoming changes.

Finally, you must restart the build master to make it aware of your new
builder.  It's generally a good idea to run `buildbot checkconfig` to verify
your changes.  Then wait until the buildbot is idle before running
`buildbot restart` in order to avoid killing running builds.

### Updating an EC2 Build Slave to Use a Different AMI

New AMIs for the latest release of a distribution are frequently published for
ec2.  These updated AMIs can be used by replacing the current AMI identifier
used by the build slave with the new AMI identifier.  All build slaves are
listed in the BUILDSLAVES section of the `master.cfg` file.  Remember the
buildbot will need to be restarted to pick up the change.

### Adding a Test Suite

Test suites are added as a new `test_factory` build step in the FACTORIES
section of the `master.cfg` file.  As described in the 'Test Suites' section
each test suite consists of a wrapper script which is executed by the
`runurl` utility.

All test scripts should be named `bb-test-*` and placed in the `scripts/`
directory.  When `command` is executed the script will be fetched and run.  At
a minimum each build step should run in a different `workdir` and specify a
maximum run time using `maxTime`.  By default buildbot will log all output to
stdio.  Optionally, the contents of specific files can be logged by adding
them to `logfiles`.  Finally, set a clear `description` and `descriptionDone`
message to be reported by the web interface.

To activate the new build step the build master must be restarted.  It's
generally a good idea to run `buildbot checkconfig` to verify your changes.
Then wait until the buildbot is idle before running `buildbot restart` in
order to avoid killing running builds.

### Running a Private Master

The official OpenZFS buildbot can be accessed by everyone at
http://build.openzfs.org/ and it is integrated with the project's GitHub
pull requests.  Developers are encouraged to use this infrastructure when
working on a change.  However, this code can be used as a basis for building
a private build and test environment.  This may be useful when working on
extending the testing infrastructure itself.

Generally speaking to do this you will need to create a `password.py` file
with your credentials, then list your builders in the `master.cfg` file, and
finally start the builder master.  It's assumed you're already familiar with
Amazon ec2 instances and their terminology.

## Licensing

See the [LICENSE](LICENSE) file for license rights and limitations.
