#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Prints the tag that the currently checked out commit should be released as,
# or nothing at all if it does not warrant a release.
#
# Usage: bin/compute-next-tag.sh
#
# Tags look like `v<Sonarr version>-<release>`:
#
# - if defaults/main.yml points at a Sonarr version that has never been
#   released, the release counter restarts at 0 (`v4.0.19-0`)
# - otherwise the counter is incremented (`v4.0.19-1`), but only if something
#   that actually affects the role has changed since the last release
#
# Determining the version from defaults/main.yml, rather than from the commit
# message of the pull request that got merged, makes the result independent of
# the order in which pull requests get merged, and lets any change to the role
# (bugfix, feature, dependency bump) release itself without a human tagging.
#
# It also avoids the failure modes of the previous, commit-message-driven
# workflow this replaced, which scanned the last 20 commits for a
# `renovate[bot]` subject containing "docker tag to " and "sonarr":
#
# - a squashed Renovate pull request appends its number to the subject, so
#   "Update ghcr.io/linuxserver/sonarr Docker tag to v4.0.19 (#7)" yielded the
#   tag name `v4.0.19 (#7)-0`, which git refuses outright
# - a hand-written version bump was never released at all, because no commit
#   by `renovate[bot]` matched
# - once more than 20 commits had piled up on top of a bump, the bump became
#   invisible and its release was lost for good

set -euo pipefail

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repository_path"

defaults_path='defaults/main.yml'

# Paths that shape the behavior of the role for its consumers. A commit
# touching only other paths (a README fix, CI configuration, Molecule tests)
# does not change what a playbook run does, and releasing it would only create
# churn in the repositories that consume this role.
role_defining_paths=(
	'defaults'
	'meta'
	'tasks'
	'templates'
)

# Anchored at the start of the line, so that neither the `# renovate:`
# annotation directly above the variable, nor a commented-out older value, nor
# any of the variables derived from it (`sonarr_container_image_tag`) can be
# picked up instead.
version="$(sed -nE 's|^sonarr_version:[[:space:]]*"?([^"[:space:]]+)"?.*$|\1|p' "$defaults_path" | head -n1)"

if [ -z "$version" ]; then
	echo >&2 "Could not determine the Sonarr version from $defaults_path"
	exit 1
fi

# The version value carries no leading `v` (e.g. `4.0.19`), while the tags
# always have had one. The stripping keeps this correct either way.
tag_prefix="v${version#v}-"

# Of all releases of this version, the highest release number. Sorted
# numerically, so that -10 is recognized as newer than -9.
last_release="$(git tag --list "${tag_prefix}*" | sed -e "s|^${tag_prefix}||" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"

if [ -z "$last_release" ]; then
	echo >&2 "Version $version has never been released"
	echo "${tag_prefix}0"
	exit 0
fi

previous_tag="${tag_prefix}${last_release}"

if git diff --quiet "$previous_tag" HEAD -- "${role_defining_paths[@]}"; then
	echo >&2 "Nothing affecting the role has changed since $previous_tag"
	exit 0
fi

echo >&2 "The role has changed since $previous_tag"
echo "${tag_prefix}$((last_release + 1))"
