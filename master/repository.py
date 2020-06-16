# -*- python -*-
# ex: set syntax=python:

from password import *

# During testing we may want to test against our own repo (like "tonyhutter")
# rather than "openzfs".  If the user has dev_repo_owner set in passwd.py, then
# use it here
try: dev_repo_owner
except NameError: repo_owner = "openzfs"
else: repo_owner = dev_repo_owner

spl_repo = "https://github.com/" + repo_owner + "/spl.git"
zfs_repo = "https://github.com/" + repo_owner + "/zfs.git"
linux_repo = "https://github.com/torvalds/linux.git"
lustre_repo = "git://git.hpdd.intel.com/fs/lustre-release.git"

all_repositories = {
    "https://github.com/torvalds/linux" : 'linux',
    "git://git.hpdd.intel.com/fs/lustre-release" : 'lustre',
    "https://github.com/" + repo_owner + "/spl" : 'spl',
    "https://github.com/" + repo_owner + "/zfs" : 'zfs',
    "https://github.com/torvalds/linux.git" : 'linux',
    "git://git.hpdd.intel.com/fs/lustre-release.git" : 'lustre',
    "https://github.com/" + repo_owner + "/spl.git" : 'spl',
    "https://github.com/" + repo_owner + "/zfs.git" : 'zfs',
}
