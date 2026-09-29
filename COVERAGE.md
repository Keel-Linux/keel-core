# Test coverage baseline

Measured on 2026-09-26 against master 24c82ee (equal to upstream
turnkeylinux-apps/core master), following the project decisions 0003 (90
percent floor per repository, 95 percent for every file the project
writes), 0004 (shell: bats plus kcov) and 0006 (the gate runs in GitHub
Actions and is a required status on the default branch).

## What this repository is

An appliance recipe, not a program: `Makefile` (2 lines: the Webmin
firewall ports and the include of `turnkey.mk` from common), `plan/main`
(1 line: `#include <turnkey/base>`), `conf.d/main` (the message of the
day: the one thing an overlay cannot do, remove a file), the overlay and
documentation. Every package,
hook and conf script of the image comes from `common`, `fab` and the
Debian and TurnKey archives, each measured in its own repository.

The overlay carries the appliance's own text and, since the console
banner, its first piece of project-authored shell:

| Path | What it is | Measured |
| --- | --- | --- |
| `etc/confconsole/services.txt` | the lines confconsole shows on its usage screen | data |
| `etc/keel/banner.txt`, `etc/keel/banner-small.txt` | the mark in ASCII, the full one and the small one, installed unmodified from the design system (exports of `keel-mark.svg`; a change is a re-export, never an edit of the characters). Their size is whatever the exported files carry: the renderer measures each file, centres the mark it picked on the width of the terminal and falls back to the small mark and then to none as the screen shrinks, so a re-export at another size needs no change here | data |
| `usr/lib/keel/banner.sh` | the banner renderer, pure functions (decision 0004) | 100 percent, see below |
| `usr/lib/keel/motd.sh` | the rest of the login: the system information block, the backup line, the console line, and the two functions `conf.d/main` uses at build time, pure functions (decision 0004) | 100 percent, see below |
| `etc/update-motd.d/00-keel-banner` | the thin main: terminal size, version file, `ip` probe, one call into the library | the LXC run |
| `etc/update-motd.d/01-keel-sysinfo` | the thin main: run the system information command, cut its backup tail, print the backup line | the LXC run |
| `etc/update-motd.d/08-keel-confconsole` | the thin main: print the console line | the LXC run |

The banner is a drop-in named before the files `common`
(`conf/turnkey.d/motd`) writes, so every word upstream prints keeps its
place and the mark is added above it. That directory is what pam_motd runs
at an interactive login, over SSH and on the container console alike; the
other console, tty1 running confconsole from inithooks, never reaches
pam_motd and gets the mark from the confconsole repository, from these
same two files. `/etc/issue` was not used: getty prints it before the
login prompt, so the mark would scroll away with each failed attempt and
be printed twice on a console login.

## What "test" means here

Org-plan section 1: the layer boots in an LXC container, its first boot
completes headless from an instance spec, and the machine matches the
spec. Coverage of an appliance recipe is that test passing. It is the
acceptance test of decision 0004 item 4 and it does not count toward a
unit number.

1. **Fetch and verify.** The layer is built and published by the build
   host; `test-appliance.yml` pulls it from
   `https://mirror.keellinux.org/layers` over IPv6 and runs `keel verify`,
   which passes on 0, 8 (hash file present, not signed) and 9, and fails
   on 6 and 7. The self-hosted runner has no fab, deck or buildtasks and
   builds nothing.
2. **Boot.** `tests/boot-test.sh core` assembles the chain into a scratch
   LXC rootfs, marks it as a container, installs `tests/instance.yaml`
   (IPv6 from the bridge, ACME off, root password from a file it writes)
   and renders it into `etc/inithooks.conf` so the first boot is headless,
   starts the container, waits for a global IPv6 address, then for
   `RUN_FIRSTBOOT=false` plus confconsole or an SSH banner, and runs
   `keel diff --root <rootfs>` against the spec: exit 0 or 13 (no drift)
   passes. `tests/README.md` documents the run by hand.
3. **Unit tests of the test.** The boot test is project-authored shell,
   so it follows decision 0004: the logic (argument parsing, address
   discovery from `lxc-info`, waiting with a deadline, readiness checks,
   verdicts) is `tests/lib/boot-test-lib.sh`, exercised by
   `tests/boot-test.bats` with a PATH stub for `lxc-info` and function
   stubs for the clock and `sleep`; `tests/coverage.sh` measures it with
   kcov. `tests/boot-test.sh` is the thin main that runs `keel` and LXC as
   root and is exercised only by the LXC run.

## State

| What | Measured | How |
| --- | --- | --- |
| Recipe (`Makefile`, `plan/main`, `conf.d/main`, `overlay`) | builds identically to upstream: the M0 gate run of 2026-09-26 built this repository at 24c82ee and upstream core at the same commit from the same bootstrap; 412 identical packages, 49 of 33,684 files differ, all install-time state (keys, timestamps, pids, Perl hash order), none traceable to a source difference; the squashfs is bit-identical across two packings and the ISO too with the project's fab | `docs/m0-gate.md` and `docs/m0-gate-run-2026-09-26.md` of the keel project |
| Boot test | passes on the self-hosted runner `keel-lxc-1` since 2026-09-26: `keel pull` 3 s from the mirror, `keel verify` exit 9, assemble 13 s, boot and first boot 10 s, `keel diff` 6 same, 0 drift, 2 unknown (`instance.fqdn` and the IPv6 method, neither readable from an offline root, exit 13); 30 s for the whole job. Three upstream hooks report an error in a container without a hub account and without the appliance's certificate tooling (`15regen-sslcert`, `29tagid`, `95secupdates`); the run continues and the machine matches the spec | `tests/boot-test.sh`, `test-appliance.yml` |
| `tests/lib/boot-test-lib.sh` | 100 percent (224 of 224 lines, 72 bats tests, kcov 43), measured on 2026-09-29 with the login verdicts and their applicability | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |
| `overlay/usr/lib/keel/banner.sh` | 100 percent (124 of 124 lines, 71 bats tests, kcov 43), measured on 2026-09-28 with the identity file it reads | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |
| `overlay/usr/lib/keel/motd.sh` | 100 percent (62 of 62 lines, 43 bats tests, kcov 43), measured on 2026-09-28 | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |
| `conf.d/main` | 100 percent (8 of 8 lines, kcov 43), measured on 2026-09-28 in the same kcov run as `motd.sh`, which executes the conf script against a scratch drop-in directory | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |

Baseline for the threshold in `.github/workflows/tests.yml`: 100, the
measured number of all four project-authored files (186 bats tests in
all); it is only ever raised. `tests/coverage.sh` measures each library
against the bats file that exercises it and fails when any one is below
the threshold.

## The login

`conf.d/main` stopped being a no-op on 2026-09-28: it removes the two
drop-ins `common` writes that speak for another product
(`00-turnkey-sysinfo`, `08-turnkey-confconsole`) and checks that the
directory was left with every Keel drop-in and none of anyone else's. An
overlay cannot remove a file, which is why this is a conf script and not
an overlay entry.

The order was read from `root.patched/body` in `/usr/share/fab/product.mk`
**of the build host**, which runs fab `1.1.1+keel2` (`product.mk` md5
`a06bfe03`). The unit phases belong to that version: they arrive in it
through *Apply the units before the common removelists* and *Let a unit
carry a removelist*, so `1.1.1` (md5 `0657df1a`, what a stock tkldev
container has) and `1.1.1+keel1` (md5 `c04cb601`) both still have
upstream's order. Check the reading against the md5 rather than against
the version string, and take it from the machine that builds:

1. common overlays
2. common conf scripts (`conf/turnkey.d/motd` among them)
3. common patches
4. unit overlays
5. unit conf scripts
6. unit removelists
7. common removelists
8. the product overlay
9. the product conf scripts (`conf.d/main`)
10. the product patches, the product removelist, the initramfs, the
    common removelists-final
11. `root.patched/post`, where `/etc/turnkey_version` and
    `/etc/keel_version` are written

Two positions carry this change, 2 before 8 and 8 before 9. A recipe with
units should note 5: unit conf scripts run before the product overlay,
not after it.

The limit of putting the prune in one recipe: it is enough for the way
Keel ships, because `bt-layer` subtracts the parent's `common_conf` from
the child's, so no appliance built on core re-runs
`conf/turnkey.d/motd` and core's removals are inherited by every layer
above it. A plain `make` of a non-core recipe, with the full
`COMMON_CONF` and no parent, writes the drop-ins again and has no prune
to take them away; a recipe built that way needs the same two calls in
its own `conf.d`.

What the login must look like is asserted against a booted container and
not against a file: step 6 of the boot test renders `/etc/update-motd.d`
with `run-parts`, which is what pam_motd does at an interactive login, and
requires exactly one welcome, that it names Keel, that the system
information block still carries the load, the memory, the processes, the
swap and the usage of `/`, that it still reports on the network, that the
login carries one of the addresses the container actually answers on,
and that neither `turnkey` nor `tklbam` appears anywhere in it.

The address is checked from the machine and not from a word, because the
address row of the system information block is IPv4 only: it comes from
`netinfo.InterfaceInfo.address`, which is `SIOCGIFADDR` on an `AF_INET`
socket, and on a machine with no IPv4 the command prints `Networking not
configured` instead. `tests/instance.yaml` declares an IPv6-only
appliance, and the gate passes today only because lxcbr0 also hands out
IPv4. Requiring the words "IP address" would fail an IPv6-only appliance
that is entirely correct, so the block is required to carry either row and
the address the operator is given is asserted against the ones the
container answers on, of which the banner prints IPv6 first. Every
global address is passed, not the first one discovered, because a
machine can hold several and which of them the banner shows is the
banner's own rule (static before dynamic, privacy last).

The login verdict and the drift verdict are collected and reported
together at the end rather than short circuited, so a red login check never costs the run the drift check.

## Gate

`.github/workflows/tests.yml` has two jobs. `tests` calls `test-shell.yml`
with threshold 100 and produces the required check `tests / coverage` on
hosted runners, on every pull request and push to master. `appliance`
calls `test-appliance.yml` with `appliance: core` and is gated on the
organization variable `KEEL_LXC_RUNNER`, as the reusable workflow requires
(a job targeting the `keel-lxc` label with no such runner stays queued for
24 hours). The variable is `true` since 2026-09-26, so both checks appear
on every pull request and both are required on `master`:
`tests / coverage` and `appliance / boot-published-layer`.

The appliance check boots the `core` layer the mirror publishes, which was
built before the branch under test, so it is evidence about that layer and not
about the diff. A layer that has never been published fails it rather than
passing it (keel-linux/.github pull request 12).

## Plan

1. The layer still carries upstream's inithooks, which has no
   `00declarative` hook, so the spec reaches the first boot as
   `/etc/inithooks.conf` rendered by `keel spec apply` before the container
   starts, not as a spec the machine reads itself. When the inithooks fork
   is in the layer, that rendering step goes away and `tests/instance.yaml`
   becomes the input rather than a description of the result; the value
   marked in that file (`ipv6.method`) is the one to revisit then.
2. Fail the boot test on the three hooks that report an error, once each
   has been diagnosed: `15regen-sslcert`, `29tagid`, `95secupdates`.
3. The recipe is no longer byte-identical to upstream: the console banner
   of 2026-09-26 is the first project-authored addition to the overlay
   and the login of 2026-09-28 is the second. The M0 gate reference
   stands at 24c82ee, the commit both trees were built from, and a
   rebuild now differs by the overlay files listed above, all of them new
   paths and none of them an edit of an upstream file, plus `conf.d/main`,
   which no longer does nothing: it removes the two drop-ins of another
   product from `/etc/update-motd.d`. That is a deliberate divergence, it
   is the subject of issue #7, and it comes with the decision 0004
   treatment (a tested library, `overlay/usr/lib/keel/motd.sh`) and a
   behavioural assertion in the boot test. `plan/main` and the `Makefile`
   are still untouched.
4. The layer on the mirror lags the repository whenever the overlay or a
   conf script changes, and the boot test boots the layer. The login
   check is therefore asked only of a layer built with the login change,
   recognised by `/usr/lib/keel/motd.sh`, which `conf.d/main` refuses to
   build without. On an older layer it reports that it did not apply and
   names the remedy, rebuild and publish the layer; it does not pass, and
   a run in which no check applied fails. It was a hard failure first,
   and that could not work: the check is required and strict on master,
   the layer can only be rebuilt from master after the merge, and so no
   merge could ever have turned it green. On a layer that carries the
   change, a wrong login fails as before, so a regression is still
   caught by the first published layer that has one.
5. The two spec paths (`etc/keel/instance.yaml`, `etc/inithooks.yaml`)
   collapse to one when the maintainer settles the name (brief section
   11); `BT_SPEC_PATHS` in the library and its test change in one line.
