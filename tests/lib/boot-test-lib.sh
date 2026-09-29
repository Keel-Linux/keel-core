#!/bin/bash
# Pure helpers of tests/boot-test.sh (decision 0004: logic apart from
# effect). Nothing here starts a container, writes outside a path it is
# given or opens a socket. The two functions that run a command, bt_now
# and bt_container_ipv6, take it from the environment or from PATH so a
# test can replace it. Sourced by boot-test.sh and by tests/boot-test.bats.
# shellcheck disable=SC2034  # the BT_* variables are read by the caller

BT_DEFAULT_TIMEOUT=900
BT_DEFAULT_INTERVAL=5
BT_DEFAULT_BRIDGE=br0
BT_DEFAULT_LAYERS_DIR=/mnt/builds/layers
BT_DEFAULT_CACHE_DIR=/var/cache/keel/layers
BT_DEFAULT_LXC_PATH=/var/lib/lxc
BT_SSH_PORT=22
BT_PASSWORD_LENGTH=24
BT_RANDOM_BYTES=1024
# Where the first boot reads the instance description. inithooks reads
# etc/inithooks.yaml (hook 00declarative), keel reads etc/keel/instance.yaml;
# the final name is a maintainer decision (brief section 11), so the test
# installs the same file at both until then.
BT_SPEC_PATHS="etc/keel/instance.yaml etc/inithooks.yaml"

bt_usage() {
    cat <<USAGE
usage: tests/boot-test.sh APPLIANCE [options]

Assembles the layer chain of APPLIANCE (core, lamp, ...) into an LXC
rootfs, boots it headless from tests/instance.yaml, waits for the first
boot to finish and checks that keel diff reports no drift. Root only.

options:
  --timeout SECONDS     give up after this long per wait (default $BT_DEFAULT_TIMEOUT)
  --interval SECONDS    poll interval (default $BT_DEFAULT_INTERVAL)
  --bridge NAME         bridge the container joins (default $BT_DEFAULT_BRIDGE)
  --layers-dir DIR|URL  where the layers are published: a directory, or an
                        http(s) URL such as https://mirror.keellinux.org/layers
                        (default $BT_DEFAULT_LAYERS_DIR)
  --cache-dir DIR       keel layer cache (default $BT_DEFAULT_CACHE_DIR)
  --lxc-path DIR        lxcpath for the test container (default $BT_DEFAULT_LXC_PATH)
  --name NAME           container name (default keel-APPLIANCE-boot-test)
  --spec FILE           instance spec (default tests/instance.yaml)
  --keep                leave the container running for inspection
  -h, --help            this text
USAGE
}

bt_is_positive_int() {
    [[ ${1-} =~ ^[1-9][0-9]*$ ]]
}

bt_is_appliance_name() {
    # The name bt-layer and the workflow use: no keel- prefix, lower case.
    [[ ${1-} =~ ^[a-z][a-z0-9-]*$ ]] && [[ $1 != keel-* ]]
}

bt_container_name() {
    printf 'keel-%s-boot-test\n' "$1"
}

bt_is_container_name() {
    # What LXC accepts and what the CI cleanup command allows: lower case
    # letters, digits, dot and dash, starting with a letter or a digit.
    [[ ${1-} =~ ^[a-z0-9][a-z0-9.-]*$ ]]
}

# Sets BT_APPLIANCE, BT_TIMEOUT, BT_INTERVAL, BT_BRIDGE, BT_LAYERS_DIR,
# BT_CACHE_DIR, BT_LXC_PATH, BT_SPEC, BT_KEEP, BT_NAME and BT_ROOTFS.
# Returns 0 when parsed, 2 after printing the usage, 1 on a bad argument
# (message on stderr).
bt_parse_args() {
    BT_APPLIANCE=""
    BT_TIMEOUT=$BT_DEFAULT_TIMEOUT
    BT_INTERVAL=$BT_DEFAULT_INTERVAL
    BT_BRIDGE=$BT_DEFAULT_BRIDGE
    BT_LAYERS_DIR=$BT_DEFAULT_LAYERS_DIR
    BT_CACHE_DIR=$BT_DEFAULT_CACHE_DIR
    BT_LXC_PATH=$BT_DEFAULT_LXC_PATH
    BT_NAME=""
    BT_SPEC=""
    BT_KEEP=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout|--interval)
                bt_is_positive_int "${2-}" || {
                    echo "boot-test: $1 needs a positive number of seconds" >&2
                    return 1
                }
                [ "$1" = --timeout ] && BT_TIMEOUT=$2 || BT_INTERVAL=$2
                shift
                ;;
            --bridge|--layers-dir|--cache-dir|--lxc-path|--name|--spec)
                [ -n "${2-}" ] || {
                    echo "boot-test: $1 needs a value" >&2
                    return 1
                }
                case "$1" in
                    --bridge) BT_BRIDGE=$2 ;;
                    --layers-dir) BT_LAYERS_DIR=$2 ;;
                    --cache-dir) BT_CACHE_DIR=$2 ;;
                    --lxc-path) BT_LXC_PATH=$2 ;;
                    --name) BT_NAME=$2 ;;
                    --spec) BT_SPEC=$2 ;;
                esac
                shift
                ;;
            --keep) BT_KEEP=1 ;;
            -h|--help)
                bt_usage
                return 2
                ;;
            -*)
                echo "boot-test: unknown option $1" >&2
                return 1
                ;;
            *)
                if [ -n "$BT_APPLIANCE" ]; then
                    echo "boot-test: one appliance at a time ($BT_APPLIANCE, $1)" >&2
                    return 1
                fi
                BT_APPLIANCE=$1
                ;;
        esac
        shift
    done
    if [ -z "$BT_APPLIANCE" ]; then
        echo "boot-test: APPLIANCE is required (core, lamp, ...)" >&2
        return 1
    fi
    if ! bt_is_appliance_name "$BT_APPLIANCE"; then
        echo "boot-test: '$BT_APPLIANCE' is not an appliance name (lower case, no keel- prefix)" >&2
        return 1
    fi
    BT_NAME=${BT_NAME:-$(bt_container_name "$BT_APPLIANCE")}
    if ! bt_is_container_name "$BT_NAME"; then
        echo "boot-test: '$BT_NAME' is not a container name (lower case, digits, dot, dash)" >&2
        return 1
    fi
    BT_ROOTFS=$BT_LXC_PATH/$BT_NAME/rootfs
    return 0
}

bt_is_global_ipv6() {
    # Global unicast, which includes ULA (fc00::/7); not link local
    # (fe80::/10), loopback or multicast. IPv4 has no colon.
    local addr=${1,,}
    [[ $addr == *:* ]] || return 1
    [[ $addr == fe[89ab]?:* ]] && return 1
    [[ $addr == ::1 ]] && return 1
    [[ $addr == ff* ]] && return 1
    return 0
}

bt_global_ipv6() {
    # stdin: the output of lxc-info -i ("IP:  ADDRESS" per line). Prints
    # the first global IPv6 address; returns 1 when there is none yet.
    local label addr _
    while read -r label addr _; do
        [ "$label" = "IP:" ] || continue
        if bt_is_global_ipv6 "$addr"; then
            printf '%s\n' "$addr"
            return 0
        fi
    done
    return 1
}

bt_global_ipv6_all() {
    # stdin: the output of lxc-info -i. Prints every global IPv6 address,
    # in the order given; returns 1 when there is none. A machine can
    # hold several (a SLAAC address and a privacy one, a static and a
    # dynamic), and which of them a program shows is that program's
    # choice: the banner picks static before dynamic and privacy last.
    # So a check that the login names the machine's address has to hold
    # all of them, not the one this function happened to see first.
    local label addr _ found=1
    while read -r label addr _; do
        [ "$label" = "IP:" ] || continue
        if bt_is_global_ipv6 "$addr"; then
            printf '%s\n' "$addr"
            found=0
        fi
    done
    return "$found"
}

bt_container_ipv6() {
    # bt_container_ipv6 NAME LXCPATH: the container's first global IPv6.
    lxc-info -P "$2" -n "$1" -i 2>/dev/null | bt_global_ipv6
}

bt_container_ipv6_all() {
    # bt_container_ipv6_all NAME LXCPATH: every global IPv6 it holds.
    lxc-info -P "$2" -n "$1" -i 2>/dev/null | bt_global_ipv6_all
}

bt_now() {
    ${BT_CLOCK:-date +%s}
}

bt_deadline_passed() {
    # bt_deadline_passed START TIMEOUT NOW
    [ $(( $3 - $1 )) -ge "$2" ]
}

bt_wait_for() {
    # bt_wait_for TIMEOUT INTERVAL DESCRIPTION COMMAND [ARGS...]
    # Runs COMMAND until it succeeds; returns 1 once TIMEOUT seconds passed.
    local timeout=$1 interval=$2 what=$3 start now
    shift 3
    start=$(bt_now)
    until "$@"; do
        now=$(bt_now)
        if bt_deadline_passed "$start" "$timeout" "$now"; then
            echo "boot-test: timeout after ${timeout}s waiting for $what" >&2
            return 1
        fi
        ${BT_SLEEP:-sleep} "$interval"
    done
}

bt_is_ssh_banner() {
    [[ ${1-} == SSH-2.0-* ]]
}

bt_firstboot_done_in() {
    # bt_firstboot_done_in FILE: FILE is the rootfs copy of
    # /etc/default/inithooks; 98finalize sets RUN_FIRSTBOOT=false at the end.
    [ -r "$1" ] && grep -q '^RUN_FIRSTBOOT=false' "$1"
}

bt_lxc_config() {
    # bt_lxc_config NAME ROOTFS BRIDGE: an LXC config for a plain rootfs
    # directory on a bridge; the address comes from the bridge (SLAAC or
    # DHCPv6), the spec declares managed_by: host.
    cat <<CONFIG
lxc.uts.name = $1
lxc.rootfs.path = dir:$2
lxc.include = /usr/share/lxc/config/common.conf
lxc.arch = amd64
lxc.net.0.type = veth
lxc.net.0.link = $3
lxc.net.0.name = eth0
lxc.net.0.flags = up
lxc.start.auto = 0
CONFIG
}

bt_spec_targets() {
    # bt_spec_targets ROOTFS: the paths the spec is installed at.
    local relative
    for relative in $BT_SPEC_PATHS; do
        printf '%s/%s\n' "$1" "$relative"
    done
}

bt_spec_in_rootfs() {
    # bt_spec_in_rootfs SPEC ROOTFS: the spec with its secret references
    # pointed inside ROOTFS, printed on stdout. `keel spec apply` runs on
    # the host and resolves a secret path against the host, so the copy it
    # reads has to name the files this test wrote into the container.
    sed -E "s#^([[:space:]]*file:[[:space:]]*)(/etc/keel/secrets/)#\1$2\2#" "$1"
}

bt_random_password() {
    # A fixed block is read first and filtered afterwards. The other way
    # round, "tr < source | head -c N", leaves tr killed by SIGPIPE when
    # head has its N characters, and the set -o pipefail of boot-test.sh
    # turns that into exit 141 before the container is ever started.
    local pool source=${BT_RANDOM_SOURCE:-/dev/urandom}
    pool=$(head -c "$BT_RANDOM_BYTES" "$source" | LC_ALL=C tr -dc 'A-Za-z0-9')
    if [ "${#pool}" -lt "$BT_PASSWORD_LENGTH" ]; then
        echo "boot-test: $source gave only ${#pool} usable characters" >&2
        return 1
    fi
    printf '%s\n' "${pool:0:BT_PASSWORD_LENGTH}"
}

# The drop-in directory pam_motd runs at an interactive login, and the
# way to render it: run-parts is what pam_motd does with it, so this is
# the login the operator gets and not a file read off the disk.
BT_MOTD_DIR=/etc/update-motd.d
# A line that names a distribution to whoever just logged in: the welcome.
# There must be exactly one and it must be ours (issue #7).
BT_MOTD_GREETINGS=("Welcome to " "Keel Linux" "Keel GNU/Linux" "TurnKey GNU/Linux")
BT_MOTD_KEEL="Keel"
# The facts the block gives on every machine, whatever it is attached to:
# losing any of them would be a regression.
BT_MOTD_FIELDS=("System load:" "Memory usage:" "Processes:" "Swap usage:" "Usage of /:")
# The address row is the one line of the block that depends on the
# machine, so it is checked apart from the five above and by shape rather
# than by family. The command reports an address per interface from
# netinfo.InterfaceInfo.address, which is SIOCGIFADDR on an AF_INET
# socket: IPv4 only. On an appliance with no IPv4, which is what
# tests/instance.yaml declares and what this distribution is built for,
# it prints "Networking not configured" instead, and requiring the words
# "IP address" would fail a machine that is entirely correct. Either row
# means the block still reports on the network; that the operator is
# given an address to reach the machine by is asserted separately, from
# the address the container actually answers on.
BT_MOTD_NETWORK_ROWS=("IP address for" "Networking not configured")
# What a Keel login must not say: the distribution this image is not, and
# the backup service it does not have (decisions 0002 and 0014).
BT_MOTD_FORBIDDEN=(turnkey tklbam)

bt_motd_greetings() {
    # bt_motd_greetings TEXT: the lines of a rendered motd that welcome
    # the operator to a distribution, one per line.
    local text=${1-} line phrase
    while IFS= read -r line; do
        for phrase in "${BT_MOTD_GREETINGS[@]}"; do
            case $line in
                *"$phrase"*)
                    printf '%s\n' "$line"
                    break
                    ;;
            esac
        done
    done <<< "$text"
}

bt_motd_missing_fields() {
    # bt_motd_missing_fields TEXT: the system information labels TEXT does
    # not carry, one per line; nothing when it carries them all.
    local text=${1-} field
    for field in "${BT_MOTD_FIELDS[@]}"; do
        case $text in
            *"$field"*) continue ;;
        esac
        printf '%s\n' "$field"
    done
}

bt_motd_network_row() {
    # bt_motd_network_row TEXT: true when the system information block
    # still reports on the network, in either of the two shapes the
    # command can print.
    local text=${1-} row
    for row in "${BT_MOTD_NETWORK_ROWS[@]}"; do
        case $text in
            *"$row"*) return 0 ;;
        esac
    done
    return 1
}

bt_motd_forbidden_words() {
    # bt_motd_forbidden_words TEXT: the words TEXT says and must not,
    # matched without regard to case so turnkeylinux.org counts.
    local text=${1-} word
    text=${text,,}
    for word in "${BT_MOTD_FORBIDDEN[@]}"; do
        case $text in
            *"$word"*) printf '%s\n' "$word" ;;
        esac
    done
}

bt_motd_verdict() {
    # bt_motd_verdict TEXT [ADDRESS]: the verdicts on what an interactive
    # login prints. Prints one line per verdict and returns 1 when any of
    # them failed. This is the assertion that closes issue #7, and it is
    # behavioural: TEXT is what the drop-in chain produced in the running
    # container, not the content of a file. ADDRESS..., when given, are
    # the addresses the container answers on, and the login has to carry
    # one of them: that is what makes "the operator is told how to reach
    # this machine" an assertion about the machine rather than about a
    # word. Several, because a machine can hold several and which one the
    # banner shows is the banner's choice.
    local text=${1-} failed=0 greetings count missing forbidden line
    local address found_address=""
    shift || true
    local -a addresses=("$@")
    if [ -z "${text//[[:space:]]/}" ]; then
        echo "motd: the login printed nothing" >&2
        return 1
    fi
    greetings=$(bt_motd_greetings "$text")
    count=0
    if [ -n "$greetings" ]; then
        count=$(printf '%s\n' "$greetings" | wc -l)
    fi
    if [ "$count" -eq 1 ]; then
        echo "motd: one welcome: $greetings"
    else
        echo "motd: $count welcomes, there must be one" >&2
        if [ -n "$greetings" ]; then
            while IFS= read -r line; do
                printf '  %s\n' "$line" >&2
            done <<< "$greetings"
        fi
        failed=1
    fi
    case $greetings in
        *"$BT_MOTD_KEEL"*)
            echo "motd: the welcome names Keel"
            ;;
        *)
            echo "motd: the welcome does not name Keel" >&2
            failed=1
            ;;
    esac
    missing=$(bt_motd_missing_fields "$text")
    if [ -z "$missing" ]; then
        echo "motd: the system information block carries every field"
    else
        echo "motd: the system information block lost fields:" >&2
        while IFS= read -r line; do
            printf '  %s\n' "$line" >&2
        done <<< "$missing"
        failed=1
    fi
    if bt_motd_network_row "$text"; then
        echo "motd: the system information block still reports on the network"
    else
        echo "motd: the system information block reports no address at all" >&2
        failed=1
    fi
    if [ ${#addresses[@]} -gt 0 ]; then
        for address in "${addresses[@]}"; do
            case $text in
                *"$address"*)
                    found_address=$address
                    break
                    ;;
            esac
        done
        if [ -n "$found_address" ]; then
            echo "motd: the login says the machine is reachable at $found_address"
        else
            echo "motd: the login carries none of the addresses this machine" \
                 "answers on:" >&2
            for address in "${addresses[@]}"; do
                printf '  %s\n' "$address" >&2
            done
            failed=1
        fi
    fi
    forbidden=$(bt_motd_forbidden_words "$text")
    if [ -z "$forbidden" ]; then
        echo "motd: the login names no other distribution and no service we do not have"
    else
        echo "motd: the login still says:" >&2
        while IFS= read -r line; do
            printf '  %s\n' "$line" >&2
        done <<< "$forbidden"
        failed=1
    fi
    if [ "$failed" -ne 0 ]; then
        echo "motd: this login is the one issue #7 describes, on a layer" \
             "that carries the login change, so the change is not doing" \
             "its job: read $BT_MOTD_DIR in this layer." >&2
        return 1
    fi
    return 0
}

bt_diff_verdict() {
    # bt_diff_verdict CODE: interprets the exit code of keel diff
    # (docs/diff.md of the keel repository). 0 and 13 mean no drift.
    case "$1" in
        0) echo "keel diff: no drift"; return 0 ;;
        13) echo "keel diff: no drift, but a declared field could not be observed offline (see the report above)"; return 0 ;;
        14) echo "keel diff: drift found" >&2; return 1 ;;
        2|3) echo "keel diff: the spec is unreadable or invalid (exit $1)" >&2; return 1 ;;
        *) echo "keel diff: failed with exit $1" >&2; return 1 ;;
    esac
}

# The file only a layer built with the login change carries. conf.d/main
# refuses to build a layer without it, and the login drop-ins source it,
# so its absence in a booted rootfs means the layer was built from a commit
# before that change, and never that the change regressed.
BT_MOTD_LIB=/usr/lib/keel/motd.sh

bt_login_applies() {
    # bt_login_applies ROOTFS: whether the login check can be asked of the
    # layer booted from ROOTFS. The check this job runs boots the layer the
    # mirror publishes, not the branch under test (the check is called
    # boot-published-layer for that reason), so a layer built before the
    # login change cannot pass it and says nothing about the change. Returns
    # 1, naming the cause and the remedy, for such a layer; 0 otherwise.
    if [ -f "$1$BT_MOTD_LIB" ]; then
        return 0
    fi
    echo "motd: the booted layer has no $BT_MOTD_LIB, so it was built before" \
         "the login change (conf.d/main refuses to build a layer without" \
         "it). The login cannot be checked on it: rebuild and publish the" \
         "layer, and this check applies from then on."
    return 1
}

bt_checks_verdict() {
    # bt_checks_verdict NAME:CODE ...: the verdict of the whole run.
    # Returns 1 when any check failed, after naming every one that did.
    # The boot test collects its checks and calls this at the end rather
    # than exiting at the first failure, so one red assertion never hides
    # the result of another. CODE "na" is a check that did not apply to
    # the layer that booted: it is named, it does not fail the run, and it
    # does not count as a pass, so a run in which nothing applied fails.
    local check name code failed=0 total=0
    for check in "$@"; do
        name=${check%:*}
        code=${check##*:}
        if [ "$code" = na ]; then
            echo "boot-test: the $name check did not apply to this layer (see above)"
            continue
        fi
        total=$((total + 1))
        if [ "$code" -ne 0 ]; then
            echo "boot-test: the $name check failed (exit $code)" >&2
            failed=1
        fi
    done
    if [ "$total" -eq 0 ]; then
        echo "boot-test: no check was run, which is not a pass" >&2
        return 1
    fi
    if [ "$failed" -ne 0 ]; then
        return 1
    fi
    if [ "$total" -eq 1 ]; then
        echo "boot-test: 1 check passed"
    else
        echo "boot-test: $total checks passed"
    fi
    return 0
}
