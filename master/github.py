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

            # If Requires-builders contains 'all', then run all builders.
            all_pattern = '.*all.*'
            m = re.search(all_pattern, category, re.I | re.M)
            if m is not None:
                category = "style,build,test,perf,coverage,unstable"

        return category

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

        for commit in payload['commits']:
            if not commit.get('distinct', True):
                log.msg('Commit `%s` is a non-distinct commit, ignoring...' %
                        (commit['id'],))
                continue

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

            # Extract if the commit message has property overrides
            category = self.parse_comments(comments,
                "style,build,test,perf,coverage,unstable")

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

            changes.append(change)

        log.msg("Received %d changes pushed from github" % len(changes))

        return changes, 'git'

    def handle_pull_request(self, payload):
        changes = []
        number = payload['number']
        refname = 'refs/pull/%d/head' % (number,)
        commits_num = payload['pull_request']['commits']
        commits_url = payload['pull_request']['commits_url']
        created_at = dateparse(payload['pull_request']['created_at'])
        commits_cur = 0

        log.msg('Processing GitHub PR #%d' % number, logLevel=logging.DEBUG)

        action = payload.get('action')
        if action not in ('opened', 'reopened', 'synchronize'):
            log.msg("GitHub PR #%d %s, ignoring" % (number, action))
            return changes, 'git'

        commits = query_url(commits_url, token=github_token)

        # Extract any dependency information and translate to a standard form.
        # Requires-spl: refs/pull/PR/head
        spl_pull_request = None
        spl_pattern = '^Requires-spl:\s*([a-zA-Z0-9_\-\:\/\+]+)'
        for commit in commits:
            comments = commit['commit']['message']
            m = re.search(spl_pattern, comments, re.I | re.M)
            if m is not None:
                spl_pull_request = 'Requires-spl: %s' % m.group(1)
                break

        kernel_pull_request = None
        kernel_pattern = '^Requires-kernel:\s*([a-zA-Z0-9_\-\:\/\+\.]+)'
        for commit in commits:
            comments = commit['commit']['message']
            m = re.search(kernel_pattern, comments, re.I | re.M)
            if m is not None:
                kernel_pull_request = 'Requires-kernel: %s' % m.group(1)
                break

        for commit in commits:
            commit = query_url(commit['url'], token=github_token)
            commits_cur += 1
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
                category = "style,build,test,coverage"
            else:
                category = "style,build"

            # Extract if the commit message has property overrides
            category = self.parse_comments(comments, category)

            # Annotate every commit with 'Requires-spl' when missing.
            if spl_pull_request:
                if re.search(spl_pattern, comments, re.I | re.M) is None:
                    comments = comments + spl_pull_request + "\n"

            if kernel_pull_request:
                if re.search(kernel_pattern, comments, re.I | re.M) is None:
                    comments = comments + kernel_pull_request + "\n"

            comments = comments + "Pull-request: #%d part %d/%d\n" % (
                number, commits_cur, commits_num)

            branch = payload['pull_request']['base']['ref']
            props['branch'] = json.dumps(branch)
            props['pr_number'] = json.dumps(number)

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

            changes.append(change)

        log.msg("Received %d changes from GitHub Pull Request #%d" % (
            len(changes), number))

        return changes, 'git'
