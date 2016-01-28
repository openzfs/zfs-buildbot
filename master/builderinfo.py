# -*- python -*-
# ex: set syntax=python:

import string
import random
import re
from abc import ABCMeta, abstractmethod
from buildbot.plugins import util
from buildbot.buildslave import BuildSlave
from buildbot.buildslave.ec2 import EC2LatentBuildSlave

# The 'slaves' are logically split in to 'build slaves' and 'test slaves'.
#
# Build slaves:
# - May NOT modify the configuration of the system by installing packages
#   (other than required dependencies) or modifying configuration files.
# - May NOT save build products outside the default build area:
#   /var/lib/buildbot/slaves/zfs/BUILDER/build/.
# - May NOT always be destroyed and recreated between builds.
#
# Test slaves:
# - May ALWAYS modify the configuration of the system by installing packages
#   and modifying configuration files.
# - Will ALWAYS be destroyed and recreated from an AMI between builds.

# Abstract class
class BuildSlaveInfo(object):
    """
    Class to maintain information about BuildBot slaves.
    """
    __metaclass__ = ABCMeta

    def __init__(self, name, password, **kwargs):
        """Initializes a new BuildSlaveInfo object.

        Args:
            name (str): Internal name of the BuildBot slave.
            password (str): Password used to access the slave.
        """
        self.name = name
        self.password = password

    def getName(self):
        return self.name

    @staticmethod
    def id_generator(size=24, chars=string.ascii_uppercase + string.digits):
        return ''.join(random.choice(chars) for _ in range(size))

    @abstractmethod
    def makeBuildSlave(self, **kwargs):
        """Returns a build slave created based on the info in this object"""
        pass

# Create a standard persistent long running build slave.
class PersistSlaveInfo(BuildSlaveInfo):
    def makeBuildSlave(self, **kwargs):
        return BuildSlave(self.name, self.password, **kwargs)

# Create an EC2 latent build slave.
class EC2SlaveInfo(BuildSlaveInfo):
    def __init__(self, name, mode, master, ami, url, 
            ec2_access, ec2_secret, ec2_keypair, **kwargs):
        super(EC2SlaveInfo, self).__init__(name, BuildSlaveInfo.id_generator(), **kwargs)
        self.master = master
        self.ami = ami
        self.url = url
        self.mode = mode 
        self.ec2_access=ec2_access
        self.ec2_secret=ec2_secret
        self.ec2_keypair=ec2_keypair

    # An EC2LatentBuildSlave that uses a user-data script for bootstrapping itself.
    def makeBuildSlave(self, **kwargs):
        instance_type="t2.micro"
        region="us-west-2"
        placement="c"
        spot_instance=False
        max_spot_price=0.08
        price_multiplier=1.25
        keepalive_interval=3600
        security_name="ZFSBuilder"
        password = self.password
        bin_path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        user_data = """#!/bin/bash
set -e
set -x
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

export PATH=""" + bin_path + """:$PATH

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

# Get the runurl utility.
wget -qO/usr/bin/runurl """ + self.url + """runurl
chmod 755 /usr/bin/runurl

# Run the bootstrap script
export BB_MASTER='""" + self.master + """'
export BB_NAME='""" + self.name + """'
export BB_PASSWORD='""" + self.password + """'
export BB_MODE='""" + self.mode + """'
runurl """ + self.url + """bb-bootstrap.sh
"""

        for key in kwargs:
            if key=="instance_type":
                instance_type=kwargs[key]
            if key=="build_wait_timeout":
                build_wait_timeout=kwargs[key]
            if key=="spot_instance":
                spot_instance=kwargs[key]
            if key=="max_spot_price":
                max_spot_price=kwargs[key]
            if key=="price_multiplier":
                price_multiplier=kwargs[key]
            if key=="placement":
                placement=kwargs[key]

        return EC2LatentBuildSlave(
            self.name, self.password, instance_type, ami=self.ami,
            valid_ami_owners=None, valid_ami_location_regex=None, elastic_ip=None,
            identifier=self.ec2_access, secret_identifier=self.ec2_secret,
            aws_id_file_path=None, user_data=user_data, region=region,
            keypair_name=self.ec2_keypair, security_name=security_name,
            max_builds=1, notify_on_missing=[], missing_timeout=60 * 20,
            build_wait_timeout=build_wait_timeout, properties={}, locks=None,
            spot_instance=spot_instance, max_spot_price=max_spot_price, volumes=[],
            placement=placement, price_multiplier=price_multiplier,
            tags={
                "ENV"      : "DEV",
                "Name"     : "ZFSBuilder",
                "ORG"      : "COMP",
                "OWNER"    : "behlendorf1",
                "PLATFORM" : self.name,
                "PROJECT"  : "ZFS",
            })

# Create a large EC2 latent build slave.
class EC2LargeSlaveInfo(EC2SlaveInfo):
    def makeBuildSlave(self, **kwargs):
        return super(EC2LargeSlaveInfo, self).makeBuildSlave(
            build_wait_timeout=30 * 60, instance_type="m4.xlarge",
            spot_instance=True, max_spot_price=0.08,
            price_multiplier=1.25, **kwargs)

# Create an EC2 latent test slave.
class EC2TestSlaveInfo(EC2LargeSlaveInfo):
    def makeBuildSlave(self, **kwargs):
        return super(EC2TestSlaveInfo, self).makeBuildSlave(
            keepalive_interval=60, **kwargs)

# Builder info which will help us keep track of our slaves
class BuilderInfo(object):
    """
    Class to maintain information regarding BuildBot builders.
    """

    def __init__(self, name, factory, slaves, **kwargs):
        """Initializes a new BuilderInfo object.

        Args:
            name (str): name of the builder
            factory (BuildFactory): factory containing steps each slave should follow
            slaves (list of BuildSlaveInfo): list of slaves assigned to builder
            tags (List[str]): Tags to be applied when slave is configured.
            properties(List[str]): Properties to be applied when slave is configured.
        """

        self.name = name
        self.slaves = slaves
        self.factory = factory
        self.tags = []
        self.properties = []

        for key in kwargs:
            if key=="tags":
                self.tags=kwargs[key]
            if key=="properties":
                self.properties=kwargs[key]

    def getName(self):
        return self.name

    def addSlave(self, slave):
        self.slaves.append(slave)

    def getSlaveNames(self):
        return [info.getName() for info in self.slaves]

    def getSlaves(self):
        return self.slaves

    def makeSlaves(self):
        return [info.makeBuildSlave() for info in self.slaves]

    def getBuilderConfig(self):
        """Returns the configuration for the builder."""
        return util.BuilderConfig(
                    name=self.name, slavenames=self.getSlaveNames(),
                    factory=self.factory, properties=self.properties, 
                    tags=self.tags, mergeRequests=False)

