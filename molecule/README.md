<!--
SPDX-FileCopyrightText: 2018-2025 Slavi Pantaleev
SPDX-FileCopyrightText: 2019-2022 Aaron Raimist
SPDX-FileCopyrightText: 2019-2023 MDAD project contributors
SPDX-FileCopyrightText: 2023 QEDeD
SPDX-FileCopyrightText: 2024 Fabio Bonelli
SPDX-FileCopyrightText: 2024 Nikita Chernyi
SPDX-FileCopyrightText: 2024-2026 Suguru Hirahara
SPDX-FileCopyrightText: 2026 spatterlight

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Molecule Testing

This role supports [Molecule](https://docs.ansible.com/projects/molecule/), an Ansible testing framework designed for developing and testing Ansible collections, playbooks, and roles.

## Prerequisites

To utilize Molecule you need to prepare several requirements:

- **x86** computer running one of these operating systems that make use of [systemd](https://systemd.io/):
  - **Archlinux**
  - **CentOS**, **Rocky Linux**, **AlmaLinux**, or possibly other RHEL alternatives (although your mileage may vary)
  - **Debian** (10/Buster or newer)
  - **Ubuntu** (18.04 or newer, although [20.04 may be problematic](https://github.com/mother-of-all-self-hosting/mash-playbook/blob/main/docs/ansible.md#supported-ansible-versions) if you run the Ansible playbook on it)
- `root` access on the computer which Molecule runs against
- [Ansible](http://ansible.com/) program
- [Python](https://www.python.org/)
  - Most distributions install Python by default, but some don't (e.g. Ubuntu 18.04) and require manual installation (something like `apt-get install python3`)
- [Docker](https://www.docker.com)
  - Access to Docker UNIX socket (`/var/run/docker.sock`) is required by default

## Installation

To set up the environment for using Molecule, run the command below on the terminal:

```bash
python3 -m venv ./molecule/venv
source ./molecule/venv/bin/activate
pip3 install -r ./molecule/requirements.txt
```

## Scenarios

Currently there is one testing scenario available.

### `default`

Tests a standard Sonarr installation.

The scenario deliberately runs Sonarr away from every value it would fall back to on its own, so that anything the role failed to pass through shows up as a failure rather than as a coincidence:

- a uid/gid that is neither `root` nor the `1000` the linuxserver.io image assumes, checked against the ownership of the `config.xml` Sonarr writes
- an HTTP port that is not the `8989` the image exposes, checked by waiting for `/ping` — which reads Sonarr's configuration out of its SQLite database — on the role's port
- a timezone that is UTC+14 all year round, checked against the offset the container reports
- a Traefik hostname and path prefix, checked against the router rule, the strip-prefix middleware and the load balancer port on the container's labels — and the label file is rendered a second time with Traefik disabled, to catch labels leaking out of that conditional
- an additional container network, an additional read-only bind mount and an extra `docker create` argument, checked against `docker container inspect` and by reading a marker file back out of the mount

It also asserts that the version Sonarr reports over its API is the `sonarr_version` that `defaults/main.yml` pins.

Two things this scenario deliberately does *not* rely on, both established by running the image by hand: Sonarr's single-page web UI answers `200` on every path, including paths that do not exist; and a Sonarr that aborts at startup leaves s6 holding the container open, so the systemd unit still reports `active`.

## Running

By default it is configured to run the scenarios on Ubuntu 26.04.

```bash
molecule test --scenario-name default
```

You can utilize other distributions by setting one to the `MOLECULE_DISTRO` environment variable:

```bash
# Ubuntu 24.04
MOLECULE_DISTRO=ubuntu2404 molecule test --scenario-name default

# Debian 13
MOLECULE_DISTRO=debian13 molecule test --scenario-name default

# Debian 12
MOLECULE_DISTRO=debian12 molecule test --scenario-name default
```
