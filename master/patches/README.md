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
0006-Force-root-volumes-to-be-deleted-upon-termination-on.patch
0007-Create-volumes.patch
0008-Allow-slaves-to-substantiate-in-parallel.patch
0009-Move-spot-price-historical-averaging-to-its-own-func.patch
0010-Allow-independant-EC2-price_multiplier-or-max_spot_p.patch
0011-Properly-handle-a-stale-broker-connection-on-ping.patch
0012-Add-debug-logging.patch
0013-Add-instance-id-to-build-properties.patch
0014-Remove-default-values-for-keypair-and-security-names.patch
0015-Add-VPC-support-to-EC2LatentBuildSlave.patch
0016-Add-support-for-block-devices-to-EC2LatentBuildSlave.patch
0017-Allow-control-over-environment-logging-MasterShellCo.patch
0018-Better-handling-for-instance-termination.patch
```

The patches cleanly apply on top of `9df5d7d2a4db811fde4780cc1555453ee0f12649`
in the buildbot Git repository, as well the buildbot 0.8.14 release.
