#!/bin/bash
# The parts of the message of the day Keel writes, apart from the mark:
# the system information block, what the appliance says about backup, and
# the line pointing at the configuration console. Pure functions (decision
# 0004: logic apart from effect); nothing here reads the network, the
# clock, the environment of the machine or a path it was not given, and
# the two functions that touch a directory touch only the one they are
# given. Sourced by /etc/update-motd.d/01-keel-sysinfo and
# /etc/update-motd.d/08-keel-confconsole at every login, by conf.d/main of
# the appliance recipe at build time, and by tests/motd.bats.
#
# The rules of the console surface are banner.sh's and hold here too:
# plain ASCII, no box drawing and no colour escape, so a serial console, a
# recovery shell and "ssh -T" all render it. The confconsole line
# upstream wrote used tput to embolden the command; this one does not.
#
# Why these files exist at all (issue #6). common (conf/turnkey.d/motd)
# writes /etc/update-motd.d/00-turnkey-sysinfo, which execs
# turnkey-sysinfo's own motd script: it welcomes the operator a second
# time, to a distribution this image is not, and it ends with a block
# telling them to run tklbam-init against a Hub this project does not use
# (decision 0002). The useful half of it, the system information, comes
# from the turnkey-sysinfo command and is kept; the two halves are
# separated here rather than filtered by the words the backup client
# happens to print today.

# The command that prints the system information. It is called by the name
# it has today; a Keel name for it is a separate decision.
KEEL_MOTD_SYSINFO_COMMAND="${KEEL_MOTD_SYSINFO_COMMAND:-turnkey-sysinfo}"

# How far the block sits from the left margin, the indent upstream used.
# shellcheck disable=SC2034  # KEEL_MOTD_INDENT is read by the drop-in
KEEL_MOTD_INDENT=2

# Our own documentation of the configuration console.
KEEL_MOTD_DOCS_URL=https://github.com/keel-linux/confconsole

# The drop-ins common writes that speak for another product, removed by
# conf.d/main once this repository's overlay has landed its own.
KEEL_MOTD_TURNKEY_DROPINS="00-turnkey-sysinfo 08-turnkey-confconsole"

# The drop-ins this repository's overlay installs. conf.d/main requires
# every one of them to be there and executable before it calls the build
# good: an overlay that did not land would otherwise leave an appliance
# with no banner at all and nothing would say so.
KEEL_MOTD_KEEL_DROPINS="00-keel-banner 01-keel-sysinfo 08-keel-confconsole"

# Anything in the drop-in directory whose name matches this belongs to
# another product and has no place in a Keel login.
KEEL_MOTD_FOREIGN_NAME='turnkey'

# keel_motd_system_block
# stdin: everything the system information command printed. Prints the
# header line and the table under it, and stops at the blank line that
# ends the table.
#
# The cut is by shape and not by words. Run as root the command appends
# the backup client's status, today TKLBAM's, tomorrow whatever replaces
# it; a filter written against the words TKLBAM prints would pass the next
# tail through silently, which is the defect this whole change is about.
# The shape is fixed by the command itself: one header, one blank line,
# the table, and any tail after a second blank line.
keel_motd_system_block() {
    local line blanks=0
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            blanks=$((blanks + 1))
            if [ "$blanks" -ge 2 ]; then
                return 0
            fi
            printf '\n'
            continue
        fi
        printf '%s\n' "$line"
    done
    return 0
}

# keel_motd_indent [LEVEL]
# stdin: any block. Prints it shifted right by LEVEL columns, leaving a
# blank line blank rather than making it a line of spaces: trailing blanks
# are invisible on a console and survive every copy of the block.
keel_motd_indent() {
    local level=${1:-0} pad="" line
    if [ "$level" -gt 0 ]; then
        printf -v pad '%*s' "$level" ''
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            printf '\n'
        else
            printf '%s%s\n' "$pad" "$line"
        fi
    done
}

# keel_motd_backup_lines
# What the appliance says about backup, in the place the backup client's
# status used to occupy (decision 0014). It says one true thing and
# advertises nothing: there is no backup service in Keel yet, decision
# 0002 defers it, and an operator told to run a command against a service
# this project does not host is being sent somewhere we do not go.
keel_motd_backup_lines() {
    cat <<'LINES'
Backup:  not configured. Keel has no backup service yet; when one
         arrives it is configured from confconsole.
LINES
}

# keel_motd_confconsole_lines
# The configuration console and where its documentation is. Upstream's
# line pointed at turnkeylinux.org, which documents another product's
# console; this one points at ours.
keel_motd_confconsole_lines() {
    printf '\n'
    printf '    For advanced configuration run:  confconsole\n'
    printf '\n'
    printf '  For more info see: %s\n' "$KEEL_MOTD_DOCS_URL"
    printf '\n'
}

# keel_motd_prune_dir DIR
# Build time, from conf.d/main: removes the drop-ins of another product
# from DIR. It runs after the overlay has landed Keel's own, which is the
# order fab applies them in (the product overlay and then the product conf
# scripts, both after every common conf script), so the directory is never
# left without a banner.
keel_motd_prune_dir() {
    local dir=${1-} name
    if [ ! -d "$dir" ]; then
        echo "keel motd: '$dir' is not a directory" >&2
        return 1
    fi
    for name in $KEEL_MOTD_TURNKEY_DROPINS; do
        rm -f "$dir/$name"
    done
    return 0
}

# keel_motd_check_dir DIR
# Build time, from conf.d/main: the verdict on what the drop-in directory
# was left holding. Every Keel drop-in present and executable, and no
# entry named after another product. This asserts the arrangement, not the
# text a login produces; that is the boot test's job (docs/traps.md,
# "Asserting the configuration is not asserting the behaviour").
keel_motd_check_dir() {
    local dir=${1-} name path failed=0
    if [ ! -d "$dir" ]; then
        echo "keel motd: '$dir' is not a directory" >&2
        return 1
    fi
    for name in $KEEL_MOTD_KEEL_DROPINS; do
        path=$dir/$name
        if [ ! -f "$path" ]; then
            echo "keel motd: $path is missing; did the overlay land?" >&2
            failed=1
        elif [ ! -x "$path" ]; then
            echo "keel motd: $path is not executable" >&2
            failed=1
        fi
    done
    for path in "$dir"/*; do
        [ -e "$path" ] || continue
        name=$(basename "$path")
        case "$name" in
            *"$KEEL_MOTD_FOREIGN_NAME"*)
                echo "keel motd: $path is another product's drop-in" >&2
                failed=1
                ;;
        esac
    done
    if [ "$failed" -ne 0 ]; then
        return 1
    fi
    echo "keel motd: $dir has every Keel drop-in and no drop-in names another product"
    return 0
}
