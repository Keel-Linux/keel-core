#!/usr/bin/env bats
# Unit tests of overlay/usr/lib/keel/banner.sh: the version string, the
# title, the address block, the mark that fits and the whole rendered
# banner. Nothing here needs root, a network or a terminal: the mark files
# are the ones the overlay installs and the addresses are arguments.

bats_require_minimum_version 1.5.0

setup() {
    KEEL_BANNER_MARK="$BATS_TEST_DIRNAME/../overlay/etc/keel/banner.txt"
    KEEL_BANNER_MARK_SMALL="$BATS_TEST_DIRNAME/../overlay/etc/keel/banner-small.txt"
    load ../overlay/usr/lib/keel/banner.sh
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
    run keel_banner_render 40 80 "Keel Linux core" 19.0-trixie-amd64 \
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
    run keel_banner_render 40 "$cols" "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10
    rows_of
    assert_centred_rows "$cols" "$KEEL_BANNER_MARK"
}

@test "render: the title and the address lines stay at column one" {
    local mark_rows
    mark_rows=$(mark_rows_of "$KEEL_BANNER_MARK")
    run keel_banner_render 40 80 "Keel Linux core" 19.0-trixie-amd64 \
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
    run keel_banner_render 40 80 "Keel Linux core" 19.0-trixie-amd64 \
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
    run keel_banner_render "$rows" "$cols" "Keel Linux core" \
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
    run keel_banner_render 10 "$cols" "Keel Linux core" 19.0-trixie-amd64 \
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
    KEEL_BANNER_MARK="$SCRATCH/mark"
    KEEL_BANNER_MARK_SMALL="$SCRATCH/mark"
    printf '%s\n' AAAA '' BB > "$KEEL_BANNER_MARK"
    run keel_banner_render 40 10 core 19.0 2001:db8:1::10
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
        draw_mark "$SCRATCH/mark" "$rows" "$cols"
        KEEL_BANNER_MARK="$SCRATCH/mark"
        KEEL_BANNER_MARK_SMALL="$SCRATCH/mark"
        [ "$(keel_banner_mark_size "$SCRATCH/mark")" = "$rows $cols" ]

        # the smallest terminal this mark fits in, nine columns to spare
        term_rows=$((rows + body + KEEL_BANNER_RESERVED_ROWS))
        term_cols=$((cols + 9))
        run keel_banner_render "$term_rows" "$term_cols" core 19.0 \
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
        run keel_banner_render $((term_rows - 1)) "$term_cols" core 19.0 \
            2001:db8:1::10
        rows_of
        [ "${#ROWS[@]}" -eq $((body - 1)) ]
        [ "${ROWS[0]}" = "core 19.0" ]
        [ "${ROWS[2]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
        run keel_banner_render "$term_rows" $((cols - 1)) core 19.0 \
            2001:db8:1::10
        rows_of
        [ "${#ROWS[@]}" -eq $((body - 1)) ]
        [ "${ROWS[${#ROWS[@]} - 1]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
    done
}

@test "render: the block is plain ASCII with no escape character" {
    run keel_banner_render 40 80 "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    [[ $output != *$'\e'* ]]
    printf '%s\n' "$output" > "$SCRATCH/block"
    run ! env LC_ALL=C grep -q '[^ -~]' "$SCRATCH/block"
}

@test "render: a long hostname does not cost the addresses a line" {
    local name="Keel Linux forum-staging-eu-west-01.infrastructure.keellinux.org"
    local rows=24 cols=80 mark_rows
    mark_rows=$(chosen_mark_rows_of "$rows" "$cols" 5)
    run keel_banner_render "$rows" "$cols" "$name" 19.0-trixie-amd64 \
        2001:db8:1::10
    rows_of
    [ "${#ROWS[@]}" -eq $((mark_rows + 5)) ]
    [ "${#ROWS[@]}" -le $((rows - KEEL_BANNER_RESERVED_ROWS)) ]
    [ "${#ROWS[mark_rows + 1]}" -eq "$cols" ]
    [ "${ROWS[mark_rows + 3]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[mark_rows + 4]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
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

# what the overlay installs

@test "the default mark paths are the ones the overlay installs" {
    run env -u KEEL_BANNER_MARK -u KEEL_BANNER_MARK_SMALL bash -c \
        "source '$BATS_TEST_DIRNAME/../overlay/usr/lib/keel/banner.sh'
         echo \$KEEL_BANNER_MARK \$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "/etc/keel/banner.txt /etc/keel/banner-small.txt" ]
}

@test "the marks are plain ASCII with no escape character" {
    run ! env LC_ALL=C grep -q '[^ -~]' "$KEEL_BANNER_MARK"
    run ! env LC_ALL=C grep -q '[^ -~]' "$KEEL_BANNER_MARK_SMALL"
}
