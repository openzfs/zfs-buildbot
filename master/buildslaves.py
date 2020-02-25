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
    default_user_data = user_data = """#!/bin/sh -x
# Make /dev/console the serial console instead of the video console
# so we get our output in the text system log at boot.
case "$(uname)" in
FreeBSD)
    # On FreeBSD the first enabled console becomes /dev/console
    # ttyv0,ttyu0,gdb -> ttyu0,ttyv0,gdb
    conscontrol delete ttyu0
    conscontrol add ttyu0
    ;;
*)
    ;;
esac

# Duplicate all output to a log file, syslog, and the console.
{
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
        elif hash pkg 2>/dev/null; then
            echo IGNORE_OSVERSION=yes >>/usr/local/etc/pkg.conf
            pkg install --quiet -y wget
        elif hash yum 2>/dev/null; then
            yum --quiet -y install wget
        else
            echo "Unknown package manager, cannot install wget"
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
} 2>&1 | tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console
"""

    @staticmethod
    def pass_generator(size=24, chars=string.ascii_uppercase + string.digits):                                         
        return ''.join(random.choice(chars) for _ in range(size))

    def __init__(self, name, password=None, master='', url='', mode="BUILD",
                instance_type="c5d.large", identifier=ec2_default_access,
                secret_identifier=ec2_default_secret,
                keypair_name=ec2_default_keypair_name, security_name='ZFSBuilder',
                subnet_id=None, security_group_ids=None,
                user_data=None, region="us-west-1", placement='a', max_builds=1,
                build_wait_timeout=60, spot_instance=False, max_spot_price=0.10,
                price_multiplier=None, missing_timeout=60 * 40,
                block_device_map=None, get_image=None, **kwargs):

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
            url = "https://raw.githubusercontent.com/openzfs/zfs-buildbot/master/scripts/"

        if password is None:
            password = ZFSEC2Slave.pass_generator()

        if user_data is None:
            user_data = ZFSEC2Slave.default_user_data % (bin_path, master, name, password, mode, url)

        if block_device_map is None:
            # io1 is 50 IOPS/GB, iops _must_ be specified for io1 only
            # Cf. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html
            boot_device_props = { "volume_type": "gp2", "size": 24 }

            # Reasonable default values for additional persistent disks, if desired
            persist_device_props = { "volume_type": "io1",
                                   "iops": 400,
                                   "size": 8
                                   }

            # The boot device name must exactly match the name in the
            # distribution provided AMI otherwise it will fail to boot.
            if "Amazon" in name or "Kernel.org" in name or "Debian" in name:
                boot_device = "/dev/xvda"
            else:
                boot_device = "/dev/sda1"

            block_device_map = { boot_device : boot_device_props,
                                 "/dev/sdb": { "ephemeral_name": "ephemeral0" },
                                 "/dev/sdc": { "ephemeral_name": "ephemeral1" },
                                 "/dev/sdd": { "ephemeral_name": "ephemeral2" },
                                 "/dev/sde": { "ephemeral_name": "ephemeral3" },
                                 "/dev/sdf": { "ephemeral_name": "ephemeral4" },
                                 "/dev/sdg": { "ephemeral_name": "ephemeral5" },
                               }

        # get_image can be used to determine an AMI when the slave starts.
        if callable(get_image):
            # Trick EC2LatentBuildSlave input validation by providing a "valid" regex.
            # This won't actually be used because we override get_image().
            kwargs['valid_ami_location_regex'] = ''
            # If we just set `self.get_image = get_image` then self doesn't get passed.
            self.get_image = lambda: get_image(self)

        EC2LatentBuildSlave.__init__(
            self, name=name, password=password, instance_type=instance_type, 
            identifier=identifier, secret_identifier=secret_identifier, region=region,
            user_data=user_data, keypair_name=keypair_name, security_name=security_name,
            subnet_id=subnet_id, security_group_ids=security_group_ids,
            max_builds=max_builds, spot_instance=spot_instance, tags=tags,
            max_spot_price=max_spot_price, price_multiplier=price_multiplier,
            build_wait_timeout=build_wait_timeout, missing_timeout=missing_timeout,
            placement=placement, block_device_map=block_device_map, **kwargs)

class ZFSEC2StyleSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, mode="STYLE",
            instance_type="c5d.large", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create an HVM EC2 large latent build slave
class ZFSEC2BuildSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, mode="BUILD",
            instance_type="c5d.large", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test slave
class ZFSEC2TestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m5d.large", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test slave
# AMI does not support an Elastic Network Adapter (ENA)
class ZFSEC2ENATestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m3.large", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test slave
class ZFSEC2CoverageSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m3.xlarge", max_spot_price=0.10, placement='a',
            spot_instance=True, **kwargs)

# Create a d2.xlarge slave for performance testing because they have disks
class ZFSEC2PerfTestSlave(ZFSEC2Slave):
    def __init__(self, name, **kwargs):
        ZFSEC2Slave.__init__(self, name, build_wait_timeout=1, mode="PERF",
            instance_type="d2.xlarge", max_spot_price=0.60, placement='a',
            spot_instance=True, **kwargs)
