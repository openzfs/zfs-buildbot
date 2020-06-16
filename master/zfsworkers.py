# -*- python -*-
# ex: set syntax=python:

import string
import random
import re
import base64
from password import *
from buildbot.plugins import util
from buildbot.worker import Worker
from buildbot.worker.ec2 import EC2LatentWorker

from twisted.python import log

bb_master = "build.zfsonlinux.org:9989"

region_placement = 'a'

# If you specify dev_tag_name in password.py, we will use it instead of the
# default tag_name.  This is useful during development.  For example, you
# may want all your builders to show up in EC2 as "ZFSBuilder-dev" during
# development.
try: dev_tag_name
except NameError: tag_name = "ZFSBuilder"
else: tag_name = dev_tag_name

# If you specify dev_bb_master in password.py, we will use it instead of the
# default bb_master.  This is useful during development.
try: dev_bb_master
except NameError: bb_master = bb_master
else: bb_master = dev_bb_master

# If you specify dev_tag_name in password.py, we will use it instead of the
# default tag_name.  This is useful during development.
try: dev_tag_name
except NameError: tag_name = tag_name
else: tag_name = dev_tag_name

# If you specify dev_region_placement in password.py, we will use it instead of
# the default region_placement.  This is useful during development.
try: dev_region_placement
except NameError: region_placement = region_placement
else: region_placement = dev_region_placement

### BUILDER CLASSES
class ZFSBuilderConfig(util.BuilderConfig):
    @staticmethod
    def nextWorker(builder, workers, buildrequest):
        availableWorker = None

        for worker in workers:
            # hold onto the first worker thats not spun up but free
            if availableWorker is None and worker.isAvailable():
                availableWorker = worker

        # we got here because there was no idle worker
        if availableWorker is not None:
            return availableWorker

        # randomly choose among all our busy workers
        return (random.choice(workers) if workers else None)

    # builders should prioritize a merge into master or the final commit
    # from a pull request before building other commits. This avoids
    # starving smaller pull requests from getting feedback.
    @staticmethod
    def nextBuild(builder, requests):
        pattern = '^Pull-request:\s*#\d+\s*part\s*(?P<part>\d+)/(?P<total>\d+)$'

        # go thru each request's changes to prioritize them
        for request in requests:
            for source in request.sources:
                ss = request.sources[source]
                for change in ss.changes:
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

    def __init__(self, collapseRequests=False, nextWorker=None, nextBuild=None, **kwargs):
        if nextWorker is None:
            nextWorker = ZFSBuilderConfig.nextWorker

        if nextBuild is None:
            nextBuild = ZFSBuilderConfig.nextBuild

        util.BuilderConfig.__init__(self, nextWorker=nextWorker,
                                    nextBuild=nextBuild,
                                    collapseRequests=collapseRequests, **kwargs)

### BUILD SLAVE CLASSES
# Create large EC2 latent build worker
class ZFSEC2Worker(EC2LatentWorker):
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
                user_data=None, region="us-west-1", placement=region_placement, max_builds=1,
                build_wait_timeout=60, spot_instance=False, max_spot_price=0.10,
                price_multiplier=None, missing_timeout=3600*12,
                block_device_map=None, get_image=None, **kwargs):

        print("Begin ZFSEC2Worker for ", name)
        self.name = name
        bin_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

        tags = kwargs.get('tags')

        if not tags or tags is None:
            tags={
                "ENV"      : "DEV",
                "Name"     : tag_name,
                "ORG"      : "COMP",
                "OWNER"    : "behlendorf1",
                "PLATFORM" : self.name,
                "PROJECT"  : "ZFS",
            }

        if master in (None, ''):
            master = bb_master

        if url in (None, ''):
            url = "https://raw.githubusercontent.com/openzfs/zfs-buildbot/master/scripts/"
            # Use dev_bb_url if specificed for the url (it can be set i/n
            # password.py during development only).
            try: dev_bb_url
            except NameError: url = url
            else: url = dev_bb_url


        if password is None:
            password = ZFSEC2Worker.pass_generator()

        if user_data is None:
            user_data = ZFSEC2Worker.default_user_data % (bin_path, master, name, password, mode, url)

            # Spot instances need user data to be base64 encoded?
            # https://github.com/buildbot/buildbot/issues/3742
            user_data = base64.b64encode(user_data.encode("ascii")).decode('ascii')

        if block_device_map is None:
            # io1 is 50 IOPS/GB, iops _must_ be specified for io1 only
            # Cf. https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSVolumeTypes.html
            boot_device_props = { "VolumeType": "gp2", "VolumeSize": 24 }

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

            block_device_map = [
                    {"DeviceName": boot_device, "Ebs": boot_device_props},
                    {"DeviceName": "/dev/sdb", "VirtualName": "ephemeral0" },
                    {"DeviceName": "/dev/sdc", "VirtualName": "ephemeral1" },
                    {"DeviceName": "/dev/sdd", "VirtualName": "ephemeral2" },
                    {"DeviceName": "/dev/sde", "VirtualName": "ephemeral3" },
                    {"DeviceName": "/dev/sdf", "VirtualName": "ephemeral4" },
                    {"DeviceName": "/dev/sdg", "VirtualName": "ephemeral5" },
                    ]

        # get_image can be used to determine an AMI when the worker starts.
        if callable(get_image):
            # Trick EC2LatentWorker input validation by providing a "valid" regex.
            # This won't actually be used because we override get_image().
            kwargs['valid_ami_location_regex'] = ''
            # If we just set `self.get_image = get_image` then self doesn't get passed.
            self.get_image = lambda: get_image(self)

        EC2LatentWorker.__init__(
            self, name=name, password=password, instance_type=instance_type,
            identifier=identifier, secret_identifier=secret_identifier, region=region,
            user_data=user_data, keypair_name=keypair_name, security_name=security_name,
            subnet_id=subnet_id, security_group_ids=security_group_ids,
            max_builds=max_builds, spot_instance=spot_instance, tags=tags,
            max_spot_price=max_spot_price, price_multiplier=price_multiplier,
            build_wait_timeout=build_wait_timeout, missing_timeout=missing_timeout,
            placement=placement, block_device_map=block_device_map, **kwargs)

class ZFSEC2StyleWorker(ZFSEC2Worker):
    def __init__(self, name, **kwargs):
        ZFSEC2Worker.__init__(self, name, mode="STYLE",
            instance_type="m5d.large", max_spot_price=0.10, placement=region_placement,
            spot_instance=True, **kwargs)

# Create an HVM EC2 large latent build worker
class ZFSEC2BuildWorker(ZFSEC2Worker):
    def __init__(self, name, arch="amd64", **kwargs):
        instance_types = {
            "amd64": "c5d.large",
            "arm64": "c6g.large"
        }
        assert arch in instance_types
        ZFSEC2Worker.__init__(self, name, mode="BUILD",
            instance_type=instance_types.get(arch), max_spot_price=0.10, placement=region_placement,
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test worker
class ZFSEC2TestWorker(ZFSEC2Worker):
    def __init__(self, name, **kwargs):
        ZFSEC2Worker.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m5d.large", max_spot_price=0.10, placement=region_placement,
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test worker
# AMI does not support an Elastic Network Adapter (ENA)
class ZFSEC2ENATestWorker(ZFSEC2Worker):
    def __init__(self, name, **kwargs):
        ZFSEC2Worker.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m3.large", max_spot_price=0.10, placement=region_placement,
            spot_instance=True, **kwargs)

# Create an HVM EC2 latent test worker
class ZFSEC2CoverageWorker(ZFSEC2Worker):
    def __init__(self, name, **kwargs):
        ZFSEC2Worker.__init__(self, name, build_wait_timeout=1, mode="TEST",
            instance_type="m3.xlarge", max_spot_price=0.10, placement=region_placement,
            spot_instance=True, **kwargs)

# Create a d2.xlarge worker for performance testing because they have disks
class ZFSEC2PerfTestWorker(ZFSEC2Worker):
    def __init__(self, name, **kwargs):
        ZFSEC2Worker.__init__(self, name, build_wait_timeout=1, mode="PERF",
            instance_type="d2.xlarge", max_spot_price=0.60, placement=region_placement,
            spot_instance=True, **kwargs)
