#!/usr/bin/env bats
# Unit tests of overlay/usr/lib/keel/banner.sh: the version string, the
# title, the address block, the mark that fits and the whole rendered
# banner. Nothing here needs root, a network or a terminal: the mark files
# are the ones the overlay installs and the addresses are arguments.
#
# KEEL_BANNER_MARK and KEEL_BANNER_MARK_SMALL are names of this file only:
# the full and the small mark of the ASCII ladder, which most of the tests
# below walk. The library reads its marks from KEEL_BANNER_DIR.

bats_require_minimum_version 1.5.0

setup() {
    KEEL_BANNER_DIR="$BATS_TEST_DIRNAME/../overlay/etc/keel"
    load ../overlay/usr/lib/keel/banner.sh
    KEEL_BANNER_MARK="$KEEL_BANNER_DIR/banner.txt"
    KEEL_BANNER_MARK_SMALL="$KEEL_BANNER_DIR/banner-small.txt"
    KEEL_BANNER_MARK_WIDE="$KEEL_BANNER_DIR/banner-wide.txt"
    KEEL_BANNER_MARK_UTF8="$KEEL_BANNER_DIR/banner-utf8.txt"
    KEEL_BANNER_MARK_SMALL_UTF8="$KEEL_BANNER_DIR/banner-small-utf8.txt"
    # Most tests below are about an appliance that serves the web over
    # HTTPS, as Keel Web in a cloud mode does; the ones about Core, which
    # serves none, set it empty.
    KEEL_BANNER_WEB=https
    SCRATCH=$(mktemp -d)
}

teardown() {
    rm -rf "$SCRATCH"
}

# the version string

@test "app_name: the appliance name of a turnkey version string" {
    run keel_banner_app_name turnkey-core-19.0-trixie-amd64
    [ "$status" -eq 0 ]
    [ "$output" = core ]
}

@test "app_name: a name with hyphens keeps them" {
    run keel_banner_app_name keel-nginx-php-fastcgi-19.0-trixie-amd64
    [ "$status" -eq 0 ]
    [ "$output" = nginx-php-fastcgi ]
}

@test "app_name: a string without version, codename and architecture fails" {
    run keel_banner_app_name core
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "app_name: an empty string fails" {
    run keel_banner_app_name ""
    [ "$status" -eq 1 ]
}

@test "version: the version of a turnkey version string" {
    run keel_banner_version turnkey-core-19.0-trixie-amd64
    [ "$status" -eq 0 ]
    [ "$output" = 19.0-trixie-amd64 ]
}

@test "version: a string without the three trailing fields fails" {
    run keel_banner_version turnkey-core
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# the title

@test "truncate: a text that fits is printed as it is" {
    run keel_banner_truncate 20 "Keel Linux core"
    [ "$output" = "Keel Linux core" ]
}

@test "truncate: a longer text ends in three dots at exactly the width" {
    run keel_banner_truncate 10 "Keel Linux core"
    [ "$output" = "Keel Li..." ]
    [ "${#output}" -eq 10 ]
}

@test "truncate: a width of three has no room for the dots" {
    run keel_banner_truncate 3 "Keel Linux core"
    [ "$output" = Kee ]
}

@test "title: the appliance name then its version" {
    run keel_banner_title "Keel Linux core" 19.0-trixie-amd64 80
    [ "$output" = "Keel Linux core 19.0-trixie-amd64" ]
}

@test "title: a name with no version is the name alone" {
    run keel_banner_title "Keel Linux core" "" 80
    [ "$output" = "Keel Linux core" ]
}

@test "title: a version with no name is the version alone" {
    run keel_banner_title "" 19.0-trixie-amd64 80
    [ "$output" = 19.0-trixie-amd64 ]
}

@test "title: a long hostname stays on one line of 80 columns" {
    local name="Keel Linux forum-staging-eu-west-01.infrastructure.keellinux.org"
    run keel_banner_title "$name" 19.0-trixie-amd64 80
    [ "${#lines[@]}" -eq 1 ]
    [ "${#output}" -eq 80 ]
    [[ $output == Keel\ Linux\ forum-staging* ]]
    [[ $output == *... ]]
}

@test "title: the width defaults to 80 columns" {
    run keel_banner_title "$(printf 'n%.0s' {1..100})" "" ""
    [ "${#output}" -eq 80 ]
}

# the address block

@test "is_ipv6: an address with a colon is IPv6, one without is not" {
    keel_banner_is_ipv6 2001:db8:1::10
    run ! keel_banner_is_ipv6 192.0.2.10
}

@test "address_lines: dual stack lists IPv6 first, then IPv4" {
    run keel_banner_address_lines 2001:db8:1::10 192.0.2.10
    [ "${#lines[@]}" -eq 4 ]
    [ "${lines[0]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${lines[1]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
    [ "${lines[2]}" = "IPv4 Web:  https://192.0.2.10" ]
    [ "${lines[3]}" = "IPv4 SSH:  root@192.0.2.10" ]
}

@test "address_lines: IPv4 given first is still printed after IPv6" {
    run keel_banner_address_lines 192.0.2.10 2001:db8:1::10
    [ "${lines[0]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${lines[2]}" = "IPv4 Web:  https://192.0.2.10" ]
}

@test "address_lines: an IPv6 only appliance has no IPv4 line" {
    run keel_banner_address_lines 2001:db8:1::10
    [ "${#lines[@]}" -eq 2 ]
    [[ $output != *IPv4* ]]
}

@test "address_lines: an appliance with no IPv6 shows its IPv4 alone" {
    run keel_banner_address_lines 192.0.2.10
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "IPv4 Web:  https://192.0.2.10" ]
    [[ $output != *IPv6* ]]
}

@test "address_lines: several addresses of a family each get their pair" {
    run keel_banner_address_lines 2001:db8:1::10 2001:db8:2::20
    [ "${#lines[@]}" -eq 4 ]
    [ "${lines[2]}" = "IPv6 Web:  https://[2001:db8:2::20]" ]
}

@test "address_lines: an empty argument is skipped" {
    run keel_banner_address_lines "" 2001:db8:1::10 ""
    [ "${#lines[@]}" -eq 2 ]
}

@test "address_lines: no address at all says so in words" {
    run keel_banner_address_lines
    [ "$status" -eq 0 ]
    [ "$output" = "no address: the appliance is not reachable yet" ]
}

@test "address_lines: an appliance with no web server lists SSH only" {
    KEEL_BANNER_WEB=""
    run keel_banner_address_lines 2001:db8:1::10 192.0.2.10
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
    [ "${lines[1]}" = "IPv4 SSH:  root@192.0.2.10" ]
    [[ $output != *Web* ]]
}

@test "address_lines: the web line takes the scheme the appliance serves" {
    KEEL_BANNER_WEB=http
    run keel_banner_address_lines 2001:db8:1::10 192.0.2.10
    [ "${lines[0]}" = "IPv6 Web:  http://[2001:db8:1::10]" ]
    [ "${lines[2]}" = "IPv4 Web:  http://192.0.2.10" ]
}

@test "address_lines: the library alone assumes no web server" {
    run env -i bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         keel_banner_address_lines 2001:db8:1::10"
    [ "$output" = "IPv6 SSH:  root@2001:db8:1::10" ]
}

# whether the appliance serves the web
#
# services.txt is the declaration confconsole's usage screen reads, and each
# layer of the chain installs its own over its base's: Core's lists Webmin
# and SSH, Keel Web's and every web application's start with a Web line.

@test "web_scheme: Core's services name no web server" {
    run keel_banner_web_scheme < "$BATS_TEST_DIRNAME/../overlay/etc/confconsole/services.txt"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "web_scheme: Keel Web's services name http" {
    run keel_banner_web_scheme <<'TXT'
Web:        http://[$ipaddr6]
Webmin:     https://[$ipaddr6]:12321
SSH/SFTP:   root@$ipaddr6 (port 22)

Web:        http://$ipaddr
TXT
    [ "$status" -eq 0 ]
    [ "$output" = http ]
}

@test "web_scheme: an indented Web line with https" {
    run keel_banner_web_scheme <<'TXT'
SSH/SFTP:   root@$ipaddr6 (port 22)
  Web:	https://$ipaddr
TXT
    [ "$output" = https ]
}

@test "web_scheme: a Web line with no URL, or another scheme, is skipped" {
    run keel_banner_web_scheme <<'TXT'
Web:        see the documentation
Web:        ftp://$ipaddr
Webmin:     https://$ipaddr:12321
TXT
    [ "$status" -eq 1 ]
    run keel_banner_web_scheme <<'TXT'
Web:        ftp://$ipaddr
Web:        http://$ipaddr
TXT
    [ "$output" = http ]
}

@test "web_scheme: a last line without a newline is read" {
    run keel_banner_web_scheme < <(printf 'Web: https://$ipaddr')
    [ "$output" = https ]
}

@test "web_scheme: an empty file names no web server" {
    run keel_banner_web_scheme < /dev/null
    [ "$status" -eq 1 ]
}

# the rest of the login message
#
# What pam_motd prints after the banner takes rows of the same screen, so
# the mark is chosen with them counted: the drop-ins named after this one,
# measured as the terminal lays them out.

@test "text_rows: one row a line, blank lines included" {
    run keel_banner_text_rows 80 < <(printf 'a\n\nb\n\n')
    [ "$output" = 4 ]
}

@test "text_rows: a line as wide as the terminal is one row, one more wraps" {
    run keel_banner_text_rows 10 < <(printf '%s\n' 0123456789)
    [ "$output" = 1 ]
    run keel_banner_text_rows 10 < <(printf '%s\n' 0123456789a)
    [ "$output" = 2 ]
    run keel_banner_text_rows 10 < <(printf '%s\n' \
        012345678901234567890123456789)
    [ "$output" = 3 ]
}

@test "text_rows: escape sequences take no column" {
    # 08-turnkey-confconsole's bold, as tput prints it for xterm and for
    # the Linux console: CSI, and sgr0's "ESC ( B" charset selection
    local line=$'    For Advanced commandline config run:    \e[1mconfconsole\e(B\e[m'
    run keel_banner_text_rows 55 <<< "$line"
    [ "$output" = 1 ]
    run keel_banner_text_rows 54 <<< "$line"
    [ "$output" = 2 ]
    run keel_banner_text_rows 4 < <(printf '\e]0;title\aab\ecd\n')
    [ "$output" = 1 ]
}

@test "visible: what each kind of escape sequence leaves on the screen" {
    # CSI; OSC ended by BEL, by ST, or by whichever comes first; an OSC
    # left open; a charset selection; a two-byte one (ESC c, a reset)
    run keel_banner_visible $'a\e[1;33mb\e[0mc'
    [ "$output" = abc ]
    run keel_banner_visible $'\e]0;title\aab'
    [ "$output" = ab ]
    run keel_banner_visible $'\e]8;;http://x\e\\ab\e]8;;\e\\'
    [ "$output" = ab ]
    run keel_banner_visible $'\e]0;t\e\\a\a'
    [ "$output" = $'a\a' ]
    run keel_banner_visible $'ab\e]0;never ended'
    [ "$output" = ab ]
    run keel_banner_visible $'\e(Bab\e)0'
    [ "$output" = ab ]
    run keel_banner_visible $'\ecab'
    [ "$output" = ab ]
    run keel_banner_visible $'a\tb'
    [ "$output" = 'a       b' ]
}

@test "text_rows: a tab moves to the next multiple of eight" {
    run keel_banner_text_rows 9 < <(printf 'ab\tcd\n')
    [ "$output" = 2 ]
    run keel_banner_text_rows 10 < <(printf 'ab\tcd\n')
    [ "$output" = 1 ]
}

@test "text_rows: a character is a column, whatever the caller's locale" {
    run env LC_ALL=C bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         printf '%s\n' '██████' | keel_banner_text_rows 6"
    [ "$output" = 1 ]
}

@test "text_rows: a last line without a newline counts, nothing is zero" {
    run keel_banner_text_rows 80 < <(printf 'a\nb')
    [ "$output" = 2 ]
    run keel_banner_text_rows 80 < /dev/null
    [ "$output" = 0 ]
}

@test "after: the drop-ins named after this one, in the order given" {
    run keel_banner_after 00-keel-banner <<'LIST'
/etc/update-motd.d/00-keel-banner
/etc/update-motd.d/00-turnkey-sysinfo
/etc/update-motd.d/06-keel-init
/etc/update-motd.d/10-uname
LIST
    [ "${#lines[@]}" -eq 3 ]
    [ "${lines[0]}" = /etc/update-motd.d/00-turnkey-sysinfo ]
    [ "${lines[2]}" = /etc/update-motd.d/10-uname ]
}

@test "after: one named before this one, or this one, is not after it" {
    run keel_banner_after 05-keel-banner < <(printf '%s\n' \
        /x/00-turnkey-sysinfo /x/05-keel-banner /x/05-keel-bannerz /x/50-z)
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = /x/05-keel-bannerz ]
    [ "${lines[1]}" = /x/50-z ]
}

@test "after: names compare byte by byte, as run-parts orders them" {
    run keel_banner_after Z < <(printf '%s\n' /x/B /x/a /x/_)
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = /x/a ]
    [ "${lines[1]}" = /x/_ ]
}

# the mark that fits
#
# No test writes down the rows or the columns of the installed marks: the two
# files are exports of the design system and are redrawn there, so every
# expectation about them is measured from the file it is about. The fallback
# ladder is pinned with synthetic marks instead, whose size a test may choose.

mark_rows_of() {
    local size
    size=$(keel_banner_mark_size "$1")
    printf '%s\n' "${size% *}"
}

mark_cols_of() {
    local size
    size=$(keel_banner_mark_size "$1")
    printf '%s\n' "${size#* }"
}

# chosen_mark_rows_of ROWS COLS BODY_ROWS
# The rows of the mark the renderer takes on that terminal, 0 when none fits:
# a render test asks which mark was chosen rather than naming one.
chosen_mark_rows_of() {
    local mark
    if mark=$(keel_banner_choose_mark "$1" "$2" "$3" "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"); then
        mark_rows_of "$mark"
    else
        printf '0\n'
    fi
}

@test "mark_size: the installed mark is the size of its file" {
    local measured
    measured=$(awk '{ if (length($0) > w) w = length($0) }
                    END { print NR, w }' "$KEEL_BANNER_MARK")
    run keel_banner_mark_size "$KEEL_BANNER_MARK"
    [ "$status" -eq 0 ]
    [ "$output" = "$measured" ]
}

@test "mark_size: the small mark is the size of its file" {
    local measured
    measured=$(awk '{ if (length($0) > w) w = length($0) }
                    END { print NR, w }' "$KEEL_BANNER_MARK_SMALL")
    run keel_banner_mark_size "$KEEL_BANNER_MARK_SMALL"
    [ "$status" -eq 0 ]
    [ "$output" = "$measured" ]
}

@test "mark_size: the small mark is shorter and no wider than the full one" {
    [ "$(mark_rows_of "$KEEL_BANNER_MARK_SMALL")" -lt \
        "$(mark_rows_of "$KEEL_BANNER_MARK")" ]
    [ "$(mark_cols_of "$KEEL_BANNER_MARK_SMALL")" -le \
        "$(mark_cols_of "$KEEL_BANNER_MARK")" ]
}

@test "mark_size: a file whose last line has no newline still counts it" {
    printf 'ab\ncde' > "$SCRATCH/mark"
    run keel_banner_mark_size "$SCRATCH/mark"
    [ "$output" = "2 3" ]
}

@test "mark_size: an unreadable file fails" {
    run keel_banner_mark_size "$SCRATCH/absent"
    [ "$status" -eq 1 ]
}

@test "mark_size: an empty file fails rather than passing as a blank mark" {
    : > "$SCRATCH/empty"
    run keel_banner_mark_size "$SCRATCH/empty"
    [ "$status" -eq 1 ]
}

@test "choose_mark: a terminal with exactly the room takes the full mark" {
    local body=7 rows cols
    rows=$(($(mark_rows_of "$KEEL_BANNER_MARK") + body \
        + KEEL_BANNER_RESERVED_ROWS))
    cols=$(mark_cols_of "$KEEL_BANNER_MARK")
    run keel_banner_choose_mark "$rows" "$cols" "$body" "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK" ]
}

@test "choose_mark: one row short of the full mark takes the small one" {
    local body=7 rows
    rows=$(($(mark_rows_of "$KEEL_BANNER_MARK") + body \
        + KEEL_BANNER_RESERVED_ROWS - 1))
    run keel_banner_choose_mark "$rows" 80 "$body" "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

@test "choose_mark: a terminal narrower than the small mark takes no mark" {
    local cols
    cols=$(($(mark_cols_of "$KEEL_BANNER_MARK_SMALL") - 1))
    run keel_banner_choose_mark 40 "$cols" 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "choose_mark: a terminal too short for the small mark takes no mark" {
    local body=7 rows
    rows=$(($(mark_rows_of "$KEEL_BANNER_MARK_SMALL") + body \
        + KEEL_BANNER_RESERVED_ROWS - 1))
    run keel_banner_choose_mark "$rows" 80 "$body" "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$status" -eq 1 ]
}

@test "choose_mark: the ladder is walked by the size measured in each file" {
    printf '%s\n' '#####' '#####' '#####' > "$SCRATCH/wide"
    printf '%s\n' '##' '##' > "$SCRATCH/narrow"
    run keel_banner_choose_mark 6 5 2 "$SCRATCH/wide" "$SCRATCH/narrow"
    [ "$output" = "$SCRATCH/wide" ]
    run keel_banner_choose_mark 5 5 2 "$SCRATCH/wide" "$SCRATCH/narrow"
    [ "$output" = "$SCRATCH/narrow" ]
    run keel_banner_choose_mark 6 4 2 "$SCRATCH/wide" "$SCRATCH/narrow"
    [ "$output" = "$SCRATCH/narrow" ]
    run keel_banner_choose_mark 6 1 2 "$SCRATCH/wide" "$SCRATCH/narrow"
    [ "$status" -eq 1 ]
}

@test "choose_mark: a mark file that is not there is skipped" {
    run keel_banner_choose_mark 40 80 7 "$SCRATCH/absent" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

@test "choose_mark: a taller address block pushes the choice down" {
    local body=7 rows
    rows=$(($(mark_rows_of "$KEEL_BANNER_MARK") + body \
        + KEEL_BANNER_RESERVED_ROWS))
    run keel_banner_choose_mark "$rows" 80 "$body" "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK" ]
    run keel_banner_choose_mark "$rows" 80 $((body + 1)) \
        "$KEEL_BANNER_MARK" "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

# centring the mark
#
# The bats $lines array drops empty lines (its IFS is a newline), so a block
# that can hold a blank row is read into ROWS, where every row keeps its
# place.

rows_of() {
    mapfile -t ROWS < <(printf '%s\n' "$output")
}

# assert_centred_rows WIDTH FILE [FIRST_ROW]
# Every line of FILE stands in ROWS, from FIRST_ROW (0 by default), shifted
# right by the one indent that centres the widest line of the file on WIDTH.
# This is how a test checks a mark it did not draw: the indent comes from the
# file, so the check holds at whatever size the file carries.
assert_centred_rows() {
    local width=$1 file=$2 first=${3:-0} indent i line
    indent=$(((width - $(mark_cols_of "$file")) / 2))
    if [ "$indent" -lt 0 ]; then
        indent=0
    fi
    local -a mark_lines=()
    mapfile -t mark_lines < "$file"
    for ((i = 0; i < ${#mark_lines[@]}; i++)); do
        line=${mark_lines[i]}
        line=${line%"${line##*[![:space:]]}"}
        if [ -z "$line" ]; then
            [ -z "${ROWS[first + i]}" ] || return 1
            continue
        fi
        [ "${ROWS[first + i]}" = "$(printf '%*s%s' "$indent" '' "$line")" ] \
            || return 1
    done
}

@test "center_mark: an even leftover is split in two" {
    printf '%s\n' ab > "$SCRATCH/mark"
    run keel_banner_center_mark 6 "$SCRATCH/mark"
    [ "$output" = "  ab" ]
}

@test "center_mark: an odd leftover leaves the extra column on the right" {
    printf '%s\n' ab > "$SCRATCH/mark"
    run keel_banner_center_mark 5 "$SCRATCH/mark"
    [ "$output" = " ab" ]
}

@test "center_mark: the whole block moves by one indent, not line by line" {
    printf '%s\n' ABCDEF AB '  CD' > "$SCRATCH/mark"
    run keel_banner_center_mark 10 "$SCRATCH/mark"
    rows_of
    [ "${ROWS[0]}" = "  ABCDEF" ]
    [ "${ROWS[1]}" = "  AB" ]
    [ "${ROWS[2]}" = "    CD" ]
}

@test "center_mark: a mark exactly as wide as the width starts at column one" {
    printf '%s\n' abcd ab > "$SCRATCH/mark"
    run keel_banner_center_mark 4 "$SCRATCH/mark"
    rows_of
    [ "${ROWS[0]}" = abcd ]
    [ "${ROWS[1]}" = ab ]
}

@test "center_mark: a mark wider than the width is neither indented nor cut" {
    printf '%s\n' abcdefgh '  cd' > "$SCRATCH/mark"
    run keel_banner_center_mark 4 "$SCRATCH/mark"
    rows_of
    [ "${ROWS[0]}" = abcdefgh ]
    [ "${ROWS[1]}" = "  cd" ]
}

@test "center_mark: a blank line inside the mark stays blank" {
    printf '%s\n' ab '' cd > "$SCRATCH/mark"
    run keel_banner_center_mark 8 "$SCRATCH/mark"
    rows_of
    [ "${#ROWS[@]}" -eq 3 ]
    [ "${ROWS[0]}" = "   ab" ]
    [ "${ROWS[1]}" = "" ]
    [ "${ROWS[2]}" = "   cd" ]
}

@test "center_mark: no line of the centred mark ends in whitespace" {
    printf '%s\n' 'ab  ' '   ' cd > "$SCRATCH/mark"
    run keel_banner_center_mark 12 "$SCRATCH/mark"
    rows_of
    [ "${ROWS[1]}" = "" ]
    printf '%s\n' "$output" > "$SCRATCH/block"
    run ! grep -q '[[:space:]]$' "$SCRATCH/block"
}

@test "center_mark: a file whose last line has no newline is centred too" {
    printf 'abcd\nef' > "$SCRATCH/mark"
    run keel_banner_center_mark 12 "$SCRATCH/mark"
    rows_of
    [ "${#ROWS[@]}" -eq 2 ]
    [ "${ROWS[0]}" = "    abcd" ]
    [ "${ROWS[1]}" = "    ef" ]
}

@test "center_mark: an unreadable file fails and prints nothing" {
    run keel_banner_center_mark 80 "$SCRATCH/absent"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "center_mark: each installed mark is centred on the width it is given" {
    local mark
    for mark in "$KEEL_BANNER_MARK" "$KEEL_BANNER_MARK_SMALL"; do
        run keel_banner_center_mark 80 "$mark"
        [ "$status" -eq 0 ]
        rows_of
        [ "${#ROWS[@]}" -eq "$(mark_rows_of "$mark")" ]
        assert_centred_rows 80 "$mark"
    done
}

# block_margins WIDTH
# "LEFT RIGHT": the blank columns on each side of the block now in ROWS.
# Both are read off the block itself rather than computed from the file, so
# a test that uses this proves where the mark landed instead of repeating
# the arithmetic that put it there.
block_margins() {
    local width=$1 line lead left="" widest=0
    for line in "${ROWS[@]}"; do
        [ -n "$line" ] || continue
        lead=${line%%[![:space:]]*}
        if [ -z "$left" ] || [ "${#lead}" -lt "$left" ]; then
            left=${#lead}
        fi
        if [ "${#line}" -gt "$widest" ]; then
            widest=${#line}
        fi
    done
    printf '%s %s\n' "${left:-0}" "$((width - widest))"
}

@test "center_mark: the block stands in the middle, whatever the width" {
    # A mark of this file's own, whose widest line is neither the first nor
    # the last and one of whose lines is indented in the art itself: an
    # indent taken from the wrong line, or applied line by line rather than
    # to the block, shows up here as a lopsided pair of margins.
    printf '%s\n' '/\' '/====\' '' '  ||' > "$SCRATCH/mark"
    local width margins left right
    for width in 6 7 8 9 23 24 80 81; do
        run keel_banner_center_mark "$width" "$SCRATCH/mark"
        [ "$status" -eq 0 ]
        rows_of
        margins=$(block_margins "$width")
        left=${margins% *}
        right=${margins#* }
        # equal margins, or the one odd column left over on the right
        [ "$((right - left))" -ge 0 ]
        [ "$((right - left))" -le 1 ]
    done
}

# draw_mark FILE ROWS COLS
# A mark of exactly ROWS rows and COLS columns, ragged so that its widest
# line is the last one. A test may ask for any size with this, including
# one no art has ever had and none is planned to have.
draw_mark() {
    local file=$1 rows=$2 cols=$3 i
    : > "$file"
    for ((i = 1; i < rows; i++)); do
        printf '#\n' >> "$file"
    done
    printf '%*s\n' "$cols" '' | tr ' ' '#' >> "$file"
}

# the whole banner
#
# A rendered block is the mark, a blank row, the title, a blank row and the
# address lines, so a row that carries text sits at an offset from the rows of
# the mark that was chosen. Every index below is written that way, and no test
# names the mark it expects: it asks the library which one fits.

@test "render: a dual stack appliance on a tall terminal" {
    local mark_rows
    mark_rows=$(mark_rows_of "$KEEL_BANNER_MARK")
    run keel_banner_render 40 80 ascii "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    local expected
    expected=$(keel_banner_center_mark 80 "$KEEL_BANNER_MARK"
        printf '\nKeel Linux core 19.0-trixie-amd64\n\n'
        printf 'IPv6 Web:  https://[2001:db8:1::10]\n'
        printf 'IPv6 SSH:  root@2001:db8:1::10\n'
        printf 'IPv4 Web:  https://192.0.2.10\n'
        printf 'IPv4 SSH:  root@192.0.2.10\n')
    [ "$output" = "$expected" ]
    rows_of
    [ "${#ROWS[@]}" -eq $((mark_rows + 7)) ]
}

@test "render: the mark is centred on the width of the terminal" {
    local cols=70
    run keel_banner_render 40 "$cols" ascii "Keel Linux core" \
        19.0-trixie-amd64 \
        2001:db8:1::10
    rows_of
    assert_centred_rows "$cols" "$KEEL_BANNER_MARK"
}

@test "render: the title and the address lines stay at column one" {
    local mark_rows
    mark_rows=$(mark_rows_of "$KEEL_BANNER_MARK")
    run keel_banner_render 40 80 ascii "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    rows_of
    [ "${ROWS[mark_rows + 1]}" = "Keel Linux core 19.0-trixie-amd64" ]
    [ "${ROWS[mark_rows + 3]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[mark_rows + 4]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
    [ "${ROWS[mark_rows + 5]}" = "IPv4 Web:  https://192.0.2.10" ]
    [ "${ROWS[mark_rows + 6]}" = "IPv4 SSH:  root@192.0.2.10" ]
}

@test "render: an IPv6 only appliance names no IPv4" {
    local mark_rows
    mark_rows=$(mark_rows_of "$KEEL_BANNER_MARK")
    run keel_banner_render 40 80 ascii "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10
    [[ $output != *IPv4* ]]
    rows_of
    [ "${#ROWS[@]}" -eq $((mark_rows + 5)) ]
    assert_centred_rows 80 "$KEEL_BANNER_MARK"
    [ "${ROWS[mark_rows]}" = "" ]
    [ "${ROWS[mark_rows + 1]}" = "Keel Linux core 19.0-trixie-amd64" ]
    [ "${ROWS[mark_rows + 2]}" = "" ]
    [ "${ROWS[mark_rows + 3]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[mark_rows + 4]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
}

@test "render: a terminal of 24 rows keeps every address line and fits" {
    local rows=24 cols=80 mark_rows
    mark_rows=$(chosen_mark_rows_of "$rows" "$cols" 7)
    run keel_banner_render "$rows" "$cols" ascii "Keel Linux core" \
        19.0-trixie-amd64 2001:db8:1::10 192.0.2.10
    rows_of
    [ "${#ROWS[@]}" -eq $((mark_rows + 7)) ]
    [ "${#ROWS[@]}" -le $((rows - KEEL_BANNER_RESERVED_ROWS)) ]
    [ "${ROWS[mark_rows + 1]}" = "Keel Linux core 19.0-trixie-amd64" ]
    [ "${ROWS[mark_rows + 3]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[mark_rows + 6]}" = "IPv4 SSH:  root@192.0.2.10" ]
}

@test "render: a terminal too small for any mark keeps the text" {
    local cols
    cols=$(($(mark_cols_of "$KEEL_BANNER_MARK_SMALL") - 1))
    run keel_banner_render 10 "$cols" ascii "Keel Linux core" \
        19.0-trixie-amd64 \
        2001:db8:1::10
    rows_of
    [ "${#ROWS[@]}" -eq 4 ]
    [ "${ROWS[0]}" = \
        "$(keel_banner_truncate "$cols" "Keel Linux core 19.0-trixie-amd64")" ]
    [ "${#ROWS[0]}" -le "$cols" ]
    [ "${ROWS[1]}" = "" ]
    [ "${ROWS[2]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[3]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
}

@test "render: a mark of a third size is measured, not assumed" {
    KEEL_BANNER_DIR=$SCRATCH
    printf '%s\n' AAAA '' BB > "$SCRATCH/banner.txt"
    run keel_banner_render 40 10 ascii core 19.0 2001:db8:1::10
    rows_of
    [ "${#ROWS[@]}" -eq 8 ]
    [ "${ROWS[0]}" = "   AAAA" ]
    [ "${ROWS[1]}" = "" ]
    [ "${ROWS[2]}" = "   BB" ]
    [ "${ROWS[3]}" = "" ]
    [ "${ROWS[4]}" = "core 19.0" ]
    [ "${ROWS[5]}" = "" ]
    [ "${ROWS[6]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[7]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
}

@test "render: a mark of a size nobody drew renders whole and centred" {
    # Sizes picked to be nothing the art is or has been: one character, a
    # mark taller and far wider than any console mark, and a mark of one
    # tall column. Whichever it is, the renderer measures it, the block is
    # complete and centred, and the text below it keeps its order and its
    # column one. Five rows of text go with one address: the blank row, the
    # title, the blank row and the two address lines.
    local body=5 size rows cols term_rows term_cols
    for size in "1 1" "2 3" "9 17" "31 71" "44 7"; do
        rows=${size% *}
        cols=${size#* }
        KEEL_BANNER_DIR=$SCRATCH
        draw_mark "$SCRATCH/banner.txt" "$rows" "$cols"
        cp "$SCRATCH/banner.txt" "$SCRATCH/mark"
        [ "$(keel_banner_mark_size "$SCRATCH/mark")" = "$rows $cols" ]

        # the smallest terminal this mark fits in, nine columns to spare
        term_rows=$((rows + body + KEEL_BANNER_RESERVED_ROWS))
        term_cols=$((cols + 9))
        run keel_banner_render "$term_rows" "$term_cols" ascii core 19.0 \
            2001:db8:1::10
        [ "$status" -eq 0 ]
        rows_of
        [ "${#ROWS[@]}" -eq $((rows + body)) ]
        [ "${#ROWS[@]}" -le $((term_rows - KEEL_BANNER_RESERVED_ROWS)) ]
        assert_centred_rows "$term_cols" "$SCRATCH/mark"
        [ "${ROWS[rows]}" = "" ]
        [ "${ROWS[rows + 1]}" = "core 19.0" ]
        [ "${ROWS[rows + 2]}" = "" ]
        [ "${ROWS[rows + 3]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
        [ "${ROWS[rows + 4]}" = "IPv6 SSH:  root@2001:db8:1::10" ]

        # one row short, or one column short, and the mark goes rather
        # than a line of text: what is left is the body without the blank
        # row the mark carried above it.
        run keel_banner_render $((term_rows - 1)) "$term_cols" ascii core \
            19.0 2001:db8:1::10
        rows_of
        [ "${#ROWS[@]}" -eq $((body - 1)) ]
        [ "${ROWS[0]}" = "core 19.0" ]
        [ "${ROWS[2]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
        run keel_banner_render "$term_rows" $((cols - 1)) ascii core 19.0 \
            2001:db8:1::10
        rows_of
        [ "${#ROWS[@]}" -eq $((body - 1)) ]
        [ "${ROWS[${#ROWS[@]} - 1]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
    done
}

@test "render: the block is plain ASCII with no escape character" {
    run keel_banner_render 40 80 ascii "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    [[ $output != *$'\e'* ]]
    printf '%s\n' "$output" > "$SCRATCH/block"
    run ! env LC_ALL=C grep -q '[^ -~]' "$SCRATCH/block"
}

@test "render: a long hostname does not cost the addresses a line" {
    local name="Keel Linux forum-staging-eu-west-01.infrastructure.keellinux.org"
    local rows=24 cols=80 mark_rows
    mark_rows=$(chosen_mark_rows_of "$rows" "$cols" 5)
    run keel_banner_render "$rows" "$cols" ascii "$name" 19.0-trixie-amd64 \
        2001:db8:1::10
    rows_of
    [ "${#ROWS[@]}" -eq $((mark_rows + 5)) ]
    [ "${#ROWS[@]}" -le $((rows - KEEL_BANNER_RESERVED_ROWS)) ]
    [ "${#ROWS[mark_rows + 1]}" -eq "$cols" ]
    [ "${ROWS[mark_rows + 3]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[mark_rows + 4]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
}

@test "render: Core, with no web server, lists SSH only" {
    KEEL_BANNER_WEB=""
    local mark_rows
    mark_rows=$(mark_rows_of "$KEEL_BANNER_MARK")
    run keel_banner_render 40 80 ascii "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    [[ $output != *Web* ]]
    rows_of
    [ "${#ROWS[@]}" -eq $((mark_rows + 5)) ]
    [ "${ROWS[mark_rows + 3]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
    [ "${ROWS[mark_rows + 4]}" = "IPv4 SSH:  root@192.0.2.10" ]
}

@test "render: the rows of the login message below push the choice down" {
    # a terminal with exactly the room for the full mark and the banner's
    # own text: one row of message below takes the full mark away, and a
    # message as tall as the terminal leaves no room for any mark
    local body=7 rows below
    rows=$(($(mark_rows_of "$KEEL_BANNER_MARK") + body \
        + KEEL_BANNER_RESERVED_ROWS))
    run keel_banner_render "$rows" 80 ascii core 19.0 2001:db8:1::10 \
        192.0.2.10
    rows_of
    assert_centred_rows 80 "$KEEL_BANNER_MARK"
    KEEL_BANNER_BELOW_ROWS=1
    run keel_banner_render "$rows" 80 ascii core 19.0 2001:db8:1::10 \
        192.0.2.10
    rows_of
    assert_centred_rows 80 "$KEEL_BANNER_MARK_SMALL"
    below=$((rows - body - KEEL_BANNER_RESERVED_ROWS))
    KEEL_BANNER_BELOW_ROWS=$below
    run keel_banner_render "$rows" 80 ascii core 19.0 2001:db8:1::10 \
        192.0.2.10
    rows_of
    [ "${#ROWS[@]}" -eq $((body - 1)) ]
    [ "${ROWS[0]}" = "core 19.0" ]
}

# core_motd_rest: what pam_motd printed after the banner at a Core login on
# the step 8 image (screenshots 112 to 119): the sysinfo, the confconsole
# line in bold as tput writes it, and uname, which is wider than 80 columns.
core_motd_rest() {
    printf '%s\n' 'Welcome to Core, Debian 13/Trixie' '' \
        '  System information for Fri Oct 02 11:36:10 2026 (UTC+0000)' '' \
        '    System load:  0.57               Memory usage:  18.7%' \
        '    Processes:    33                 Swap usage:    5.1%' \
        '    Usage of /:   26.0% of 29.36GB   IP address for eth0: 10.0.3.98' \
        '' \
        $'    For Advanced commandline config run:    \e[1mconfconsole\e(B\e[m' \
        '' '  For more info see: https://github.com/Keel-Linux/confconsole' \
        '' \
        'Linux core 6.12.107+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.107-1 (2026-08-29) x86_64'
}

@test "render: on the maintainer's four terminals the whole login message fits" {
    # The banner, the rest of the message, the blank line the drop-in ends
    # with and the prompt: nothing scrolls off the top. 80 by 24 has no room
    # for any mark once the message is counted, 100 by 30 has room for one,
    # and the larger two take the wide mark whole.
    KEEL_BANNER_WEB=""
    local size rows cols charset below body mark
    for charset in utf8 ascii; do
        for size in "24 80" "30 100" "45 160" "50 200"; do
            rows=${size% *}
            cols=${size#* }
            below=$(($(core_motd_rest | keel_banner_text_rows "$cols") + 1))
            KEEL_BANNER_BELOW_ROWS=$below
            body=$((3 + 2 + below))
            run keel_banner_render "$rows" "$cols" "$charset" \
                "Keel Linux core" 19.0-trixie-amd64 fd42:b2:0:1::98 10.0.3.98
            [ "$status" -eq 0 ]
            rows_of
            [ $((${#ROWS[@]} + below + KEEL_BANNER_RESERVED_ROWS)) -le "$rows" ]
            if mark=$(expected_mark "$charset" "$rows" "$cols" "$body"); then
                assert_centred_rows "$cols" "$mark"
                [ "${#ROWS[@]}" -eq $(($(mark_rows_of "$mark") + body - below)) ]
            else
                [ "${ROWS[0]}" = "Keel Linux core 19.0-trixie-amd64" ]
            fi
            case "$charset $cols" in
                *" 80") [ "${ROWS[0]}" = "Keel Linux core 19.0-trixie-amd64" ] ;;
                *" 100") [ "${ROWS[0]}" != "Keel Linux core 19.0-trixie-amd64" ] ;;
                utf8*) [ "$mark" = "$KEEL_BANNER_MARK_WIDE" ] ;;
            esac
        done
    done
}

# the address probe

@test "pick_ipv6: a static address is preferred over a dynamic one" {
    run keel_banner_pick_ipv6 <<'OUT'
    inet6 2001:db8:1::20/64 scope global dynamic mngtmpaddr
       valid_lft 2591996sec preferred_lft 604796sec
    inet6 2001:db8:1::10/64 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$output" = 2001:db8:1::10 ]
}

@test "pick_ipv6: a privacy address is the last resort" {
    run keel_banner_pick_ipv6 <<'OUT'
    inet6 2001:db8:1::f00/64 scope global temporary dynamic
    inet6 2001:db8:1::20/64 scope global dynamic mngtmpaddr
OUT
    [ "$output" = 2001:db8:1::20 ]
}

@test "pick_ipv6: a privacy address alone is still printed" {
    run keel_banner_pick_ipv6 <<'OUT'
    inet6 2001:db8:1::f00/64 scope global temporary dynamic
OUT
    [ "$output" = 2001:db8:1::f00 ]
}

@test "pick_ipv6: no global address fails" {
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
OUT
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "pick_ipv4: the first global address" {
    run keel_banner_pick_ipv4 <<'OUT'
    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 198.51.100.10/24 scope global secondary eth0
OUT
    [ "$output" = 192.0.2.10 ]
}

@test "pick_ipv4: an appliance without IPv4 fails, which is not an error" {
    run keel_banner_pick_ipv4 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
OUT
    [ "$status" -eq 1 ]
}

@test "pick_ipv6: the public address on eth0 is preferred over the ULA of a WireGuard overlay" {
    # a Keel Web machine with the wireguard overlay (2026-10-03) printed
    # "IPv6 Web: http://[fd11:a58a:88ef::1]", the wg0 address, which no
    # one but a peer can reach
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
    inet6 2804:14c:5bb1:8a00::1/64 scope global dynamic mngtmpaddr
       valid_lft 86213sec preferred_lft 14213sec
3: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN qlen 1000
    inet6 fd11:a58a:88ef::1/64 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$status" -eq 0 ]
    [ "$output" = 2804:14c:5bb1:8a00::1 ]
}

@test "pick_ipv6: a ULA on a physical interface is preferred over a public one on an overlay" {
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 fd42:b2:0:1::98/64 scope global
       valid_lft forever preferred_lft forever
3: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN qlen 1000
    inet6 2001:db8:77::1/64 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$output" = fd42:b2:0:1::98 ]
}

@test "pick_ipv6: a public address is preferred over a ULA on the same interface" {
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 fd42:b2:0:1::98/64 scope global
       valid_lft forever preferred_lft forever
    inet6 2001:db8:1::10/64 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$output" = 2001:db8:1::10 ]
}

@test "pick_ipv6: a ULA alone is still printed" {
    # the LXC boot test's bridge hands out fd42:b2:0:1::/64 and nothing else
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0@if9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP qlen 1000
    inet6 fd42:b2:0:1::98/64 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$status" -eq 0 ]
    [ "$output" = fd42:b2:0:1::98 ]
}

@test "pick_ipv6: an address on an overlay alone is still printed" {
    local iface
    for iface in wg0 tun0 tap0; do
        run keel_banner_pick_ipv6 <<OUT
3: $iface: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN qlen 1000
    inet6 fd11:a58a:88ef::1/64 scope global
       valid_lft forever preferred_lft forever
OUT
        [ "$status" -eq 0 ]
        [ "$output" = fd11:a58a:88ef::1 ]
    done
}

@test "pick_ipv6: on eth0 the stable address is taken, not the temporary one, whatever their order" {
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2804:14c:5bb1:8a00:a1b2:c3d4:e5f6:789a/64 scope global temporary dynamic
       valid_lft 86213sec preferred_lft 14213sec
    inet6 2804:14c:5bb1:8a00:5054:ff:fe12:3456/64 scope global dynamic mngtmpaddr
       valid_lft 86213sec preferred_lft 14213sec
OUT
    [ "$output" = 2804:14c:5bb1:8a00:5054:ff:fe12:3456 ]
}

@test "pick_ipv6: a deprecated address is passed over for one still preferred" {
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:db8:1::10/64 scope global deprecated dynamic
       valid_lft 86213sec preferred_lft 0sec
    inet6 2001:db8:2::10/64 scope global dynamic
       valid_lft 86213sec preferred_lft 14213sec
OUT
    [ "$output" = 2001:db8:2::10 ]
}

@test "pick_ipv6: two physical interfaces, the lowest-numbered one wins" {
    run keel_banner_pick_ipv6 <<'OUT'
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:db8:2::20/64 scope global
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:db8:1::10/64 scope global dynamic mngtmpaddr
       valid_lft 86213sec preferred_lft 14213sec
OUT
    [ "$output" = 2001:db8:1::10 ]
}

@test "pick_ipv6: two physical interfaces, a temporary address on the first yields to the second" {
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:db8:1::f00/64 scope global temporary dynamic
       valid_lft 86213sec preferred_lft 14213sec
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 2001:db8:2::20/64 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$output" = 2001:db8:2::20 ]
}

@test "pick_ipv6: an address that is neither public nor a ULA ranks below both" {
    # 2002::/16 (6to4) is in 2000::/3 and counts as public
    run keel_banner_pick_ipv6 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet6 fec0::1/64 scope global
       valid_lft forever preferred_lft forever
    inet6 fd42:b2:0:1::98/64 scope global
       valid_lft forever preferred_lft forever
    inet6 2002:c000:204::1/48 scope global
       valid_lft forever preferred_lft forever
OUT
    [ "$output" = 2002:c000:204::1 ]
}

@test "pick_ipv4: a public address is preferred over an RFC 1918 one on a WireGuard overlay" {
    run keel_banner_pick_ipv4 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet 198.51.100.10/24 brd 198.51.100.255 scope global eth0
       valid_lft forever preferred_lft forever
3: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN qlen 1000
    inet 10.44.0.1/24 scope global wg0
       valid_lft forever preferred_lft forever
OUT
    [ "$output" = 198.51.100.10 ]
}

@test "pick_ipv4: the overlay's address is skipped even when it comes first" {
    run keel_banner_pick_ipv4 <<'OUT'
2: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 state UNKNOWN qlen 1000
    inet 10.44.0.1/24 scope global wg0
3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet 10.0.3.98/24 brd 10.0.3.255 scope global eth0
OUT
    [ "$output" = 10.0.3.98 ]
}

@test "pick_ipv4: a public address is preferred over a private one when both exist" {
    run keel_banner_pick_ipv4 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet 192.168.1.10/24 brd 192.168.1.255 scope global eth0
    inet 172.16.5.10/16 brd 172.16.255.255 scope global secondary eth0
    inet 203.0.113.10/24 brd 203.0.113.255 scope global secondary eth0
OUT
    [ "$output" = 203.0.113.10 ]
}

@test "pick_ipv4: private addresses alone keep the first, as before" {
    run keel_banner_pick_ipv4 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet 10.0.3.98/24 brd 10.0.3.255 scope global eth0
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet 192.168.1.10/24 brd 192.168.1.255 scope global eth1
OUT
    [ "$output" = 10.0.3.98 ]
}

@test "pick_ipv4: 172.32.0.0 is not RFC 1918" {
    run keel_banner_pick_ipv4 <<'OUT'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP qlen 1000
    inet 172.31.255.10/16 scope global eth0
    inet 172.32.0.10/16 scope global secondary eth0
OUT
    [ "$output" = 172.32.0.10 ]
}

@test "pick_ipv4: an address on an overlay alone is still printed" {
    run keel_banner_pick_ipv4 <<'OUT'
2: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 state UNKNOWN qlen 500
    inet 10.8.0.2/24 scope global tun0
OUT
    [ "$status" -eq 0 ]
    [ "$output" = 10.8.0.2 ]
}

# what the overlay installs

@test "the marks are read from /etc/keel unless told otherwise" {
    run env -u KEEL_BANNER_DIR bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         keel_banner_marks utf8; keel_banner_marks ascii"
    [ "$output" = "/etc/keel/banner-wide.txt
/etc/keel/banner-utf8.txt
/etc/keel/banner-small-utf8.txt
/etc/keel/banner.txt
/etc/keel/banner-small.txt" ]
}

@test "the overlay installs every mark the two ladders name" {
    local mark
    for mark in $(keel_banner_marks utf8) $(keel_banner_marks ascii); do
        [ -s "$mark" ]
        keel_banner_mark_size "$mark" > /dev/null
    done
}

@test "the ASCII marks are plain ASCII with no escape character" {
    local mark
    for mark in $(keel_banner_marks ascii); do
        run ! env LC_ALL=C grep -q '[^ -~]' "$mark"
    done
}

@test "the UTF-8 marks are valid UTF-8 with no escape character" {
    local mark
    for mark in $(keel_banner_marks utf8); do
        iconv -f UTF-8 -t UTF-8 "$mark" > /dev/null
        run ! grep -q $'\e' "$mark"
        run ! grep -q $'\t' "$mark"
    done
}

@test "the UTF-8 and the ASCII marks of a tier are the same size" {
    [ "$(keel_banner_mark_size "$KEEL_BANNER_MARK_UTF8")" = \
        "$(keel_banner_mark_size "$KEEL_BANNER_MARK")" ]
    [ "$(keel_banner_mark_size "$KEEL_BANNER_MARK_SMALL_UTF8")" = \
        "$(keel_banner_mark_size "$KEEL_BANNER_MARK_SMALL")" ]
}

@test "the ladders go from the largest mark to the smallest" {
    local charset previous="" mark size
    for charset in utf8 ascii; do
        previous=""
        for mark in $(keel_banner_marks "$charset"); do
            size=$(keel_banner_mark_size "$mark")
            if [ -n "$previous" ]; then
                [ "${size#* }" -le "${previous#* }" ]
                [ "${size% *}" -le "${previous% *}" ]
            fi
            previous=$size
        done
    done
}

@test "no line of an installed mark ends in whitespace" {
    local mark
    for mark in $(keel_banner_marks utf8) $(keel_banner_marks ascii); do
        run ! grep -q '[[:space:]]$' "$mark"
    done
}

# the character set
#
# The UTF-8 marks draw with block and shade characters, which a terminal in
# the C locale prints as three bytes of noise each, so the ladder follows the
# locale: UTF-8 when it says UTF-8, ASCII otherwise.

@test "marks: the UTF-8 ladder is the wide, the full and the small mark" {
    run keel_banner_marks utf8
    [ "$output" = "$KEEL_BANNER_MARK_WIDE
$KEEL_BANNER_MARK_UTF8
$KEEL_BANNER_MARK_SMALL_UTF8" ]
}

@test "marks: the ASCII ladder has no wide mark" {
    run keel_banner_marks ascii
    [ "$output" = "$KEEL_BANNER_MARK
$KEEL_BANNER_MARK_SMALL" ]
}

@test "marks: anything but utf8 is the ASCII ladder" {
    run keel_banner_marks ""
    [ "$output" = "$(keel_banner_marks ascii)" ]
    run keel_banner_marks latin1
    [ "$output" = "$(keel_banner_marks ascii)" ]
}

@test "effective_locale: LC_ALL wins over LC_CTYPE and LANG" {
    run keel_banner_effective_locale C en_US.UTF-8 en_US.UTF-8
    [ "$output" = C ]
}

@test "effective_locale: LC_CTYPE wins over LANG" {
    run keel_banner_effective_locale "" C.UTF-8 C
    [ "$output" = C.UTF-8 ]
}

@test "effective_locale: LANG when nothing else is set" {
    run keel_banner_effective_locale "" "" pt_BR.UTF-8
    [ "$output" = pt_BR.UTF-8 ]
}

@test "effective_locale: nothing set prints nothing" {
    run keel_banner_effective_locale "" "" ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run keel_banner_effective_locale
    [ -z "$output" ]
}

@test "charset: a UTF-8 locale, however it is spelled" {
    local value
    for value in C.UTF-8 C.utf8 en_US.UTF-8 pt_BR.utf8 de_DE.UTF-8@euro; do
        run keel_banner_charset "$value"
        [ "$output" = utf8 ]
    done
}

@test "charset: C, POSIX, a legacy codeset or nothing is ASCII" {
    local value
    for value in C POSIX en_US en_US.ISO-8859-1 ""; do
        run keel_banner_charset "$value"
        [ "$output" = ascii ]
    done
    run keel_banner_charset
    [ "$output" = ascii ]
}

@test "locale_of_file: reads /etc/default/locale with its precedence" {
    run keel_banner_locale_of_file <<'FILE'
#  File generated by update-locale
LANG="en_US.UTF-8"
LC_CTYPE=C
FILE
    [ "$output" = C ]
}

@test "locale_of_file: single quotes, blanks and comments" {
    run keel_banner_locale_of_file <<'FILE'

# LC_ALL=C
  LANG='pt_BR.UTF-8'
LANGUAGE=pt_BR:pt
FILE
    [ "$output" = pt_BR.UTF-8 ]
}

@test "locale_of_file: LC_ALL in the file wins over the rest" {
    run keel_banner_locale_of_file <<'FILE'
LANG=en_US.UTF-8
LC_ALL=C
LC_CTYPE=en_US.UTF-8
FILE
    [ "$output" = C ]
}

@test "locale_of_file: a last line with no newline is read" {
    run keel_banner_locale_of_file < <(printf 'LANG=C.UTF-8')
    [ "$output" = C.UTF-8 ]
}

@test "locale_of_file: an empty file names no locale" {
    run keel_banner_locale_of_file < /dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# the size of the terminal
#
# pam_motd runs the drop-ins with an empty environment and its output goes
# to a file, so the size comes from LINES and COLUMNS when a caller sets
# them, from stty on the controlling terminal when there is one, and from
# the 24 by 80 every terminal guarantees when neither says.

@test "terminal_size: LINES and COLUMNS win" {
    run keel_banner_terminal_size 50 200 "30 100"
    [ "$output" = "50 200" ]
}

@test "terminal_size: stty when the environment does not say" {
    run keel_banner_terminal_size "" "" "45 160"
    [ "$output" = "45 160" ]
}

@test "terminal_size: each dimension falls back on its own" {
    run keel_banner_terminal_size 30 "" "45 160"
    [ "$output" = "30 160" ]
    run keel_banner_terminal_size "" 100 ""
    [ "$output" = "24 100" ]
}

@test "terminal_size: nothing usable is 24 by 80" {
    run keel_banner_terminal_size "" "" ""
    [ "$output" = "24 80" ]
    run keel_banner_terminal_size
    [ "$output" = "24 80" ]
}

@test "terminal_size: zero, negative or not a number is not a size" {
    run keel_banner_terminal_size 0 abc "0 0"
    [ "$output" = "24 80" ]
    run keel_banner_terminal_size -5 12x "x -7"
    [ "$output" = "24 80" ]
    run keel_banner_terminal_size -5 12x "x 7"
    [ "$output" = "24 7" ]
}

# the UTF-8 ladder on the four terminals the maintainer looks at
#
# Which tier a terminal gets is measured, never written down: the expected
# mark is the largest of the ladder whose measured size leaves room for the
# text, and each case checks that it is the one rendered and that it is
# centred.

# expected_mark CHARSET ROWS COLS BODY
expected_mark() {
    local mark size
    for mark in $(keel_banner_marks "$1"); do
        size=$(keel_banner_mark_size "$mark")
        [ "${size#* }" -le "$3" ] || continue
        [ $((${size% *} + $4 + KEEL_BANNER_RESERVED_ROWS)) -le "$2" ] \
            || continue
        printf '%s\n' "$mark"
        return 0
    done
    return 1
}

@test "mark_size: a UTF-8 mark is measured in characters in any locale" {
    printf '%s\n' '█▄▀░' '▒▓' > "$SCRATCH/mark"
    run env LC_ALL=C bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         keel_banner_mark_size '$SCRATCH/mark'"
    [ "$output" = "2 4" ]
    run env LC_ALL=C.UTF-8 bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         keel_banner_mark_size '$SCRATCH/mark'"
    [ "$output" = "2 4" ]
}

@test "mark_size: the measurement leaves the caller's locale alone" {
    run env LC_ALL=C bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         keel_banner_mark_size '$KEEL_BANNER_MARK_WIDE' > /dev/null
         s='█'; echo \${#s}"
    [ "$output" = 3 ]
}

@test "center_mark: a UTF-8 mark is centred on characters, not bytes" {
    printf '%s\n' '██' '▀' > "$SCRATCH/mark"
    run env LC_ALL=C bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         keel_banner_center_mark 6 '$SCRATCH/mark'"
    [ "$output" = "  ██
  ▀" ]
}

@test "render: each terminal gets the largest UTF-8 mark that fits" {
    local size rows cols mark body=7
    for size in "24 80" "30 100" "45 160" "50 200"; do
        rows=${size% *}
        cols=${size#* }
        mark=$(expected_mark utf8 "$rows" "$cols" "$body")
        run keel_banner_render "$rows" "$cols" utf8 "Keel Linux core" \
            19.0-trixie-amd64 2001:db8:1::10 192.0.2.10
        [ "$status" -eq 0 ]
        rows_of
        [ "${#ROWS[@]}" -eq $(($(mark_rows_of "$mark") + body)) ]
        assert_centred_rows "$cols" "$mark"
    done
}

@test "render: the wide mark needs its full width and falls back below it" {
    local cols rows=50 body=7
    cols=$(mark_cols_of "$KEEL_BANNER_MARK_WIDE")
    run keel_banner_render "$rows" "$cols" utf8 core 19.0 \
        2001:db8:1::10 192.0.2.10
    rows_of
    assert_centred_rows "$cols" "$KEEL_BANNER_MARK_WIDE"
    run keel_banner_render "$rows" $((cols - 1)) utf8 core 19.0 \
        2001:db8:1::10 192.0.2.10
    rows_of
    assert_centred_rows $((cols - 1)) "$KEEL_BANNER_MARK_UTF8"
    [ "${#ROWS[@]}" -eq $(($(mark_rows_of "$KEEL_BANNER_MARK_UTF8") + body)) ]
}

@test "render: an ASCII terminal never gets the wide mark" {
    run keel_banner_render 50 200 ascii core 19.0 2001:db8:1::10
    rows_of
    assert_centred_rows 200 "$KEEL_BANNER_MARK"
    printf '%s\n' "$output" > "$SCRATCH/block"
    run ! env LC_ALL=C grep -q '[^ -~]' "$SCRATCH/block"
}

@test "render: a UTF-8 terminal too small for the full mark gets the small" {
    local rows body=7
    rows=$(($(mark_rows_of "$KEEL_BANNER_MARK_SMALL_UTF8") + body \
        + KEEL_BANNER_RESERVED_ROWS))
    run keel_banner_render "$rows" 80 utf8 core 19.0 \
        2001:db8:1::10 192.0.2.10
    rows_of
    assert_centred_rows 80 "$KEEL_BANNER_MARK_SMALL_UTF8"
}

@test "render: a UTF-8 tier that is not installed is skipped" {
    KEEL_BANNER_DIR=$SCRATCH
    cp "$KEEL_BANNER_MARK_SMALL_UTF8" "$SCRATCH/banner-small-utf8.txt"
    run keel_banner_render 50 200 utf8 core 19.0 2001:db8:1::10
    rows_of
    assert_centred_rows 200 "$SCRATCH/banner-small-utf8.txt"
}

# the drop-in itself, and /etc/appname
#
# /etc/appname is written by hand as often as by a tool, and an editor or
# `printf` may leave it without a trailing newline. read returns non-zero
# on such a file although it has read the name, so the name must survive
# that status.

# run_dropin APPNAME_CONTENT: runs 00-keel-banner on the library of this
# repository with /etc/appname holding APPNAME_CONTENT, on a terminal of
# DROPIN_LINES rows (24 unless a test says) by 80 in the C locale. The
# drop-in directory is $SCRATCH/motd.d, holding a copy of the banner and
# whatever a test puts there; /etc/motd is $SCRATCH/motd and services.txt
# is $SCRATCH/services.txt, each absent unless a test writes it.
run_dropin() {
    printf '%s' "$1" > "$SCRATCH/appname"
    printf 'turnkey-web-19.0-trixie-amd64\n' > "$SCRATCH/version"
    mkdir -p "$SCRATCH/motd.d"
    cp "$BATS_TEST_DIRNAME/../overlay/etc/update-motd.d/00-keel-banner" \
        "$SCRATCH/motd.d/"
    run env -i PATH="$PATH" LINES="${DROPIN_LINES:-24}" COLUMNS=80 LC_ALL=C \
        KEEL_BANNER_LIB="$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh" \
        KEEL_BANNER_DIR="$KEEL_BANNER_DIR" \
        KEEL_VERSION_FILE="$SCRATCH/version" \
        KEEL_APPNAME_FILE="$SCRATCH/appname" \
        KEEL_LOCALE_FILE=/nonexistent \
        KEEL_MOTD_DIR="$SCRATCH/motd.d" \
        KEEL_MOTD_FILE="$SCRATCH/motd" \
        KEEL_SERVICES_FILE="$SCRATCH/services.txt" \
        ${DROPIN_ENV:+"$DROPIN_ENV"} \
        bash "$SCRATCH/motd.d/00-keel-banner"
}

# motd_script NAME LINES: an executable drop-in printing LINES lines
motd_script() {
    mkdir -p "$SCRATCH/motd.d"
    printf '#!/bin/sh\nfor i in $(seq %s); do echo "line $i"; done\n' "$2" \
        > "$SCRATCH/motd.d/$1"
    chmod +x "$SCRATCH/motd.d/$1"
}

# has_mark, no_mark: the banner in $output opens with a mark, or with its
# title
has_mark() {
    [[ ${lines[0]} != "My Site"* ]]
}

no_mark() {
    [[ ${lines[0]} == "My Site"* ]]
}

@test "drop-in: no services.txt, or Core's, and there is no Web line" {
    DROPIN_LINES=60 run_dropin 'My Site'
    [[ $output != *"Web:"* ]]
    cp "$BATS_TEST_DIRNAME/../overlay/etc/confconsole/services.txt" \
        "$SCRATCH/services.txt"
    DROPIN_LINES=60 run_dropin 'My Site'
    [ "$status" -eq 0 ]
    [[ $output != *"Web:"* ]]
}

@test "drop-in: an appliance whose services.txt lists Web has its Web line" {
    local global
    global=$( (ip -6 addr show scope global; ip -4 addr show scope global) \
        | grep -c 'inet' || :)
    if [ "${global:-0}" -eq 0 ]; then
        skip "this machine has no global address to list"
    fi
    printf 'Web:        http://$ipaddr\n' > "$SCRATCH/services.txt"
    DROPIN_LINES=60 run_dropin 'My Site'
    [[ $output == *"Web:  http://"* ]]
}

@test "drop-in: the drop-ins named after it are counted, not printed" {
    DROPIN_LINES=60 run_dropin 'My Site'
    has_mark
    # one named before it is not below it
    motd_script 00-a-before 60
    DROPIN_LINES=60 run_dropin 'My Site'
    has_mark
    motd_script 50-after 55
    DROPIN_LINES=60 run_dropin 'My Site'
    [ "$status" -eq 0 ]
    no_mark
    [[ $output != *"line 1"* ]]
}

@test "drop-in: the drop-ins are the ones pam_motd runs, LSB names too" {
    # pam_motd runs "run-parts --lsbsysinit", which also takes the LSB
    # hierarchical names a plain run-parts skips
    DROPIN_LINES=60 run_dropin 'My Site'
    has_mark
    motd_script 50-org.example-motd 55
    DROPIN_LINES=60 run_dropin 'My Site'
    [ "$status" -eq 0 ]
    no_mark
}

@test "drop-in: /etc/motd, which pam_motd prints last, is counted" {
    DROPIN_LINES=60 run_dropin 'My Site'
    has_mark
    seq 55 > "$SCRATCH/motd"
    DROPIN_LINES=60 run_dropin 'My Site'
    no_mark
}

@test "drop-in: a drop-in that hangs costs its timeout, not the login" {
    mkdir -p "$SCRATCH/motd.d"
    printf '#!/bin/sh\nsleep 60\n' > "$SCRATCH/motd.d/50-hangs"
    chmod +x "$SCRATCH/motd.d/50-hangs"
    local start=$SECONDS
    DROPIN_ENV=KEEL_MOTD_TIMEOUT=1 DROPIN_LINES=60 run_dropin 'My Site'
    [ "$status" -eq 0 ]
    [ $((SECONDS - start)) -lt 10 ]
    has_mark
}

@test "drop-in: run while it measures the others, it prints nothing" {
    DROPIN_ENV=KEEL_BANNER_MEASURING=1 run_dropin 'My Site'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "drop-in: /etc/appname with a trailing newline names the appliance" {
    run_dropin $'My Site\n'
    [ "$status" -eq 0 ]
    [[ "$output" == *"My Site"* ]]
}

@test "drop-in: /etc/appname without a trailing newline still names it" {
    run_dropin 'My Site'
    [ "$status" -eq 0 ]
    [[ "$output" == *"My Site"* ]]
}
