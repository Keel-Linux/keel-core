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
post-package configuration), `overlay/etc/confconsole/services.txt` (the
lines confconsole shows on its usage screen) and documentation. Every
package, hook and conf script of the image comes from `common`, `fab` and
the Debian and TurnKey archives, each measured in its own repository.
There is nothing to unit test in the recipe itself.

## What "test" means here

Org-plan section 1: the recipe builds on the runner (`bt-layer`), the
result boots in an LXC container, its first boot completes headless from
an instance spec, and the machine answers over IPv6 and matches the spec.
Coverage of an appliance recipe is that test passing. It is the
acceptance test of decision 0004 item 4 and it does not count toward a
unit number.

1. **Build.** `bt-layer core` builds the layer on the self-hosted LXC
   runner; `keel verify` checks its manifest (`test-appliance.yml`).
2. **Boot.** `tests/boot-test.sh core` assembles the chain into an LXC
   rootfs, installs `tests/instance.yaml` (IPv6 from the bridge, ACME off,
   no network at first boot, root password from a file it writes), starts
   the container, waits for a global IPv6 address, then for the first boot
   to finish (confconsole's usage screen on the console, or SSH answering
   on port 22 over IPv6), and runs `keel diff --root <rootfs>` against the
   spec: exit 0 or 13 (no drift) passes. `tests/README.md` documents the
   run by hand on the build host.
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
| Boot test | not run yet: no self-hosted runner is registered (`KEEL_LXC_RUNNER` is `false`), and the M0 image is built with upstream's inithooks from the archive, so a headless first boot from the spec depends on the organization's inithooks package (hook `00declarative`) being in the image | `tests/boot-test.sh`, `test-appliance.yml` |
| `tests/lib/boot-test-lib.sh` | 100 percent (97 of 97 lines, 26 bats tests, kcov 43) | `COVERAGE_THRESHOLD=100 tests/coverage.sh` |

Baseline for the threshold in `.github/workflows/tests.yml`: 100, the
measured number of the one project-authored file; it is only ever raised.

## Gate

`.github/workflows/tests.yml` has two jobs. `tests` calls `test-shell.yml`
with threshold 100 and produces the required check `tests / coverage` on
hosted runners, on every pull request and push to master. `appliance`
calls `test-appliance.yml` with `appliance: core` and is gated on the
organization variable `KEEL_LXC_RUNNER`, as the reusable workflow requires
(a job targeting the `keel-lxc` label with no such runner stays queued for
24 hours). While the variable is `false` the job is skipped and no check
appears, so branch protection requires `tests / coverage` alone. When the
runner is registered and the variable set to `true`, the check
`appliance / build-and-boot` appears on the next push and is added to the
protection rule; that is the tightening step.

## Plan

1. Register the LXC runner (docs/ci-cd.md section 6 of the keel
   repository), set `KEEL_LXC_RUNNER` to `true`, let the boot test run once
   on master, add `appliance / build-and-boot` to the protection rule.
2. Until the image carries the organization's inithooks, the first boot of
   the M0 image is interactive and the test times out on step 5 with the
   inithooks log printed; the fix is on the packaging side (the inithooks
   fork built by `build-deb.yml` and installed by the plan), not here.
3. The recipe stays byte-identical to upstream until the M0 gate no longer
   depends on it. Any later change to `plan/main`, `conf.d` or the
   `Makefile` comes with the boot test green and, for a conf script, the
   decision 0004 treatment.
4. The two spec paths (`etc/keel/instance.yaml`, `etc/inithooks.yaml`)
   collapse to one when the maintainer settles the name (brief section
   11); `BT_SPEC_PATHS` in the library and its test change in one line.
