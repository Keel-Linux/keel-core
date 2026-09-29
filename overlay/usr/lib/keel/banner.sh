#!/bin/bash
# Pure helpers of the Keel console banner (decision 0004: logic apart from
# effect). Nothing here reads the network, the clock, the environment of
# the machine or a path it was not given: the caller collects the facts and
# these functions turn them into text. Sourced by
# /etc/update-motd.d/00-keel-banner and by tests/banner.bats.
#
# The rules of the console surface, which the tests hold in place:
#
#   - plain ASCII, no box drawing, no colour escape, so a serial console, a
#     recovery shell and "ssh -T" all render it;
#   - the mark, then one line naming the appliance and its version, then the
#     addresses, in that order and nothing above the mark;
#   - the mark is centred on the width it is given, as a block: every line
#     moves right by the same indent, so the picture keeps its internal
#     alignment. The title and the addresses stay at column one;
#   - IPv6 first, IPv4 after and only when it is there, and an address that
#     is the host of a URL is bracketed: https://[2001:db8:1::10];
#   - the banner never scrolls the addresses away: the mark is dropped to
#     the small one, and then to nothing, before the text loses a line.
#
# The two mark files are exports of keel-mark.svg of the design system and
# are installed unmodified; a change to the mark is a re-export, never an
# edit of the characters. No size of theirs is written down here: every
# function that needs the rows or the columns of a mark measures the file,
# so a re-export at another size is a change to the design system alone.
# shellcheck disable=SC2034  # KEEL_BANNER_ROWS and _COLS are read by callers

KEEL_BANNER_MARK="${KEEL_BANNER_MARK:-/etc/keel/banner.txt}"
KEEL_BANNER_MARK_SMALL="${KEEL_BANNER_MARK_SMALL:-/etc/keel/banner-small.txt}"

# What a terminal is assumed to be when it does not say: the smallest size
# POSIX guarantees, so an unknown terminal gets the banner that always fits.
KEEL_BANNER_ROWS=24
KEEL_BANNER_COLS=80

# Lines kept free under the banner for the shell prompt, so the last
# address is not the last row of the screen.
KEEL_BANNER_RESERVED_ROWS=1

# keel_banner_version_string FILE...
# The first line of the first file that is readable and not empty. The
# appliance is named from /etc/keel_version, written at build time by
# common (bin/keel-version-files, decision 0014), and from
# /etc/turnkey_version when the layer was built before that file existed:
# the fallback is what keeps a banner correct on a layer older than this
# code. Returns 1 when no file can be read, and then the caller names the
# machine from its hostname.
keel_banner_version_string() {
    local file line
    for file in "$@"; do
        [ -r "$file" ] || continue
        line=""
        read -r line < "$file" || true
        if [ -n "$line" ]; then
            printf '%s\n' "$line"
            return 0
        fi
    done
    return 1
}

# keel_banner_app_name VERSION_STRING
# The appliance name of a version string: core from
# turnkey-core-19.0-trixie-amd64, nginx-php-fastcgi from
# keel-nginx-php-fastcgi-19.0-trixie-amd64. Returns 1 when the string does
# not carry the three trailing fields (version, codename, architecture).
keel_banner_app_name() {
    local rest=${1-}
    rest=${rest#turnkey-}
    rest=${rest#keel-}
    local name=${rest%-*-*-*}
    if [ "$name" = "$rest" ] || [ -z "$name" ]; then
        return 1
    fi
    printf '%s\n' "$name"
}

# keel_banner_version VERSION_STRING
# The version of a version string: 19.0-trixie-amd64 from
# turnkey-core-19.0-trixie-amd64. Returns 1 on the same condition.
keel_banner_version() {
    local rest=${1-}
    local name=${rest%-*-*-*}
    if [ "$name" = "$rest" ] || [ -z "$name" ]; then
        return 1
    fi
    printf '%s\n' "${rest#"$name"-}"
}

# keel_banner_truncate WIDTH TEXT
# TEXT cut to WIDTH columns, ending in "..." when it was cut. A title that
# wraps costs a row the address block was counted on, so it is cut instead.
keel_banner_truncate() {
    local width=$1 text=$2
    if [ "${#text}" -le "$width" ]; then
        printf '%s\n' "$text"
        return 0
    fi
    if [ "$width" -le 3 ]; then
        printf '%s\n' "${text:0:$width}"
        return 0
    fi
    printf '%s...\n' "${text:0:$((width - 3))}"
}

# keel_banner_title NAME VERSION WIDTH
# The one line that names the appliance and its version, on a machine with
# a long hostname too: it is one line at any width.
keel_banner_title() {
    local name=${1-} version=${2-} width=${3:-$KEEL_BANNER_COLS}
    local text
    if [ -n "$name" ] && [ -n "$version" ]; then
        text="$name $version"
    elif [ -n "$name" ]; then
        text=$name
    else
        text=$version
    fi
    keel_banner_truncate "$width" "$text"
}

# keel_banner_is_ipv6 ADDRESS
keel_banner_is_ipv6() {
    [[ ${1-} == *:* ]]
}

# keel_banner_address_lines ADDRESS...
# The address block: web and SSH for each address, IPv6 before IPv4 whatever
# order the arguments came in, IPv4 only when it is present. The IPv6
# address is bracketed where it is the host of a URL and bare where it is
# not, which is the form the identity asks for and the one confconsole
# already prints. With no address at all it says so in words, because a
# blank block would read as a rendering fault.
keel_banner_address_lines() {
    local addr
    local -a six=() four=()
    for addr in "$@"; do
        [ -n "$addr" ] || continue
        if keel_banner_is_ipv6 "$addr"; then
            six+=("$addr")
        else
            four+=("$addr")
        fi
    done
    if [ ${#six[@]} -eq 0 ] && [ ${#four[@]} -eq 0 ]; then
        printf 'no address: the appliance is not reachable yet\n'
        return 0
    fi
    for addr in "${six[@]}"; do
        printf 'IPv6 Web:  https://[%s]\n' "$addr"
        printf 'IPv6 SSH:  root@%s\n' "$addr"
    done
    for addr in "${four[@]}"; do
        printf 'IPv4 Web:  https://%s\n' "$addr"
        printf 'IPv4 SSH:  root@%s\n' "$addr"
    done
}

# keel_banner_mark_size FILE
# "ROWS COLS" of a mark file. Returns 1 when the file cannot be read or is
# empty, so a missing or truncated mark costs the banner its picture and
# nothing else.
keel_banner_mark_size() {
    local file=${1-} line cols=0
    [ -r "$file" ] || return 1
    local -a mark_lines=()
    mapfile -t mark_lines < "$file"
    [ ${#mark_lines[@]} -gt 0 ] || return 1
    for line in "${mark_lines[@]}"; do
        if [ "${#line}" -gt "$cols" ]; then
            cols=${#line}
        fi
    done
    printf '%s %s\n' "${#mark_lines[@]}" "$cols"
}

# keel_banner_choose_mark ROWS COLS BODY_ROWS MARK...
# The first mark of the list that fits a ROWS by COLS terminal once
# BODY_ROWS of text and the reserved rows are kept free below it. Prints its
# path; returns 1 when none fits, and then the caller prints the text alone.
# The marks are given largest first, so a console too short or too narrow
# for the full mark falls back to the small one and a serial line narrower
# than that to no mark at all. Each candidate is measured from its file.
keel_banner_choose_mark() {
    local rows=$1 cols=$2 body=$3
    shift 3
    local mark size mark_rows mark_cols
    for mark in "$@"; do
        size=$(keel_banner_mark_size "$mark") || continue
        mark_rows=${size% *}
        mark_cols=${size#* }
        [ "$mark_cols" -le "$cols" ] || continue
        [ $((mark_rows + body + KEEL_BANNER_RESERVED_ROWS)) -le "$rows" ] \
            || continue
        printf '%s\n' "$mark"
        return 0
    done
    return 1
}

# keel_banner_center_mark WIDTH FILE
# The lines of FILE shifted right by one common indent, so the mark is
# centred on WIDTH as a block and not line by line: padding each line to its
# own centre would pull the picture apart. The indent is half of what WIDTH
# has left over once the widest line is placed, so a mark as wide as WIDTH or
# wider starts at column one and nothing is ever cut. A blank line stays
# blank rather than becoming a line of spaces, and no line ends in
# whitespace: trailing blanks are invisible on the console and survive every
# copy of the block. Returns 1 when the file cannot be measured, the
# condition keel_banner_mark_size reports.
keel_banner_center_mark() {
    local width=${1-} file=${2-} size indent pad="" line
    size=$(keel_banner_mark_size "$file") || return 1
    indent=$(((width - ${size#* }) / 2))
    if [ "$indent" -gt 0 ]; then
        printf -v pad '%*s' "$indent" ''
    fi
    local -a mark_lines=()
    mapfile -t mark_lines < "$file"
    for line in "${mark_lines[@]}"; do
        # ${line##*[![:space:]]} is the run of blanks that ends the line, and
        # the whole line when it holds nothing else.
        line=${line%"${line##*[![:space:]]}"}
        if [ -z "$line" ]; then
            printf '\n'
            continue
        fi
        printf '%s%s\n' "$pad" "$line"
    done
}

# keel_banner_render ROWS COLS NAME VERSION [ADDRESS...]
# The whole block, from the mark files named by KEEL_BANNER_MARK and
# KEEL_BANNER_MARK_SMALL. Three rows of text go with the address block: the
# blank row under the mark, the title, and the blank row under the title.
# The mark is centred on COLS, the title and the addresses are not.
keel_banner_render() {
    local rows=$1 cols=$2 name=$3 version=$4
    shift 4
    local -a address_lines=()
    mapfile -t address_lines < <(keel_banner_address_lines "$@")
    local body=$((3 + ${#address_lines[@]}))
    local marks=("$KEEL_BANNER_MARK" "$KEEL_BANNER_MARK_SMALL")
    local mark
    if mark=$(keel_banner_choose_mark "$rows" "$cols" "$body" "${marks[@]}")
    then
        keel_banner_center_mark "$cols" "$mark"
        printf '\n'
    fi
    keel_banner_title "$name" "$version" "$cols"
    printf '\n'
    printf '%s\n' "${address_lines[@]}"
}

# keel_banner_pick_ipv6
# stdin: the output of "ip -6 addr show IFACE scope global", the probe
# confconsole (ifutil._list_ipv6_global) and keel inspect
# (keel.spec.runtime.live_ipv6) both read. Prints the address that stays
# reachable, in confconsole's order: a static address before a SLAAC or
# DHCPv6 one, a privacy address last. Returns 1 when there is none.
keel_banner_pick_ipv6() {
    local keyword value rest rank best="" best_rank=9
    while read -r keyword value rest; do
        [ "$keyword" = inet6 ] || continue
        rank=0
        case " $rest " in
            *" temporary "*) rank=2 ;;
            *" dynamic "*) rank=1 ;;
        esac
        if [ "$rank" -lt "$best_rank" ]; then
            best=${value%%/*}
            best_rank=$rank
        fi
    done
    [ -n "$best" ] || return 1
    printf '%s\n' "$best"
}

# keel_banner_pick_ipv4
# stdin: the output of "ip -4 addr show IFACE scope global". Prints the
# first address; returns 1 when the appliance has no IPv4, which is the
# normal case and not an error.
keel_banner_pick_ipv4() {
    local keyword value _
    while read -r keyword value _; do
        [ "$keyword" = inet ] || continue
        printf '%s\n' "${value%%/*}"
        return 0
    done
    return 1
}
