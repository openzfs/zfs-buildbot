# ZFS on Linux Buildbot Patches

This directory contains patches which have been applied to the ZFS on
Linux buildbot master.  Some of the patches were required to improve
reliability, others are bug fixes and finally several are to modify
the default behavior to facilitate the testing of kernel modules.
Each patch is fully described in its commit comment.

```
0001-Treat-RETRY-as-FAILURE.patch
0002-Add-isIdle-helper.patch
0003-Set-tags-for-latent-ec2-buildslaves.patch
0004-Retry-on-EC2-NotFound-errors.patch
0005-Soft-disconnect-when-build_wait_timeout-0.patch
```
