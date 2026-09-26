# Tests

What a test means for an appliance recipe is written in `COVERAGE.md`: the
recipe builds, the result boots in an LXC container, its first boot
completes headless from an instance spec, and the machine matches the spec.

## Layout

- `boot-test.sh`: the boot test. `test-appliance.yml` (reusable workflow of
  `keel-linux/.github`) runs it on the self-hosted LXC runner after
  `bt-layer` built the layer and `keel verify` checked it. It is the thin
  main: assemble, install the spec, start the container, wait, `keel diff`.
- `lib/boot-test-lib.sh`: the logic (argument parsing, address discovery
  from `lxc-info`, waiting with a deadline, readiness checks, verdicts), as
  functions with no side effects, per decision 0004.
- `boot-test.bats`: unit tests of the library. `lxc-info` is a stub first in
  `PATH`; the clock and `sleep` are functions. No root, no network, no LXC.
- `coverage.sh`: runs the bats file under kcov and fails when the library is
  below `COVERAGE_THRESHOLD` (default 95).
- `instance.yaml`: the spec the container boots from. IPv6 only, address
  from the bridge, no certificate request, no network at first boot.

## Unit tests and coverage

Debian packages `bats` (1.11) and `kcov` (43); no root:

    bats tests/boot-test.bats
    COVERAGE_THRESHOLD=95 tests/coverage.sh

`COVERAGE_DIR=coverage tests/coverage.sh` keeps the kcov report;
`coverage/index.html` shows the executed lines.

## The boot test by hand, on the build host

Needs root, `keel` on `PATH`, LXC (`lxc-start`, `lxc-info`, `lxc-attach`,
`lxc-stop`), a bridge with IPv6 router advertisements or DHCPv6 (default
`br0`), and the layers `bt-layer` wrote (default `/mnt/builds/layers`).
From the repository root:

    /turnkey/buildtasks/bt-layer core
    keel verify --layers-dir /mnt/builds/layers --non-interactive
    tests/boot-test.sh core

Useful options: `--bridge lxcbr0`, `--layers-dir DIR`, `--lxc-path DIR`,
`--timeout 600`, `--keep` (leaves the container running; then
`lxc-attach -n keel-core-boot-test`, and `lxc-stop -k` plus
`rm -r /var/lib/lxc/keel-core-boot-test` when done). `tests/boot-test.sh
--help` lists them all.

What it does, in order:

1. `keel pull` and `keel assemble` the chain into
   `/var/lib/lxc/keel-core-boot-test/rootfs`.
2. Writes a random root password to `etc/keel/secrets/root_password` (mode
   0600) and installs `tests/instance.yaml` at `etc/keel/instance.yaml` and
   `etc/inithooks.yaml` in the rootfs (both paths the first boot may read
   until the maintainer settles the name).
3. Writes an LXC config for that rootfs on the bridge and starts the
   container.
4. Waits for a global IPv6 address on the container (`lxc-info -i`).
5. Waits until the first boot has finished: `RUN_FIRSTBOOT=false` in the
   rootfs copy of `/etc/default/inithooks` and a `confconsole` process (the
   usage screen on the console), or an SSH banner on `[address]:22`.
6. Runs `keel diff --root <rootfs> --spec tests/instance.yaml`; exit 0 or
   13 (no drift) passes, 14 (drift) or any other code fails.

On failure it prints the last lines of the container's
`/var/log/inithooks.log`. The container is stopped and removed unless
`--keep` was given. Each wait has its own `--timeout` (default 900 s).
