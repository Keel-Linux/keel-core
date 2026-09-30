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
- `coverage.sh`: runs each bats file under kcov and fails when any measured
  library is below `COVERAGE_THRESHOLD` (default 95).
- `instance.yaml`: the spec the container boots from. IPv6 only, address
  from the bridge, no certificate request, no network at first boot.

## Unit tests and coverage

Debian packages `bats` (1.11) and `kcov` (43); no root:

    bats tests/boot-test.bats tests/banner.bats tests/image-conf.bats
    COVERAGE_THRESHOLD=100 tests/coverage.sh

- `image-conf.bats`: unit tests of `conf.d/main`, the conf script fab runs
  in the image chroot, run against a scratch tree named by
  `KEEL_CONF_ROOT`: the WireGuard guards (a file in `/etc/wireguard`, an
  enabled `wg-quick@` unit) and the deletion of CrowdSec's identity
  (tracker#47), which keeps the packages' configuration and fails the
  build when a file cannot be deleted.
- `package.bats`: builds `packages/keel-core` with `dpkg-buildpackage` and
  reads back its fields, its files and the manifest's Core table. Needs
  `dpkg-dev`, `debhelper` and `python3-yaml` besides `bats`; it runs in
  the check `packages / build` (`.github/workflows/packages.yml`), with
  lintian over the source and binary package.

## The package on a built image

What the package does on a machine is proven on an image built from this
branch, since the boot test boots the published layer. The container is
started as `boot-test.sh` does it, with a spec in a simple installation
(`appliance.name: core`, `installation.mode: simple`, every overlay
written out, `monitor.enabled: true` with a channel) and the conf rendered
by `keel spec apply --conf <rootfs>/etc/inithooks.conf --root <rootfs>`
before the first boot: inithooks' own reader of the spec does not know
`appliance`, `installation`, `overlays` or `monitor` yet. Then, on the
container:

    keel manifest validate
    keel manifest show core --resolved   # the Core table of decision 0041
    systemctl is-active etcd crowdsec crowdsec-firewall-bouncer   # inactive
    keel inspect --output /root/emitted.yaml
    keel spec apply --system --spec /root/emitted.yaml   # 0 change(s)

`inspect` cannot read the monitor's channels back (they are in
`/etc/keel/monitor.json`, which it does not repeat), so the channel is
added to the emitted file before it is applied, as its report says. And
Monit's `/etc/keel/monit/keel-manifest.conf` checks sshd, webmin and
postfix and nothing else. Core has no web shell: TurnKey removed
shellinabox in 18.0, so the manifest does not declare the `webshell` of
the handbook's first draft (its errata of 0041).

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
8. Runs `keel diff --root <rootfs> --spec tests/instance.yaml`; exit 0 or
   13 (no drift) passes, 14 (drift) or any other code fails.

Measured on `keel-lxc-1` (2 GB of layer, 6 vCPU): pull 3 s from the mirror
on the same host, assemble 13 s, boot and first boot 10 s.

On failure it prints the last lines of the container's
`/var/log/inithooks.log`. The container is stopped and removed unless
`--keep` was given. Each wait has its own `--timeout` (default 900 s).
