#!/bin/bash
# Line coverage of tests/lib/boot-test-lib.sh under tests/boot-test.bats,
# measured with kcov (decision 0004). Exits 1 when the covered share of
# the library is below the threshold (default 95, the bar for
# project-authored code), 2 when a tool is missing.
#
#   COVERAGE_THRESHOLD=95 tests/coverage.sh
#
# COVERAGE_DIR keeps the kcov report (default: a temporary directory).
# Needs the Debian packages bats and kcov. boot-test.sh itself is the thin
# main that runs keel and LXC as root; it is exercised by the LXC run in
# test-appliance.yml, not measured here.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$here/lib/boot-test-lib.sh"
threshold="${COVERAGE_THRESHOLD:-95}"

for tool in kcov bats; do
    if ! command -v "$tool" >/dev/null; then
        echo "$tool not found (apt-get install $tool)" >&2
        exit 2
    fi
done

report="${COVERAGE_DIR:-$(mktemp -d)}"
kcov --include-path="$target" "$report" bats "$here/boot-test.bats"

# with --include-path the report holds one file, so its first entry is ours
json="$(find "$report" -name coverage.json -not -path '*/kcov-merged/*' | head -1)"
percent="$(grep -o '"percent_covered": "[0-9.]*"' "$json" | head -1 | grep -o '[0-9.]*')"
covered="$(grep -o '"covered_lines": "[0-9]*"' "$json" | head -1 | grep -o '[0-9]*')"
total="$(grep -o '"total_lines": "[0-9]*"' "$json" | head -1 | grep -o '[0-9]*')"

echo "boot-test-lib.sh: $percent percent ($covered of $total lines) covered, threshold $threshold"
if ! awk -v p="$percent" -v t="$threshold" 'BEGIN { exit !(p + 0 >= t + 0) }'; then
    echo "coverage below threshold (report: $report)" >&2
    exit 1
fi
