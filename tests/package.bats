#!/usr/bin/env bats
# The keel-core package of packages/keel-core (handbook decision 0041, first
# implementation, step 4): built for real with dpkg-buildpackage, then its
# fields, its files and the manifest it ships read back. Needs dpkg-dev,
# debhelper and python3-yaml; no root, no network.

bats_require_minimum_version 1.5.0

PACKAGE_DIR="$BATS_TEST_DIRNAME/../packages/keel-core"

setup_file() {
    BUILD=$(mktemp -d)
    export BUILD
    cp -a "$PACKAGE_DIR" "$BUILD/src"
    (cd "$BUILD/src" && dpkg-buildpackage -us -uc -b >"$BUILD/build.log" 2>&1)
    DEB=$(ls "$BUILD"/keel-core_*_all.deb)
    export DEB
}

teardown_file() {
    rm -rf "$BUILD"
}

# the manifest as Python reads it, one expression per call
manifest() {
    python3 -c 'import sys, yaml
m = yaml.safe_load(open(sys.argv[1]))
print(eval(sys.argv[2]))' "$PACKAGE_DIR/manifest.yaml" "$1"
}

# the package

@test "one binary package, keel-core, architecture all" {
    run dpkg-deb -f "$DEB" Package Architecture
    [ "$status" -eq 0 ]
    [ "$output" = $'Package: keel-core\nArchitecture: all' ]
}

@test "it depends on the five Core overlays and on the keel of the VIP" {
    run dpkg-deb -f "$DEB" Depends
    [ "$status" -eq 0 ]
    [ "$output" = "keel (>= 0.20.0), keel-overlay-crowdsec, keel-overlay-etcd, keel-overlay-installer, keel-overlay-vip (>= 0.1.1), keel-overlay-wireguard" ]
}

@test "the manifest is installed as /usr/share/keel/appliances/core.yaml" {
    dpkg-deb -x "$DEB" "$BUILD/root"
    cmp "$PACKAGE_DIR/manifest.yaml" "$BUILD/root/usr/share/keel/appliances/core.yaml"
}

@test "the manifest is a plain file of mode 0644, owned by root" {
    run bash -c "dpkg-deb -c '$DEB' | grep ' ./usr/share/keel/appliances/core.yaml$'"
    [ "$status" -eq 0 ]
    [[ "$output" == "-rw-r--r-- root/root "* ]]
}

@test "it installs the manifest, monit's ordering and its documentation" {
    run bash -c "dpkg-deb -c '$DEB' | awk '{print \$6}' | grep -v '/\$' | sort"
    [ "$status" -eq 0 ]
    [ "$output" = $'./usr/lib/systemd/system/monit.service.d/keel-core.conf\n./usr/share/doc/keel-core/changelog.gz\n./usr/share/doc/keel-core/copyright\n./usr/share/keel/appliances/core.yaml' ]
}

# keel#61: monit's first cycle after boot found webmin and postfix
# inactive, because monit started beside them; its checks are the units
# of the manifest's processes, so monit starts after those units
@test "monit starts after the units of Core's processes, and only that" {
    dpkg-deb -x "$DEB" "$BUILD/root"
    dropin="$BUILD/root/usr/lib/systemd/system/monit.service.d/keel-core.conf"
    run grep -v '^#' "$dropin"
    [ "$status" -eq 0 ]
    [ "$output" = $'[Unit]\nAfter=ssh.service webmin.service postfix.service' ]
    units=$(manifest '" ".join(p["unit"] for p in m["processes"])')
    [ "$(sed -n 's/^After=//p' "$dropin")" = "$units" ]
}

@test "monit's ordering is a plain file of mode 0644, owned by root" {
    run bash -c "dpkg-deb -c '$DEB' | grep ' ./usr/lib/systemd/system/monit.service.d/keel-core.conf$'"
    [ "$status" -eq 0 ]
    [[ "$output" == "-rw-r--r-- root/root "* ]]
}

@test "systemd reads the ordering without a complaint" {
    if ! command -v systemd-analyze >/dev/null; then
        skip "systemd-analyze is not installed"
    fi
    dpkg-deb -x "$DEB" "$BUILD/root"
    mkdir -p "$BUILD/units"
    printf '[Service]\nExecStart=/bin/true\n' > "$BUILD/units/monit.service"
    mkdir -p "$BUILD/units/monit.service.d"
    cp "$BUILD/root/usr/lib/systemd/system/monit.service.d/keel-core.conf" \
        "$BUILD/units/monit.service.d/"
    run systemd-analyze verify --man=no "$BUILD/units/monit.service"
    [[ "$output" != *"keel-core.conf"* ]]
}

# the manifest: the Core table of decision 0041

@test "manifest: an appliance named core, version 1, on no base" {
    run manifest '(m["manifest_version"], m["kind"], m["name"], m["base"])'
    [ "$status" -eq 0 ]
    [ "$output" = "(1, 'appliance', 'core', 'none')" ]
}

@test "manifest: installer is enabled in every mode" {
    run manifest 'm["overlays"]["installer"]'
    [ "$output" = "{'simple': 'enabled', 'cloud_simple': 'enabled', 'cloud_advanced': 'enabled'}" ]
}

@test "manifest: wireguard is disabled in simple and enabled in the cloud modes" {
    run manifest 'm["overlays"]["wireguard"]'
    [ "$output" = "{'simple': 'disabled', 'cloud_simple': 'enabled', 'cloud_advanced': 'enabled'}" ]
}

@test "manifest: etcd is enabled in cloud advanced only" {
    run manifest 'm["overlays"]["etcd"]'
    [ "$output" = "{'simple': 'disabled', 'cloud_simple': 'disabled', 'cloud_advanced': 'enabled'}" ]
}

@test "manifest: crowdsec is disabled in simple and enabled in the cloud modes" {
    run manifest 'm["overlays"]["crowdsec"]'
    [ "$output" = "{'simple': 'disabled', 'cloud_simple': 'enabled', 'cloud_advanced': 'enabled'}" ]
}

@test "manifest: vip is disabled in every mode, keel enables it only for appliance.vip" {
    run manifest 'm["overlays"]["vip"]'
    [ "$output" = "{'simple': 'disabled', 'cloud_simple': 'disabled', 'cloud_advanced': 'disabled'}" ]
}

@test "manifest: exactly the five overlays of Core" {
    run manifest 'sorted(m["overlays"])'
    [ "$output" = "['crowdsec', 'etcd', 'installer', 'vip', 'wireguard']" ]
}

# TurnKey removed the web shell (shellinabox, port 12320) in 18.0, and
# common 19.x installs none: a process naming shellinabox.service fails
# keel manifest validate on the built image (rule 5), and with it every
# spec that names the appliance. Webmin's own terminal replaces it.
@test "manifest: sshd, webmin and postfix, with their units, and no web shell" {
    run manifest '[(p["name"], p["unit"]) for p in m["processes"]]'
    [ "$output" = "[('sshd', 'ssh.service'), ('webmin', 'webmin.service'), ('postfix', 'postfix.service')]" ]
}

@test "manifest: 22 and 12321 public, 25 on the IPv4 loopback" {
    run manifest '[(l.get("address"), l["port"], l["expose"]) for p in m["processes"] for l in p["listen"]]'
    [ "$output" = "[(None, 22, 'public'), (None, 12321, 'public'), ('127.0.0.1', 25, 'loopback')]" ]
}

@test "manifest: the ssh, HTTPS and SMTP probes, each restarting" {
    run manifest '[(c["name"], c["type"], c.get("protocol"), c["port"], c["on_failure"]) for c in m["checks"]]'
    [ "$output" = "[('sshd', 'protocol', 'ssh', 22, 'restart'), ('webmin', 'http', None, 12321, 'restart'), ('postfix', 'protocol', 'smtp', 25, 'restart')]" ]
}

@test "manifest: the root password is its one secret, never shared" {
    run manifest '[(s["name"], s["generate"], s["shared"]) for s in m["secrets"]]'
    [ "$output" = "[('root_password', 'allowed', False)]" ]
}
