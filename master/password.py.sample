# -*- python -*-
# ex: set syntax=python:

# Build slaves configured with mkBuildSlave() must have a name and password
# entry.  The names must match the names in mkBuildSlave() and the passwords
# should be distributed to the static builders for authentication.
slave_userpass = [
    ("slave1", "password1"),
    ("slave2", "password2"),
]

# Web users are authenticated using a basic login and password.  From the
# web interface pending builds may be canceled or resubmitted.
web_userpass = [
    ("user1", "password1"),
    ("user2", "password2"),
]

# Buildbot allows for requests to be submitted using the 'buildbot try'
# command.  This interface is mainly useful for injecting builds when
# working on the buildbot infrastructure itself.  The vast majority of
# build requested should be submitted via pull requests.
try_userpass = [
    ("user1", "password1"),
    ("user2", "password2"),
]

# Amazon ec2 credentials which are needed to create latent build slaves.
ec2_default_access = "access"
ec2_default_secret = "secret"

# An Amazon ec2 key pair which should be installed for the default login
# to enable access to the instance.  This is optional.
ec2_default_keypair_name = "buildbot"

# Github credentials, these allow for an increased number of API calls
# to be made without throttling and for status updates to be pushed for
# pull requests.
github_secret = "secret"
github_token = "token"
