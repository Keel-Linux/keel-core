# Test coverage baseline

Measured on 2026-09-26 against master 24c82ee (equal to upstream
turnkeylinux-apps/core master), following the project decisions 0003 (90
percent floor per repository, 95 percent for every file the project
writes), 0004 (shell: bats plus kcov) and 0006 (the gate runs in GitHub
Actions and is a required status on the default branch).

## What this repository is

An appliance recipe, not a program: `Makefile` (2 lines: the Webmin
firewall ports and the include of `turnkey.mk` from common), `plan/main`
(1 line: `#include <turnkey/base>`), `conf.d/main` (a no-op: core needs no
post-package configuration), the overlay and documentation. Every package,
hook and conf script of the image comes from `common`, `fab` and the
Debian and TurnKey archives, each measured in its own repository.

The overlay carries the appliance's own text and, since the console
banner, its first piece of project-authored shell:

| Path | What it is | Measured |
| --- | --- | --- |
| `etc/confconsole/services.txt` | the lines confconsole shows on its usage screen | data |
| `etc/keel/banner.txt`, `etc/keel/banner-small.txt` | the mark in ASCII, 38 by 19 and 23 by 11, installed unmodified from the design system (exports of `keel-mark.svg`; a change is a re-export, never an edit of the characters) | data |
| `usr/lib/keel/banner.sh` | the banner renderer, pure functions (decision 0004) | 100 percent, see below |
| `etc/update-motd.d/00-keel-banner` | the thin main: terminal size, version file, `ip` probe, one call into the library | the LXC run |

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
| Boot test | passes on the self-hosted runner `keel-lxc-1` since 2026-09-26: pull 3 s, assemble 13 s, boot and first boot 10 s, `keel diff` 8 same, 0 drift, 1 unknown (`instance.fqdn`, which inspect cannot read offline, exit 13). Three upstream hooks report an error in a container without a hub account and without the appliance's certificate tooling (`15regen-sslcert`, `29tagid`, `95secupdates`); the run continues and the machine matches the spec | `tests/boot-test.sh`, `test-appliance.yml` |
| `tests/lib/boot-test-lib.sh` | 100 percent (109 of 109 lines, 30 bats tests, kcov 43) | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |
| `overlay/usr/lib/keel/banner.sh` | 100 percent (102 of 102 lines, 48 bats tests, kcov 43), measured on 2026-09-26 with the console banner | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |

Baseline for the threshold in `.github/workflows/tests.yml`: 100, the
measured number of both project-authored files (78 bats tests in all); it
is only ever raised. `tests/coverage.sh` measures each library against the
bats file that exercises it and fails when any one is below the
threshold.

## Gate

`.github/workflows/tests.yml` has two jobs. `tests` calls `test-shell.yml`
with threshold 100 and produces the required check `tests / coverage` on
hosted runners, on every pull request and push to master. `appliance`
calls `test-appliance.yml` with `appliance: core` and is gated on the
organization variable `KEEL_LXC_RUNNER`, as the reusable workflow requires
(a job targeting the `keel-lxc` label with no such runner stays queued for
24 hours). The variable is `true` since 2026-09-26, so both checks appear
on every pull request and both are required on `master`:
`tests / coverage` and `appliance / build-and-boot`.

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
   of 2026-09-26 is the first project-authored addition to the overlay.
   The M0 gate reference stands at 24c82ee, the commit both trees were
   built from, and a rebuild now differs by exactly the four overlay
   files listed above, all of them new paths, none of them an edit of an
   upstream file. `plan/main`, `conf.d` and the `Makefile` are still
   untouched. Any later change to those three comes with the boot test
   green and, for a conf script, the decision 0004 treatment.
4. The two spec paths (`etc/keel/instance.yaml`, `etc/inithooks.yaml`)
   collapse to one when the maintainer settles the name (brief section
   11); `BT_SPEC_PATHS` in the library and its test change in one line.
