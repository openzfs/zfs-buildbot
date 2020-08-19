# -*- python -*-
# ex: set syntax=python:

import logging
import urllib2
import json
import string
import re

from password import *
from buildbot.status.web.hooks.github import GitHubEventHandler
from dateutil.parser import parse as dateparse
from twisted.python import log

builders_common="arch,style,coverage,"
builders_linux="amazon2,centos7,centos8,debian10,fedora32,ubuntu18,ubuntu20,builtin,"
builders_freebsd="freebsd12,freebsd13,"

builders_push_master=builders_common+builders_linux+builders_freebsd
builders_push_release=builders_common+builders_linux+"centos6"

builders_pr_master=builders_common+builders_linux+builders_freebsd
builders_pr_release=builders_common+builders_linux+"centos6"

# Default builders for non-top PR commits
builders_pr_minimum="arch,style"

def query_url(url, token=None):
    log.msg("Making request to '%s'" % url)
    request = urllib2.Request(url)
    if token:
        request.add_header("Authorization", "token %s" % token)
    response = urllib2.urlopen(request)

    return json.loads(response.read())

#
# Custom class to determine how to handle incoming Github changes.
#
class CustomGitHubEventHandler(GitHubEventHandler):
    valid_props = [
        ('^Build[-\s]linux:\s*(yes|no)\s*$', 'override-buildlinux'),
        ('^Build[-\s]lustre:\s*(yes|no)\s*$', 'override-buildlustre'),
        ('^Build[-\s]spl:\s*(yes|no)\s*$', 'override-buildspl'),
        ('^Build[-\s]zfs:\s*(yes|no)\s*$', 'override-buildzfs'),
        ('^Built[-\s]in:\s*(yes|no)\s*$', 'override-builtin'),
        ('^Check[-\s]lint:\s*(yes|no)\s*$', 'override-checklint'),
        ('^Configure[-|\s]lustre:(.*)$', 'override-configlustre'),
        ('^Configure[-|\s]spl:(.*)$', 'override-configspl'),
        ('^Configure[-|\s]zfs:(.*)$', 'override-configzfs'),
        ('^Perf[-|\s]zts:\s*(yes|no)\s*$', 'override-perfzts'),
        ('^Perf[-|\s]pts:\s*(yes|no)\s*$', 'override-perfpts'),
    ]

    def parse_comments(self, comments, default_category):
        category = default_category

        # Extract any overrides for builders for this commit
        # Requires-builders: style build arch distro test perf none
        category_pattern = '^Requires-builders:\s*([ ,a-zA-Z0-9]+)'
        m = re.search(category_pattern, comments, re.I | re.M)
        if m is not None:
            category = m.group(1).lower();

            # If Requires-builders contains 'none', then skip this commit
            none_pattern = '.*none.*'
            m = re.search(none_pattern, category, re.I | re.M)
            if m is not None:
                category = ""

        return category

    def handle_push_commit(self, payload, commit, branch):
        created_at = dateparse(commit['timestamp'])
        comments = commit['message']

        # Assemble the list of modified files.
        files = []
        for kind in ('added', 'modified', 'removed'):
            files.extend(commit.get(kind, []))

        # Extract if the commit message has property overrides
        props = { }
        for prop in CustomGitHubEventHandler.valid_props:
            step_pattern = prop[0]
            m = re.search(step_pattern, comments, re.I | re.M)
            if m is not None:
                prop_name = prop[1]
                props[prop_name] = json.dumps(m.group(1).lower())

        match = re.match("master", branch)
        if match:
            category = self.parse_comments(comments, builders_push_master)
        else:
            # Don't run the zimport on release or staging branches
            comments + "\nTEST_ZIMPORT_SKIP=\"yes\""

            # Extract if the commit message has property overrides
            # For 0.8 and earlier releases include the legacy builders.
            category = self.parse_comments(comments, builders_push_release)

        props['branch'] = branch

        # Releases prior to 0.8.0 required an external spl build.
        match = re.match(r".*-0.[0-7]-release", branch)
        if not match:
            props['buildspl'] = json.dumps("no")
        else:
            props['buildspl'] = json.dumps("yes")

        # Enabled performance testing on pushes by default.
        props['perfpts'] = json.dumps("yes")
        props['perfzts'] = json.dumps("yes")

        change = {
            'revision' : commit['id'],
            'when_timestamp': created_at,
            'branch': branch,
            'revlink' : commit['url'],
            'repository': payload['repository']['url'],
            'project' : payload['repository']['full_name'],
            'properties' : props,
            'category': category,
            'author': "%s <%s>" % (commit['author']['name'],
                                   commit['author']['email']),
            'comments' : comments,
            'files' : files,
        }

        if callable(self._codebase):
            change['codebase'] = self._codebase(payload)
        elif self._codebase is not None:
            change['codebase'] = self._codebase

        return change

    def handle_push(self, payload):
        changes = []
        refname = payload['ref']

        log.msg("Processing GitHub Push `%s'" % refname)

        # We only care about regular heads, i.e. branches
        match = re.match(r"^refs\/heads\/(.+)$", refname)
        if not match:
            log.msg("Ignoring refname `%s': Not a branch" % refname)
            return changes, 'git'

        branch = match.group(1)
        if payload.get('deleted'):
            log.msg("Branch `%s' deleted, ignoring" % branch)
            return changes, 'git'

        nr = 0
        for commit in payload['commits']:
            nr += 1

            if not commit.get('distinct', True):
                log.msg('Commit `%s` is a non-distinct commit, ignoring...' %
                    (commit['id'],))
                continue

            if nr > 10:
                log.msg('Commit `%s` exceeds push limit (%d > 5), ignoring...' %
                    (commit['id'], nr))
                continue

            change = self.handle_push_commit(payload, commit, branch)
            changes.append(change)

        log.msg("Received %d changes pushed from github" % len(changes))

        return changes, 'git'

    def handle_pull_request_commit(self, payload, commit, nr, commits_nr,
                                   spl_pr, kernel_pr):

        pr_number = payload['number']
        refname = 'refs/pull/%d/head' % (pr_number,)
        created_at = dateparse(payload['pull_request']['created_at'])
        branch = payload['pull_request']['base']['ref']
        comments = commit['commit']['message'] + "\n\n"

        # Assemble the list of modified files.
        changed_files = []
        for f in commit['files']:
            changed_files.append(f['filename'])

        # Extract if the commit message has property overrides
        props = { }
        for prop in CustomGitHubEventHandler.valid_props:
            step_pattern = prop[0]
            m = re.search(step_pattern, comments, re.I | re.M)
            if m is not None:
                prop_name = prop[1]
                props[prop_name] = json.dumps(m.group(1).lower())

        # Annotate the head commit to allow special handling.
        if commit['sha'] == payload['pull_request']['head']['sha']:
            # For 0.8 and earlier releases include the legacy builders.
            match = re.match("master", branch)
            if match:
                category = builders_pr_master
            else:
                category = builders_pr_release

        else:
            category = builders_pr_minimum

        # Extract if the commit message has property overrides
        category = self.parse_comments(comments, category)

        # Annotate every commit with 'Requires-spl' when missing.
        if spl_pr:
            if re.search(spl_pattern, comments, re.I | re.M) is None:
                comments = comments + spl_pr + "\n"

        if kernel_pr:
            if re.search(kernel_pattern, comments, re.I | re.M) is None:
                comments = comments + kernel_pr + "\n"

        comments = comments + "Pull-request: #%d part %d/%d\n" % (
            pr_number, nr, commits_nr)

        props['branch'] = json.dumps(branch)
        props['pr_number'] = json.dumps(pr_number)

        # Releases prior to 0.8.0 required an external spl build.
        match = re.match(r".*-0.[0-7]-release", branch)
        if not match:
            props['buildspl'] = json.dumps("no")
        else:
            props['buildspl'] = json.dumps("yes")

        # Disabled performance testing on PRs by default.
        props['perfpts'] = json.dumps("no")
        props['perfzts'] = json.dumps("no")

        change = {
            'revision' : commit['sha'],
            'when_timestamp': created_at,
            'branch': refname,
            'revlink' : commit['html_url'],
            'repository': payload['repository']['clone_url'],
            'project' : payload['repository']['name'],
            'properties' : props,
            'category': category,
            'author': "%s <%s>" % (commit['commit']['committer']['name'],
                                   commit['commit']['committer']['email']),
            'comments' : comments,
            'files' : changed_files,
        }

        if callable(self._codebase):
            change['codebase'] = self._codebase(payload)
        elif self._codebase is not None:
            change['codebase'] = self._codebase

        return change

    def handle_pull_request(self, payload):
        changes = []
        pr_number = payload['number']
        commits_nr = payload['pull_request']['commits']

        log.msg('Processing GitHub PR #%d' % pr_number, logLevel=logging.DEBUG)

        action = payload.get('action')
        if action not in ('opened', 'reopened', 'synchronize'):
            log.msg("GitHub PR #%d %s, ignoring" % (pr_number, action))
            return changes, 'git'

        # When receiving a large PR only test the top commit.
        if commits_nr > 5:
            commit_url = payload['pull_request']['base']['repo']['commits_url'][:-6]
            commit_url += "/" + payload['pull_request']['head']['sha']
            commit = query_url(commit_url, token=github_token)
            change = self.handle_pull_request_commit(payload, commit,
                commits_nr, commits_nr, None, None)
            changes.append(change)
        # Compile all commits in the stack and test the top commit.
        else:
            commits_url = payload['pull_request']['commits_url']
            commits = query_url(commits_url, token=github_token)

            # Extract any dependency information.
            # Requires-spl: refs/pull/PR/head
            spl_pr = None
            spl_pattern = '^Requires-spl:\s*([a-zA-Z0-9_\-\:\/\+]+)'
            for commit in commits:
                comments = commit['commit']['message']
                m = re.search(spl_pattern, comments, re.I | re.M)
                if m is not None:
                    spl_pr = 'Requires-spl: %s' % m.group(1)
                    break

            kernel_pr = None
            kernel_pattern = '^Requires-kernel:\s*([a-zA-Z0-9_\-\:\/\+\.]+)'
            for commit in commits:
                comments = commit['commit']['message']
                m = re.search(kernel_pattern, comments, re.I | re.M)
                if m is not None:
                    kernel_pr = 'Requires-kernel: %s' % m.group(1)
                    break

            nr = 0
            for commit in commits:
                nr += 1
                commit = query_url(commit['url'], token=github_token)
                change = self.handle_pull_request_commit(payload, commit,
                    nr, commits_nr, spl_pr, kernel_pr)
                changes.append(change)

        log.msg("Received %d changes from GitHub Pull Request #%d" % (
            len(changes), pr_number))

        return changes, 'git'
