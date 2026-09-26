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

@test "mark_size: the installed mark is 19 rows by 38 columns" {
    run keel_banner_mark_size "$KEEL_BANNER_MARK"
    [ "$output" = "19 38" ]
}

@test "mark_size: the small mark is 11 rows by 23 columns" {
    run keel_banner_mark_size "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "11 23" ]
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

@test "choose_mark: a tall terminal takes the full mark" {
    run keel_banner_choose_mark 40 80 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK" ]
}

@test "choose_mark: 80 by 24 falls back to the small mark" {
    run keel_banner_choose_mark 24 80 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

@test "choose_mark: a terminal of 30 columns falls back to the small mark" {
    run keel_banner_choose_mark 40 30 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

@test "choose_mark: a terminal of 20 columns takes no mark" {
    run keel_banner_choose_mark 40 20 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "choose_mark: a short terminal takes no mark" {
    run keel_banner_choose_mark 15 80 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$status" -eq 1 ]
}

@test "choose_mark: a mark file that is not there is skipped" {
    run keel_banner_choose_mark 40 80 7 "$SCRATCH/absent" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

@test "choose_mark: a taller address block pushes the choice down" {
    run keel_banner_choose_mark 30 80 7 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK" ]
    run keel_banner_choose_mark 30 80 11 "$KEEL_BANNER_MARK" \
        "$KEEL_BANNER_MARK_SMALL"
    [ "$output" = "$KEEL_BANNER_MARK_SMALL" ]
}

# the whole banner
#
# The bats $lines array drops empty lines (its IFS is a newline), so the
# rendered block is read into ROWS, where a blank row keeps its place.

rows_of() {
    mapfile -t ROWS < <(printf '%s\n' "$output")
}

@test "render: a dual stack appliance on a tall terminal" {
    run keel_banner_render 40 80 "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    local expected
    expected=$(cat "$KEEL_BANNER_MARK"
        printf '\nKeel Linux core 19.0-trixie-amd64\n\n'
        printf 'IPv6 Web:  https://[2001:db8:1::10]\n'
        printf 'IPv6 SSH:  root@2001:db8:1::10\n'
        printf 'IPv4 Web:  https://192.0.2.10\n'
        printf 'IPv4 SSH:  root@192.0.2.10\n')
    [ "$output" = "$expected" ]
    rows_of
    [ "${#ROWS[@]}" -eq 26 ]
}

@test "render: an IPv6 only appliance names no IPv4" {
    run keel_banner_render 40 80 "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10
    [[ $output != *IPv4* ]]
    rows_of
    [ "${#ROWS[@]}" -eq 24 ]
    [ "${ROWS[18]}" = "                  ==" ]
    [ "${ROWS[19]}" = "" ]
    [ "${ROWS[20]}" = "Keel Linux core 19.0-trixie-amd64" ]
    [ "${ROWS[21]}" = "" ]
    [ "${ROWS[22]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[23]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
}

@test "render: 80 by 24 uses the small mark and keeps the addresses" {
    run keel_banner_render 24 80 "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10 192.0.2.10
    rows_of
    [ "${#ROWS[@]}" -eq 18 ]
    [ "${ROWS[0]}" = "   ._______." ]
    [ "${ROWS[10]}" = "           .++." ]
    [ "${ROWS[12]}" = "Keel Linux core 19.0-trixie-amd64" ]
    [ "${ROWS[14]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[17]}" = "IPv4 SSH:  root@192.0.2.10" ]
}

@test "render: a terminal too small for any mark keeps the text" {
    run keel_banner_render 10 20 "Keel Linux core" 19.0-trixie-amd64 \
        2001:db8:1::10
    rows_of
    [ "${#ROWS[@]}" -eq 4 ]
    [ "${ROWS[0]}" = "Keel Linux core 1..." ]
    [ "${ROWS[2]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
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
    run keel_banner_render 24 80 "$name" 19.0-trixie-amd64 2001:db8:1::10
    rows_of
    [ "${#ROWS[@]}" -le 23 ]
    [ "${#ROWS[12]}" -eq 80 ]
    [ "${ROWS[14]}" = "IPv6 Web:  https://[2001:db8:1::10]" ]
    [ "${ROWS[15]}" = "IPv6 SSH:  root@2001:db8:1::10" ]
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
