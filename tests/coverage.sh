#!/bin/bash
# Line coverage of the project-authored shell of this repository, measured
# with kcov (decision 0004). Exits 1 when any measured file is below the
# threshold (default 95, the bar for project-authored code), 2 when a tool
# is missing.
#
#   COVERAGE_THRESHOLD=95 tests/coverage.sh
#
# COVERAGE_DIR keeps the kcov reports, one directory per bats file
# (default: a temporary directory). Needs the Debian packages bats and
# kcov. tests/boot-test.sh and overlay/etc/update-motd.d/* are the thin
# mains that run keel, LXC, ip and the system information command as
# root; they are exercised by the LXC run in test-appliance.yml, not
# measured here.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
threshold="${COVERAGE_THRESHOLD:-95}"

# Each entry is a bats file and the files it exercises, comma separated.
# One kcov run per bats file, however many files it measures: running the
# same suite once per file would double its time for no extra coverage.
suites=(
    "tests/boot-test.bats:tests/lib/boot-test-lib.sh"
    "tests/banner.bats:overlay/usr/lib/keel/banner.sh"
    "tests/motd.bats:overlay/usr/lib/keel/motd.sh,conf.d/main"
)

for tool in kcov bats; do
    if ! command -v "$tool" >/dev/null; then
        echo "$tool not found (apt-get install $tool)" >&2
        exit 2
    fi
done

reports="${COVERAGE_DIR:-$(mktemp -d)}"
failed=0

for suite in "${suites[@]}"; do
    bats_file="${suite%%:*}"
    measured="${suite#*:}"
    report="$reports/$(basename "$bats_file")"
    mkdir -p "$report"

    include=""
    IFS=, read -r -a files <<< "$measured"
    for file in "${files[@]}"; do
        include="${include:+$include,}$root/$file"
    done
    kcov --include-path="$include" "$report" bats "$root/$bats_file"

    json="$(find "$report" -name coverage.json -not -path '*/kcov-merged/*' | head -1)"
    for file in "${files[@]}"; do
        # kcov writes one line per measured file in the "files" array
        entry="$(grep -F "\"file\": \"$root/$file\"" "$json" || true)"
        if [ -z "$entry" ]; then
            echo "$file: kcov measured nothing (report: $report)" >&2
            failed=1
            continue
        fi
        percent="$(printf '%s' "$entry" | grep -o '"percent_covered": "[0-9.]*"' | grep -o '[0-9.]*')"
        covered="$(printf '%s' "$entry" | grep -o '"covered_lines": "[0-9]*"' | grep -o '[0-9]*')"
        total="$(printf '%s' "$entry" | grep -o '"total_lines": "[0-9]*"' | grep -o '[0-9]*')"

        echo "$file: $percent percent ($covered of $total lines) covered, threshold $threshold"
        if ! awk -v p="$percent" -v t="$threshold" 'BEGIN { exit !(p + 0 >= t + 0) }'; then
            echo "$file: coverage below threshold (report: $report)" >&2
            failed=1
        fi
    done
done

if [ "$failed" -ne 0 ]; then
    exit 1
fi
