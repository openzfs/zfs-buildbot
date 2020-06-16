# ZFS on Linux Buildbot Patches

This directory contains ZFS-required patches to buildbot.

## 0001-Enable-run-time-AMI-determination.patch ## 

This is a update of the "0019-Enable-run-time-AMI-determination.patch"
patch from 2263ee93dfd670f06e416430cdb6dbfe498d3e97 to work on buildbot
3.2.0.  It is needed to dynamically lookup the latest FreeBSD AMI at
worker load time.
