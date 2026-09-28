#!/usr/bin/env bats
# Unit tests of overlay/usr/lib/keel/motd.sh: the system information block,
# the backup line, the confconsole line and the two build-time functions
# conf.d/main uses to leave /etc/update-motd.d with Keel's drop-ins and no
# TurnKey ones.
#
# Nothing here needs root, a network or an appliance: the system
# information is fed in as text, captured from a running appliance on
# 2026-09-28, and the drop-in directory is a scratch directory.

bats_require_minimum_version 1.5.0

setup() {
    load ../overlay/usr/lib/keel/motd.sh
    SCRATCH="$BATS_TEST_TMPDIR/motd"
    mkdir -p "$SCRATCH"
}

# bats fills $lines only for "run", and a block built through a pipeline
# cannot be run that way, so the tests that read it line by line split it
# here.
split_output() {
    mapfile -t lines <<< "$output"
}

# What turnkey-sysinfo prints to root on an appliance: the header, a blank
# line, the table, a blank line and then the TKLBAM block. Captured from
# the wordpress-demo container on the build host, 2026-09-28.
sysinfo_as_root() {
    cat <<'OUT'
System information for Mon Sep 28 02:20:44 2026 (UTC+0000)

  System load:  0.00               Memory usage:  54.8%
  Processes:    39                 Swap usage:    6.3%
  Usage of /:   88.2% of 58.76GB   IP address for eth0: 10.88.5.69

TKLBAM (Backup and Migration):  NOT INITIALIZED

  To initialize TKLBAM, run the "tklbam-init" command to link this
  system to your TurnKey Hub account. For details see the man page or
  go to:

      https://www.turnkeylinux.org/tklbam

OUT
}

# The same command with no backup client installed: the tail is one line.
sysinfo_without_tklbam() {
    cat <<'OUT'
System information for Mon Sep 28 02:20:44 2026 (UTC+0000)

  System load:  0.00               Memory usage:  54.8%
  Processes:    39                 Swap usage:    6.3%
  Usage of /:   88.2% of 58.76GB   IP address for eth0: 10.88.5.69

TKLBAM not installed.
OUT
}

# What it prints when it is not root: the table and nothing after it.
sysinfo_as_user() {
    cat <<'OUT'
System information for Mon Sep 28 02:20:44 2026 (UTC+0000)

  System load:  0.00               Memory usage:  54.8%
  Processes:    39                 Swap usage:    6.3%
  Usage of /:   88.2% of 58.76GB   IP address for eth0: 10.88.5.69
OUT
}

# the system information block

@test "system_block: the header and the table survive whole" {
    output=$(sysinfo_as_root | keel_motd_system_block)
    split_output
    [ "${lines[0]}" = "System information for Mon Sep 28 02:20:44 2026 (UTC+0000)" ]
    [[ $output == *"System load:  0.00"* ]]
    [[ $output == *"Memory usage:  54.8%"* ]]
    [[ $output == *"Processes:    39"* ]]
    [[ $output == *"Swap usage:    6.3%"* ]]
    [[ $output == *"Usage of /:   88.2% of 58.76GB"* ]]
    [[ $output == *"IP address for eth0: 10.88.5.69"* ]]
}

@test "system_block: the backup tail of the command is dropped" {
    output=$(sysinfo_as_root | keel_motd_system_block)
    [[ $output != *TKLBAM* ]]
    [[ $output != *tklbam* ]]
    [[ $output != *turnkeylinux.org* ]]
    [[ $output != *"TurnKey Hub"* ]]
}

@test "system_block: the tail is cut by shape, not by the words it uses" {
    # Nothing here matches on "TKLBAM": the rule is the blank line that
    # ends the table, so a tail nobody has seen yet goes too.
    output=$(printf 'System information for now\n\n  System load:  0.00\n\nSOMETHING ELSE ENTIRELY\n  with a second line\n' \
        | keel_motd_system_block)
    split_output
    [ "${#lines[@]}" -eq 3 ]
    [[ $output != *"SOMETHING ELSE"* ]]
}

@test "system_block: a tail of one line goes too" {
    output=$(sysinfo_without_tklbam | keel_motd_system_block)
    [[ $output != *"TKLBAM not installed"* ]]
    [[ $output == *"System load:  0.00"* ]]
}

@test "system_block: output with no tail at all is kept whole" {
    expected=$(sysinfo_as_user)
    output=$(sysinfo_as_user | keel_motd_system_block)
    [ "$output" = "$expected" ]
}

@test "system_block: the blank line between the header and the table stays" {
    output=$(sysinfo_as_root | keel_motd_system_block)
    split_output
    [ -z "${lines[1]}" ]
}

@test "system_block: it never ends in a blank line" {
    output=$(sysinfo_as_root | keel_motd_system_block)
    split_output
    [ -n "${lines[${#lines[@]}-1]}" ]
}

@test "system_block: no input is no output" {
    output=$(printf '' | keel_motd_system_block)
    [ -z "$output" ]
}

@test "system_block: a last line without a newline is not lost" {
    output=$(printf 'System information for now\n\n  System load:  0.00' \
        | keel_motd_system_block)
    [[ $output == *"System load:  0.00"* ]]
}

@test "system_block: input that is only blank lines produces nothing to read" {
    output=$(printf '\n\n\n' | keel_motd_system_block)
    [ -z "${output// /}" ]
}

# indenting

@test "indent: every line moves right by the level it is given" {
    output=$(printf 'one\ntwo\n' | keel_motd_indent 2)
    split_output
    [ "${lines[0]}" = "  one" ]
    [ "${lines[1]}" = "  two" ]
}

@test "indent: a blank line stays blank and gains no trailing space" {
    output=$(printf 'one\n\ntwo\n' | keel_motd_indent 4)
    split_output
    [ "${lines[0]}" = "    one" ]
    [ "${lines[1]}" = "" ]
    [ "${lines[2]}" = "    two" ]
}

@test "indent: a level of zero changes nothing" {
    output=$(printf 'one\ntwo\n' | keel_motd_indent 0)
    split_output
    [ "${lines[0]}" = one ]
}

@test "indent: no level is no indent" {
    output=$(printf 'one\n' | keel_motd_indent)
    split_output
    [ "${lines[0]}" = one ]
}

@test "indent: a last line without a newline is indented too" {
    output=$(printf 'one' | keel_motd_indent 2)
    [ "$output" = "  one" ]
}

@test "indent: the indented system block keeps the table under the header" {
    output=$(sysinfo_as_root | keel_motd_system_block | keel_motd_indent 2)
    split_output
    [ "${lines[0]}" = "  System information for Mon Sep 28 02:20:44 2026 (UTC+0000)" ]
    [ "${lines[2]}" = "    System load:  0.00               Memory usage:  54.8%" ]
}

# the backup line

@test "backup_lines: they say the appliance has no backup configured" {
    output=$(keel_motd_backup_lines)
    [[ $output == Backup:* ]]
    [[ $output == *"not configured"* ]]
}

@test "backup_lines: they advertise no service that does not exist" {
    output=$(keel_motd_backup_lines)
    [[ ${output,,} != *tklbam* ]]
    [[ ${output,,} != *turnkey* ]]
    [[ ${output,,} != *hub* ]]
    [[ $output != *http* ]]
}

@test "backup_lines: they say where it will be configured" {
    output=$(keel_motd_backup_lines)
    [[ $output == *confconsole* ]]
}

@test "backup_lines: no line is wider than eighty columns once indented" {
    local line
    while IFS= read -r line; do
        [ "${#line}" -le 78 ]
    done < <(keel_motd_backup_lines)
}

# the confconsole line

@test "confconsole_lines: they name the command and our own documentation" {
    output=$(keel_motd_confconsole_lines)
    [[ $output == *confconsole* ]]
    [[ $output == *"$KEEL_MOTD_DOCS_URL"* ]]
}

@test "confconsole_lines: they name no other project" {
    output=$(keel_motd_confconsole_lines)
    [[ ${output,,} != *turnkeylinux* ]]
    [[ ${output,,} != *turnkey* ]]
}

@test "confconsole_lines: plain text, no terminal escape" {
    output=$(keel_motd_confconsole_lines)
    [[ $output != *$'\e'* ]]
}

# the drop-in directory, at build time

make_dropins() {
    local name
    for name in "$@"; do
        printf '#!/bin/sh\necho %s\n' "$name" > "$SCRATCH/$name"
        chmod +x "$SCRATCH/$name"
    done
}

@test "prune_dir: the TurnKey named drop-ins are removed" {
    make_dropins 00-keel-banner 00-turnkey-sysinfo 01-keel-sysinfo \
        07-check-inithooks 08-keel-confconsole 08-turnkey-confconsole \
        10-nonpersistent-mode 10-uname
    keel_motd_prune_dir "$SCRATCH"
    [ ! -e "$SCRATCH/00-turnkey-sysinfo" ]
    [ ! -e "$SCRATCH/08-turnkey-confconsole" ]
}

@test "prune_dir: the drop-ins that say nothing about a product are kept" {
    make_dropins 00-keel-banner 00-turnkey-sysinfo 01-keel-sysinfo \
        07-check-inithooks 08-keel-confconsole 08-turnkey-confconsole \
        10-nonpersistent-mode 10-uname
    keel_motd_prune_dir "$SCRATCH"
    [ -x "$SCRATCH/07-check-inithooks" ]
    [ -x "$SCRATCH/10-nonpersistent-mode" ]
    [ -x "$SCRATCH/10-uname" ]
}

@test "prune_dir: a directory that has none of them is left alone" {
    make_dropins 00-keel-banner 01-keel-sysinfo 08-keel-confconsole
    run keel_motd_prune_dir "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$(ls "$SCRATCH" | wc -l)" -eq 3 ]
}

@test "prune_dir: a path that is not a directory is refused" {
    run keel_motd_prune_dir "$SCRATCH/absent"
    [ "$status" -eq 1 ]
    [[ $output == *"$SCRATCH/absent"* ]]
}

@test "prune_dir: no argument is refused" {
    run keel_motd_prune_dir
    [ "$status" -eq 1 ]
}

@test "check_dir: a pruned directory with every Keel drop-in passes" {
    make_dropins 00-keel-banner 00-turnkey-sysinfo 01-keel-sysinfo \
        07-check-inithooks 08-keel-confconsole 08-turnkey-confconsole \
        10-nonpersistent-mode 10-uname
    keel_motd_prune_dir "$SCRATCH"
    run keel_motd_check_dir "$SCRATCH"
    [ "$status" -eq 0 ]
    [[ $output == *"no drop-in names another product"* ]]
}

@test "check_dir: a drop-in of another product left behind fails" {
    make_dropins 00-keel-banner 01-keel-sysinfo 08-keel-confconsole \
        09-turnkey-something-new
    run keel_motd_check_dir "$SCRATCH"
    [ "$status" -eq 1 ]
    [[ $output == *09-turnkey-something-new* ]]
}

@test "check_dir: a missing Keel drop-in fails and is named" {
    make_dropins 00-keel-banner 08-keel-confconsole
    run keel_motd_check_dir "$SCRATCH"
    [ "$status" -eq 1 ]
    [[ $output == *01-keel-sysinfo* ]]
}

@test "check_dir: a Keel drop-in that is not executable fails" {
    make_dropins 00-keel-banner 01-keel-sysinfo 08-keel-confconsole
    chmod -x "$SCRATCH/01-keel-sysinfo"
    run keel_motd_check_dir "$SCRATCH"
    [ "$status" -eq 1 ]
    [[ $output == *01-keel-sysinfo* ]]
    [[ $output == *executable* ]]
}

@test "check_dir: a path that is not a directory is refused" {
    run keel_motd_check_dir "$SCRATCH/absent"
    [ "$status" -eq 1 ]
    [[ $output == *"$SCRATCH/absent"* ]]
}

@test "check_dir: no argument is refused" {
    run keel_motd_check_dir
    [ "$status" -eq 1 ]
}

# conf.d/main, the build-time caller

@test "conf.d/main: leaves the directory with Keel's drop-ins and no others" {
    make_dropins 00-keel-banner 00-turnkey-sysinfo 01-keel-sysinfo \
        07-check-inithooks 08-keel-confconsole 08-turnkey-confconsole \
        10-nonpersistent-mode 10-uname
    run env MOTD_DIR="$SCRATCH" \
        KEEL_MOTD_LIB="$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/motd.sh" \
        "$BATS_TEST_DIRNAME/../conf.d/main"
    [ "$status" -eq 0 ]
    [ ! -e "$SCRATCH/00-turnkey-sysinfo" ]
    [ ! -e "$SCRATCH/08-turnkey-confconsole" ]
    [ -x "$SCRATCH/00-keel-banner" ]
    [ -x "$SCRATCH/01-keel-sysinfo" ]
    [ -x "$SCRATCH/08-keel-confconsole" ]
    [ -x "$SCRATCH/07-check-inithooks" ]
    [ -x "$SCRATCH/10-nonpersistent-mode" ]
    [ -x "$SCRATCH/10-uname" ]
}

@test "conf.d/main: fails the build when the overlay did not land" {
    make_dropins 00-turnkey-sysinfo 08-turnkey-confconsole
    run env MOTD_DIR="$SCRATCH" \
        KEEL_MOTD_LIB="$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/motd.sh" \
        "$BATS_TEST_DIRNAME/../conf.d/main"
    [ "$status" -ne 0 ]
    [[ $output == *00-keel-banner* ]]
}

@test "conf.d/main: fails the build when the library is not in the chroot" {
    run env MOTD_DIR="$SCRATCH" KEEL_MOTD_LIB="$SCRATCH/absent.sh" \
        "$BATS_TEST_DIRNAME/../conf.d/main"
    [ "$status" -eq 1 ]
    [[ $output == *"the overlay did not land"* ]]
}

# the library under the caller's own shell options (docs/traps.md, "A bats
# suite cannot see a library that kills its caller"): conf.d/main runs
# under set -e, bats does not.

@test "library: conf.d/main's own shell survives every verdict" {
    make_dropins 00-keel-banner 00-turnkey-sysinfo 01-keel-sysinfo \
        08-keel-confconsole 08-turnkey-confconsole
    cat > "$BATS_TEST_TMPDIR/caller" <<CALLER
#!/bin/bash
set -euo pipefail
. "$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/motd.sh"
keel_motd_prune_dir "$SCRATCH"
keel_motd_check_dir "$SCRATCH"
echo done
CALLER
    chmod +x "$BATS_TEST_TMPDIR/caller"
    run "$BATS_TEST_TMPDIR/caller"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = done ]
}

@test "library: a failing check stops conf.d/main's own shell" {
    make_dropins 00-keel-banner 08-keel-confconsole
    cat > "$BATS_TEST_TMPDIR/caller" <<CALLER
#!/bin/bash
set -euo pipefail
. "$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/motd.sh"
keel_motd_check_dir "$SCRATCH"
echo done
CALLER
    chmod +x "$BATS_TEST_TMPDIR/caller"
    run "$BATS_TEST_TMPDIR/caller"
    [ "$status" -ne 0 ]
    [[ $output != *done* ]]
}
