#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Exercises bin/compute-next-tag.sh against throwaway git repositories.
#
# Usage: bin/test-compute-next-tag.sh
#
# Every scenario creates a repository in a temporary directory, gives it role
# files and a release history, and then replays a series of merges through the
# real script, tagging as it goes just like the autotag workflow does. This
# repository is never touched and no network access is needed.

set -euo pipefail

script_under_test="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/compute-next-tag.sh"

failures=0
workdir=''

cleanup() {
	cd /
	if [ -n "$workdir" ]; then
		rm -rf "$workdir"
		workdir=''
	fi
}

trap cleanup EXIT

# The defaults file the script has to read the version out of. Everything
# around the variable is there to be picked up by mistake: the Renovate
# annotation sits directly above it, an older value has been left behind
# commented out, another variable's name starts with the one being looked for,
# and the variables that actually get used elsewhere in the role are derived
# from it rather than repeating it. A refactor that made the script read
# `sonarr_container_image_tag` or `sonarr_container_image` instead would still
# look like it worked, until the day one of them stops being a plain
# `{{ sonarr_version }}` - so they carry Jinja here, and the raw sed the script
# uses cannot yield anything usable from them.
write_defaults() {
	cat > defaults/main.yml <<-EOF
		---
		sonarr_identifier: sonarr

		# renovate: datasource=docker depName=ghcr.io/linuxserver/sonarr versioning=semver
		# sonarr_version: 4.0.14
		sonarr_version: $1

		sonarr_version_check_enabled: true
		sonarr_container_image: "{{ sonarr_container_image_registry_prefix }}linuxserver/sonarr:{{ sonarr_container_image_tag }}"
		sonarr_container_image_tag: "{{ sonarr_version }}"
	EOF
}

# Starts a scenario with a repository at Sonarr 4.0.18 which has already seen
# two releases of it (v4.0.18-0 and v4.0.18-1).
scenario() {
	echo "$1"

	cleanup
	workdir="$(mktemp -d)"

	mkdir -p "$workdir/bin" "$workdir/defaults" "$workdir/meta" "$workdir/tasks" "$workdir/templates"
	cp "$script_under_test" "$workdir/bin/"
	cd "$workdir"

	git init -q -b develop .
	git config user.email 'test@example.com'
	git config user.name 'Test'
	git config commit.gpgsign false

	write_defaults 4.0.18
	printf 'placeholder\n' > meta/main.yml
	printf 'placeholder\n' > tasks/main.yml
	printf 'placeholder\n' > templates/env.j2
	printf 'placeholder\n' > README.md

	git add -A
	git commit -qm 'Initial commit'

	local release_number
	for release_number in 0 1; do
		git tag "v4.0.18-$release_number"
	done
}

# Applies a change, commits it, and tags whatever the script says it should be.
# Prints the tag, or nothing when the script decided against a release.
merge() {
	local change="$1" tag

	eval "$change"
	git add -A
	git commit -qm 'Merge'

	tag="$(bin/compute-next-tag.sh 2>/dev/null)"

	if [ -n "$tag" ]; then
		git tag "$tag"
	fi

	printf '%s' "$tag"
}

expect() {
	local description="$1" expected="$2" actual="$3"

	if [ "$actual" = "$expected" ]; then
		printf '  ok   | %s -> %s\n' "$description" "${actual:-no release}"
	else
		printf '  FAIL | %s -> expected %s, got %s\n' "$description" "${expected:-no release}" "${actual:-no release}"
		failures=$((failures + 1))
	fi
}

bump_version='write_defaults 4.0.19'
revert_version='write_defaults 4.0.18'
edit_task="printf 'a task\n' >> tasks/main.yml"
edit_template="printf 'a line\n' >> templates/env.j2"
edit_meta="printf 'a line\n' >> meta/main.yml"
edit_readme="printf 'documentation\n' >> README.md"
edit_script="printf '# a comment\n' >> bin/compute-next-tag.sh"

# The two merge orders below apply the same updates and must each end up with
# every update released exactly once, whichever order they arrive in.

scenario 'A version bump merged before other role changes'
expect 'version bump' v4.0.19-0 "$(merge "$bump_version")"
expect 'task edit'    v4.0.19-1 "$(merge "$edit_task")"
expect 'template'     v4.0.19-2 "$(merge "$edit_template")"

scenario 'A version bump merged after other role changes'
expect 'task edit'    v4.0.18-2 "$(merge "$edit_task")"
expect 'version bump' v4.0.19-0 "$(merge "$bump_version")"

scenario 'Commits that do not affect the role'
expect 'README'   ''        "$(merge "$edit_readme")"
expect 'a script' ''        "$(merge "$edit_script")"
expect 'meta'     v4.0.18-2 "$(merge "$edit_meta")"

scenario 'Release numbers past 9'
for release_number in 2 3 4 5 6 7 8 9 10; do
	git tag "v4.0.18-$release_number"
done
expect 'a task' v4.0.18-11 "$(merge "$edit_task")"

scenario 'Reverting to an already released version'
merge "$bump_version" > /dev/null
# The role is now identical to what v4.0.18-1 already published, so there is
# nothing new to release.
expect 'a revert' ''        "$(merge "$revert_version")"

scenario 'Reverting to an already released version, with a change'
merge "$bump_version" > /dev/null
expect 'a revert' v4.0.18-2 "$(merge "$revert_version && $edit_task")"

# The decoys in defaults/main.yml must never be what gets released. The
# commented-out 4.0.14 and the `sonarr_version_check_enabled` variable sit
# right next to the real one, and a squashed Renovate merge puts a version-like
# string into the commit subject as well - which is exactly what the
# commit-message-driven workflow this replaced used to tag from.
scenario 'Decoys around the version variable'
expect 'a task tagged from the real version' v4.0.18-2 "$(merge "$edit_task")"
git commit -q --allow-empty -m 'Update ghcr.io/linuxserver/sonarr Docker tag to v9.9.9 (#7)'
expect 'an empty commit claiming another version' '' "$(bin/compute-next-tag.sh 2>/dev/null)"

# Sonarr's own versions carry a fourth component (4.0.19.2979), while the
# linuxserver.io tag family the role pins to is three-component. A tag value
# with more components than usual must still round-trip.
scenario 'A four-component version value'
expect 'bump to a four-component version' v4.0.19.2979-0 "$(merge 'write_defaults 4.0.19.2979')"
expect 'a task on top of it'              v4.0.19.2979-1 "$(merge "$edit_task")"

if [ "$failures" -gt 0 ]; then
	echo >&2 "$failures scenario(s) behaved unexpectedly"
	exit 1
fi

echo 'All scenarios behaved as expected'
