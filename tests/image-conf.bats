#!/usr/bin/env bats
# Unit tests of conf.d/main, the conf script fab runs in the image chroot.
# It is run here against a scratch tree through KEEL_CONF_ROOT, so nothing
# needs root, a chroot or the packages themselves: the files are made the
# way the Debian packages' maintainer scripts leave them.

bats_require_minimum_version 1.5.0

CONF="$BATS_TEST_DIRNAME/../conf.d/main"

# what the postinst of crowdsec 1.4.6 and crowdsec-firewall-bouncer 0.0.25
# write in an image build (tracker#47)
IDENTITY=(
    etc/crowdsec/local_api_credentials.yaml
    etc/crowdsec/online_api_credentials.yaml
    etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local
    etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.id
    var/lib/crowdsec/data/crowdsec.db
    var/lib/crowdsec/pending-registration
)

setup() {
    ROOT=$(mktemp -d)
    export KEEL_CONF_ROOT="$ROOT"
    mkdir -p "$ROOT/etc/wireguard" "$ROOT/etc/systemd/system/multi-user.target.wants"
}

teardown() {
    rm -rf "$ROOT"
}

crowdsec_installed() {
    local path
    for path in "${IDENTITY[@]}"; do
        mkdir -p "$ROOT/${path%/*}"
        echo "secret of $path" > "$ROOT/$path"
    done
    echo "listen_uri: 127.0.0.1:8080" > "$ROOT/etc/crowdsec/config.yaml"
    echo "mode: nftables" > "$ROOT/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
}

# the image as it should be

@test "a tree with no WireGuard key, no wg-quick@ unit and no CrowdSec passes" {
    run bash "$CONF"
    [ "$status" -eq 0 ]
}

@test "a tree with no /etc/wireguard at all passes" {
    rmdir "$ROOT/etc/wireguard"
    run bash "$CONF"
    [ "$status" -eq 0 ]
}

@test "a tree with no multi-user.target.wants passes" {
    rmdir "$ROOT/etc/systemd/system/multi-user.target.wants"
    run bash "$CONF"
    [ "$status" -eq 0 ]
}

# WireGuard: the guards of #16, kept

@test "a file in /etc/wireguard fails the build" {
    echo key > "$ROOT/etc/wireguard/wg0.key"
    run bash "$CONF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"/etc/wireguard is not empty in the image"* ]]
}

@test "a hidden file in /etc/wireguard fails the build" {
    echo key > "$ROOT/etc/wireguard/.wg0.key"
    run bash "$CONF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"/etc/wireguard is not empty in the image"* ]]
}

@test "an enabled wg-quick@ unit fails the build" {
    ln -s /usr/lib/systemd/system/wg-quick@.service \
        "$ROOT/etc/systemd/system/multi-user.target.wants/wg-quick@wg0.service"
    run bash "$CONF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"a wg-quick@ unit is enabled in the image"* ]]
}

@test "another enabled unit is not taken for a wg-quick@ one" {
    ln -s /usr/lib/systemd/system/ssh.service \
        "$ROOT/etc/systemd/system/multi-user.target.wants/ssh.service"
    run bash "$CONF"
    [ "$status" -eq 0 ]
}

# CrowdSec: no identity in the image (tracker#47)

@test "every CrowdSec identity file is deleted" {
    crowdsec_installed
    run bash "$CONF"
    [ "$status" -eq 0 ]
    local path left=""
    for path in "${IDENTITY[@]}"; do
        [ ! -e "$ROOT/$path" ] || left="$left $path"
    done
    [ -z "$left" ]
}

@test "each deletion is said in the build log" {
    crowdsec_installed
    run bash "$CONF"
    [ "$status" -eq 0 ]
    local path missing=""
    for path in "${IDENTITY[@]}"; do
        [[ "$output" == *"removed /$path"* ]] || missing="$missing $path"
    done
    [ -z "$missing" ]
}

@test "CrowdSec's configuration and the bouncer's are kept" {
    crowdsec_installed
    run bash "$CONF"
    [ "$status" -eq 0 ]
    [ "$(cat "$ROOT/etc/crowdsec/config.yaml")" = "listen_uri: 127.0.0.1:8080" ]
    [ "$(cat "$ROOT/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml")" = "mode: nftables" ]
}

@test "a tree that holds only some of the identity files passes and loses them" {
    mkdir -p "$ROOT/var/lib/crowdsec"
    echo "crowdsec-firewall-bouncer FirewallBouncer-x 0123" \
        > "$ROOT/var/lib/crowdsec/pending-registration"
    run bash "$CONF"
    [ "$status" -eq 0 ]
    [ ! -e "$ROOT/var/lib/crowdsec/pending-registration" ]
}

@test "a SQLite journal beside the database goes with it" {
    crowdsec_installed
    echo wal > "$ROOT/var/lib/crowdsec/data/crowdsec.db-wal"
    echo shm > "$ROOT/var/lib/crowdsec/data/crowdsec.db-shm"
    echo journal > "$ROOT/var/lib/crowdsec/data/crowdsec.db-journal"
    run bash "$CONF"
    [ "$status" -eq 0 ]
    [ ! -e "$ROOT/var/lib/crowdsec/data/crowdsec.db-wal" ]
    [ ! -e "$ROOT/var/lib/crowdsec/data/crowdsec.db-shm" ]
    [ ! -e "$ROOT/var/lib/crowdsec/data/crowdsec.db-journal" ]
}

@test "an identity path that cannot be deleted fails the build" {
    mkdir -p "$ROOT/etc/crowdsec/local_api_credentials.yaml/held"
    run bash "$CONF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FATAL: /etc/crowdsec/local_api_credentials.yaml is still in the image"* ]]
}
