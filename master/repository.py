# -*- python -*-
# ex: set syntax=python:

from password import *

# During testing we may want to test against our own repo (like "tonyhutter")
# rather than "openzfs".  If the user has dev_repo_owner set in passwd.py, then
# use it here
try: dev_repo_owner
except NameError: repo_owner = "openzfs"
else: repo_owner = dev_repo_owner

zfs_repo = "https://github.com/" + repo_owner + "/zfs.git"
linux_repo = "https://github.com/torvalds/linux.git"

all_repositories = {
    "https://github.com/torvalds/linux" : 'linux',
    "https://github.com/openzfs/zfs" : 'zfs',
    "https://github.com/torvalds/linux.git" : 'linux',
    "https://github.com/openzfs/zfs.git" : 'zfs',
    "git://git.hpdd.intel.com/fs/lustre-release" : 'lustre',
    "https://github.com/" + repo_owner + "/zfs" : 'zfs',
    "git://git.hpdd.intel.com/fs/lustre-release.git" : 'lustre',
    "https://github.com/" + repo_owner + "/zfs.git" : 'zfs',
}
