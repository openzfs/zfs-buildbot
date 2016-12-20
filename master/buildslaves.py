# -*- python -*-
# ex: set syntax=python:

import string
import random
import re
from password import *
from buildbot.plugins import util
from buildbot.buildslave import BuildSlave
from buildbot.buildslave.ec2 import EC2LatentBuildSlave

### BUILDER CLASSES
class ZFSBuilderConfig(util.BuilderConfig):
    @staticmethod
    def nextSlave(builder, slaves):
        availableSlave = None

        for slave in slaves:
            # if we found an idle slave, immediate use this one
            if slave.isIdle():
                return slave

            # hold onto the first slave thats not spun up but free
            if availableSlave is None and slave.isAvailable():
                availableSlave = slave

        # we got here because there was no idle slave
        if availableSlave is not None:
            return availableSlave

        # randomly choose among all our busy slaves
        return (random.choice(slaves) if slaves else None)

    # builders should prioritize a merge into master or the final commit
    # from a pull request before building other commits. This avoids
    # starving smaller pull requests from getting feedback.
    @staticmethod
    def nextBuild(builder, requests):
        pattern = '^Pull-request:\s*#\d+\s*part\s*(?P<part>\d+)/(?P<total>\d+)$'

        # go thru each request's changes to prioritize them
        for request in requests:
            for change in request.source.changes:
                m = re.search(pattern, change.comments, re.I | re.M)

                # if we don't find the pattern, this was a merge to master
                if m is None:
                    return request

                part = int(m.group('part'))
                total = int(m.group('total'))

                # if the part is the same as the total, then we have the last commit
                if part == total:
                    return request

        # we didn't have a merge into master or a final commit on a pull request
        return requests[0]

    def __init__(self, mergeRequests=False, nextSlave=None, nextBuild=None, **kwargs):
        if nextSlave is None:
            nextSlave = ZFSBuilderConfig.nextSlave

        if nextBuild is None:
            nextBuild = ZFSBuilderConfig.nextBuild

        util.BuilderConfig.__init__(self, nextSlave=nextSlave,
                                    nextBuild=nextBuild,
                                    mergeRequests=mergeRequests, **kwargs)

### BUILD SLAVE CLASSES
# Create large EC2 latent build slave
class ZFSEC2Slave(EC2LatentBuildSlave):
    default_user_data = user_data = """#!/bin/bash                                                                                   
set -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

export PATH=%s:$PATH

# Ensure wget is available for runurl
if ! hash wget 2>/dev/null; then
    if hash apt-get 2>/dev/null; then
        apt-get --quiet --yes install wget
    elif hash dnf 2>/dev/null; then
        echo "keepcache=true"     >>/etc/dnf/dnf.conf
        echo "deltarpm=true"      >>/etc/dnf/dnf.conf
        echo "fastestmirror=true" >>/etc/dnf/dnf.conf
        dnf clean all
        dnf --quiet -y install wget
    elif hash yum 2>/dev/null; then
        yum --quiet -y install wget
    else
        echo "Unknown package managed cannot install wget"
    fi
fi

# Run the bootstrap script
export BB_MASTER='%s'
export BB_NAME='%s'
export BB_PASSWORD='%s'
export BB_MODE='%s'
export BB_URL='%s'

# Get the runurl utility.
wget -qO/usr/bin/runurl $BB_URL/runurl
chmod 755 /usr/bin/runurl

runurl $BB_URL/bb-bootstrap.sh
"""

    @staticmethod
    def pass_generator(size=24, chars=string.ascii_uppercase + string.digits):                                         
        return ''.join(random.choice(chars) for _ in range(size))

    def __init__(self, name, password=None, master='', url='', mode="BUILD",
                instance_type="m3.large", identifier=ec2_default_access,
                secret_identifier=ec2_default_secret,
                keypair_name=ec2_default_keypair_name, security_name='ZFSBuilder',
                user_data=None, region="us-west-1", placement='a', max_builds=1,
                build_wait_timeout=30 * 60, spot_instance=False, max_spot_price=0.10,
                price_multiplier=None, missing_timeout=60 * 20, **kwargs):

        self.name = name
        bin_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

        tags = kwargs.get('tags')
        if not tags or tags is None:
            tags={
                "ENV"      : "DEV",
                "Name"     : "ZFSBuilder",
                "ORG"      : "COMP",
                "OWNER"    : "behlendorf1",
                "PLATFORM" : self.name,
                "PROJECT"  : "ZFS",
            }

        if master in (None, ''):
            master = "build.zfsonlinux.org:9989"

        if url in (None, ''):
            url = "https://raw.githubusercontent.com/zfsonlinux/zfs-buildbot/master/scripts/" 

        if password is None:
            password = ZFSEC2Slave.pass_generator()

        if user_data is None:
            user_data = ZFSEC2Slave.default_user_data % (bin_path, master, name, password, mode, url)

        EC2LatentBuildSlave.__init__(
            self, name=name, password=password, instance_type=instance_type, 
            identifier=identifier, secret_identifier=secret_identifier, region=region,
            user_data=user_data, keypair_name=keypair_name, security_name=security_name,
            max_builds=max_builds, spot_instance=spot_instance, tags=tags,
            max_spot_price=max_spot_price, placement=placement,
            price_multiplier=price_multiplier, build_wait_timeout=build_wait_timeout, 
            missing_timeout=missing_timeout, **kwargs)

# Create an HVM EC2 large latent build slave
class ZFSEC2BuildSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, mode="BUILD",
            instance_type="m3.large", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create a PV (paravirtual) EC2 latent build slave
class ZFSEC2PVSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, mode="BUILD",
            instance_type="m1.medium", max_spot_price=0.20, placement='a',
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test slave 
class ZFSEC2TestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m3.large", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create an PV (paravirtual) EC2 latent test slave 
class ZFSEC2PVTestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m1.medium", max_spot_price=0.20, placement='a',
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test slave with x86 vector support (avx2, etc).
class ZFSEC2VectorTestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="d2.xlarge", max_spot_price=0.30, placement='a',
            spot_instance=True, **kwargs)

# Create a d2.xlarge slave for performance testing because they have disks
class ZFSEC2PerfTestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="PERF",
            instance_type="d2.xlarge", max_spot_price=0.30, placement='a',
            spot_instance=True, **kwargs)
