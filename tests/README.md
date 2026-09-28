# Tests

What a test means for an appliance recipe is written in `COVERAGE.md`: the
recipe builds, the result boots in an LXC container, its first boot
completes headless from an instance spec, and the machine matches the spec.

## Layout

- `boot-test.sh`: the boot test. `test-appliance.yml` (reusable workflow of
  `keel-linux/.github`) runs it on the self-hosted LXC runner after pulling
  the layers from `https://mirror.keellinux.org/layers` and checking them
  with `keel verify`. It is the thin main: assemble, mark the tree as a
  container, install the spec, the secret and the conf, start the container,
  wait, `keel diff`.
- `lib/boot-test-lib.sh`: the logic (argument parsing, address discovery
  from `lxc-info`, waiting with a deadline, readiness checks, verdicts), as
  functions with no side effects, per decision 0004.
- `boot-test.bats`: unit tests of the library. `lxc-info` is a stub first in
  `PATH`; the clock and `sleep` are functions. No root, no network, no LXC.
- `banner.bats`: unit tests of `overlay/usr/lib/keel/banner.sh`, the console
  banner renderer of the appliance overlay (the version string, the title,
  the address block, which mark fits, the centring of the mark, the whole
  block). The mark files are the ones the overlay installs and the addresses
  are arguments, so nothing here needs a terminal, a network or root. No test
  writes down the size of a mark: it is measured from the file, so the art can
  be redrawn in the design system without touching a test. Two tests hold that
  open with marks of their own rather than the installed art: one reads the
  blank columns off each side of a centred block and requires them equal, and
  one renders marks from a single character up to 31 by 71 and requires each
  to come out whole, centred and above an address block that lost no line.
- `motd.bats`: unit tests of `overlay/usr/lib/keel/motd.sh`, the rest of
  the Keel message of the day (the system information block with the
  backup client's tail cut off it, what the appliance says about backup,
  the configuration console line, and the two functions `conf.d/main` uses
  at build time to leave `/etc/update-motd.d` with Keel's drop-ins and no
  TurnKey ones). The system information is fed in as text captured from a
  running appliance, and the drop-in directory is a scratch directory, so
  nothing here needs an appliance.
- `coverage.sh`: runs each bats file under kcov and fails when any measured
  file is below `COVERAGE_THRESHOLD` (default 95). `conf.d/main` is measured
  too: `motd.bats` runs the conf script itself, with `MOTD_DIR` and
  `KEEL_MOTD_LIB` pointed at a scratch directory.
- `instance.yaml`: the spec the container boots from. IPv6 only, address
  from the bridge, no certificate request, no network at first boot.

## Unit tests and coverage

Debian packages `bats` (1.11) and `kcov` (43); no root:

    bats tests/boot-test.bats tests/banner.bats tests/motd.bats
    COVERAGE_THRESHOLD=100 tests/coverage.sh

`COVERAGE_DIR=coverage tests/coverage.sh` keeps the kcov reports, one
directory per measured library; each `index.html` shows the executed
lines.

## The banner by hand

The renderer is sourceable, so the block can be printed without an
appliance. From the repository root:

    KEEL_BANNER_MARK=overlay/etc/keel/banner.txt \
    KEEL_BANNER_MARK_SMALL=overlay/etc/keel/banner-small.txt \
    bash -c 'source overlay/usr/lib/keel/banner.sh
             keel_banner_render 40 100 "Keel Linux core" 19.0-trixie-amd64 \
                 2001:db8:1::10 192.0.2.10'

The first two arguments are the rows and columns of the terminal. The mark is
centred on the columns as a block; a terminal with no room for the full mark
falls back to `banner-small.txt`, and one narrower than the small mark drops
the mark and keeps the addresses. On an appliance the same block comes from
`/etc/update-motd.d/00-keel-banner` at every login.

The rest of the login is sourceable in the same way:

    bash -c 'source overlay/usr/lib/keel/motd.sh
             turnkey-sysinfo | keel_motd_system_block \
                 | keel_motd_indent "$KEEL_MOTD_INDENT"
             echo
             keel_motd_backup_lines | keel_motd_indent "$KEEL_MOTD_INDENT"
             keel_motd_confconsole_lines'

On a machine with no `turnkey-sysinfo`, feed `keel_motd_system_block` any
text: it keeps the header and the table and stops at the blank line that
ends them, which is how the backup client's block is dropped without
matching on the words it happens to print.

## The boot test by hand

Needs root, `keel` on `PATH`, LXC (`lxc-start`, `lxc-info`, `lxc-attach`,
`lxc-stop`) and a bridge with IPv6 router advertisements or DHCPv6. It does
not need fab, deck or buildtasks: the layers are fetched, not built.

On any host with LXC, from the repository root, taking the layers from the
project mirror over IPv6:

    tests/boot-test.sh core --layers-dir https://mirror.keellinux.org/layers \
        --bridge lxcbr0

On the build host, against the layers `bt-layer` just wrote:

    /turnkey/buildtasks-keel/bt-layer core
    keel verify --layers-dir /mnt/builds/layers --non-interactive
    tests/boot-test.sh core

`--layers-dir` is a directory or an http(s) URL; the other useful options
are `--bridge`, `--cache-dir`, `--lxc-path`, `--name`, `--timeout 600` and
`--keep` (leaves the container running; then `lxc-attach -n <name>`, and
`lxc-stop -k` plus `rm -r <lxc-path>/<name>` when done).
`tests/boot-test.sh --help` lists them all.

What it does, in order:

1. `keel pull` and `keel assemble` the chain into
   `<lxc-path>/<name>/rootfs`.
2. Creates `var/lib/turnkey-info/inithooks.service/lxc` in the rootfs, the
   marker `bt-container` writes and the one `keel inspect` reads to call the
   machine a container (`network.managed_by: host`).
3. Writes a random root password to `etc/keel/secrets/root_password` (mode
   0600) and installs `tests/instance.yaml` at `etc/keel/instance.yaml` and
   `etc/inithooks.yaml` in the rootfs (both paths the first boot may read
   until the maintainer settles the name).
4. Renders the spec into the rootfs `etc/inithooks.conf` with `keel spec
   apply`, from a copy whose secret references point inside the rootfs.
   Without the conf the first boot is not headless: `30rootpass` opens a
   dialog and waits forever.
5. Writes an LXC config for that rootfs on the bridge and starts the
   container.
6. Waits for a global IPv6 address on the container (`lxc-info -i`).
7. Waits until the first boot has finished: `RUN_FIRSTBOOT=false` in the
   rootfs copy of `/etc/default/inithooks`, and then either a `confconsole`
   process (the usage screen on the console) or an SSH banner on
   `[address]:22`. The flag is what says the boot ended; sshd answers long
   before the hooks are done.
8. Renders `/etc/update-motd.d` in the running container with
   `run-parts`, which is what pam_motd does at an interactive login, and
   checks the result: exactly one welcome, it names Keel, the system
   information block still carries the load, the memory, the processes,
   the swap, the usage of `/` and an address, and the login says neither
   `turnkey` nor `tklbam` (issue #6). The rendered block is printed, so a
   failure is readable in the job log.
9. Runs `keel diff --root <rootfs> --spec tests/instance.yaml`; exit 0 or
   13 (no drift) passes, 14 (drift) or any other code fails.

Measured on `keel-lxc-1` (2 GB of layer, 6 vCPU): pull 3 s from the mirror
on the same host, assemble 13 s, boot and first boot 10 s.

On failure it prints the last lines of the container's
`/var/log/inithooks.log`. The container is stopped and removed unless
`--keep` was given. Each wait has its own `--timeout` (default 900 s).
