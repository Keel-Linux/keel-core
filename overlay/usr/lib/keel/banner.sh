#!/bin/bash
# Pure helpers of the Keel console banner (decision 0004: logic apart from
# effect). Nothing here reads the network, the clock, the environment of
# the machine or a path it was not given: the caller collects the facts and
# these functions turn them into text. Sourced by
# /etc/update-motd.d/00-keel-banner and by tests/banner.bats.
#
# The rules of the console surface, which the tests hold in place:
#
#   - no colour escape, and plain ASCII unless the locale says UTF-8: the
#     maintainer's art comes in two character sets, block and shade
#     characters for a UTF-8 terminal and "#" for any other, so a serial
#     console, a recovery shell and "ssh -T" in the C locale still render
#     it;
#   - the mark, then one line naming the appliance and its version, then the
#     addresses, in that order and nothing above the mark;
#   - the mark is centred on the width it is given, as a block: every line
#     moves right by the same indent, so the picture keeps its internal
#     alignment. The title and the addresses stay at column one;
#   - IPv6 first, IPv4 after and only when it is there, and an address that
#     is the host of a URL is bracketed: https://[2001:db8:1::10];
#   - the banner never scrolls the addresses away: the largest mark that
#     fits is taken, in the order wide, full, small, and none at all before
#     the text loses a line.
#
# The mark files are the maintainer's console art, installed as he drew it
# in /etc/keel: banner-wide.txt (the mark with the KEEL LINUX lettering,
# the tagline and KEELLINUX.ORG, UTF-8 only), banner-utf8.txt and
# banner.txt (the full mark), banner-small-utf8.txt and banner-small.txt
# (the small one). A change to the art is a new drawing, never an edit of
# the characters here. No size of theirs is written down either: every
# function that needs the rows or the columns of a mark measures the file,
# so a redrawing at another size needs no change to this code.
# shellcheck disable=SC2034  # KEEL_BANNER_ROWS and _COLS are read by callers

KEEL_BANNER_DIR="${KEEL_BANNER_DIR:-/etc/keel}"

# The two ladders, largest first. There is no ASCII wide mark: the
# lettering is drawn in block and shade characters only.
KEEL_BANNER_MARKS_UTF8=(banner-wide.txt banner-utf8.txt banner-small-utf8.txt)
KEEL_BANNER_MARKS_ASCII=(banner.txt banner-small.txt)

# What a terminal is assumed to be when it does not say: the smallest size
# POSIX guarantees, so an unknown terminal gets the banner that always fits.
KEEL_BANNER_ROWS=24
KEEL_BANNER_COLS=80

# Lines kept free under the banner for the shell prompt, so the last
# address is not the last row of the screen.
KEEL_BANNER_RESERVED_ROWS=1

# keel_banner_marks CHARSET
# The paths of the ladder for CHARSET, largest first, one per line: the
# UTF-8 ladder for utf8, the ASCII ladder for anything else.
keel_banner_marks() {
    local name
    local -a names=("${KEEL_BANNER_MARKS_ASCII[@]}")
    if [ "${1-}" = utf8 ]; then
        names=("${KEEL_BANNER_MARKS_UTF8[@]}")
    fi
    for name in "${names[@]}"; do
        printf '%s/%s\n' "$KEEL_BANNER_DIR" "$name"
    done
}

# keel_banner_effective_locale LC_ALL LC_CTYPE LANG
# The locale that decides the character set: LC_ALL, then LC_CTYPE, then
# LANG, the first that is set and not empty. Prints nothing when none is.
keel_banner_effective_locale() {
    local value
    for value in "${1-}" "${2-}" "${3-}"; do
        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    done
}

# keel_banner_charset LOCALE
# utf8 when LOCALE names the UTF-8 codeset (C.UTF-8, en_US.utf8,
# de_DE.UTF-8@euro), ascii otherwise, nothing at all included: the C
# locale, which is what an unset locale is, has no characters past 127.
keel_banner_charset() {
    local value=${1-}
    case "${value,,}" in
        *.utf-8 | *.utf-8@* | *.utf8 | *.utf8@*) printf 'utf8\n' ;;
        *) printf 'ascii\n' ;;
    esac
}

# keel_banner_locale_of_file
# stdin: /etc/default/locale, the system locale update-locale writes, in
# its KEY=VALUE form with optional quotes. Prints the effective locale it
# sets, with the precedence of keel_banner_effective_locale, or nothing.
keel_banner_locale_of_file() {
    local line key value lc_all="" lc_ctype="" lang=""
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line#"${line%%[![:space:]]*}"}
        key=${line%%=*}
        [ "$key" != "$line" ] || continue
        value=${line#*=}
        value=${value%"${value##*[![:space:]]}"}
        value=${value#[\"\']}
        value=${value%[\"\']}
        case "$key" in
            LC_ALL) lc_all=$value ;;
            LC_CTYPE) lc_ctype=$value ;;
            LANG) lang=$value ;;
        esac
    done
    keel_banner_effective_locale "$lc_all" "$lc_ctype" "$lang"
}

# keel_banner_is_size VALUE
# Whether VALUE is a positive whole number of rows or columns.
keel_banner_is_size() {
    [[ ${1-} =~ ^[0-9]+$ ]] && [ "$((10#$1))" -gt 0 ]
}

# keel_banner_terminal_size LINES COLUMNS STTY_SIZE
# "ROWS COLS" of the terminal: LINES and COLUMNS when the caller has them,
# else what "stty size" printed ("ROWS COLS"), else the 24 by 80 every
# terminal guarantees. Each dimension falls back on its own, and anything
# that is not a positive number is not a size.
keel_banner_terminal_size() {
    local lines=${1-} columns=${2-} stty=${3-}
    local stty_rows="" stty_cols="" rows=$KEEL_BANNER_ROWS
    local cols=$KEEL_BANNER_COLS
    read -r stty_rows stty_cols _ <<< "$stty"
    if keel_banner_is_size "$lines"; then
        rows=$((10#$lines))
    elif keel_banner_is_size "$stty_rows"; then
        rows=$((10#$stty_rows))
    fi
    if keel_banner_is_size "$columns"; then
        cols=$((10#$columns))
    elif keel_banner_is_size "$stty_cols"; then
        cols=$((10#$stty_cols))
    fi
    printf '%s %s\n' "$rows" "$cols"
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
# nothing else. A column is a character, whatever the caller's locale: the
# UTF-8 marks are counted in C.UTF-8, which glibc carries built in, so a
# block character is one column and not the three bytes the C locale sees.
# Every character of the art is one column wide.
keel_banner_mark_size() {
    local LC_ALL=C.UTF-8
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

# keel_banner_render ROWS COLS CHARSET NAME VERSION [ADDRESS...]
# The whole block, the mark taken from the ladder of CHARSET (utf8 or
# ascii, keel_banner_charset). Three rows of text go with the address
# block: the blank row under the mark, the title, and the blank row under
# the title. The mark is centred on COLS, the title and the addresses are
# not.
keel_banner_render() {
    local rows=$1 cols=$2 charset=$3 name=$4 version=$5
    shift 5
    local -a address_lines=()
    mapfile -t address_lines < <(keel_banner_address_lines "$@")
    local body=$((3 + ${#address_lines[@]}))
    local -a marks=()
    mapfile -t marks < <(keel_banner_marks "$charset")
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
