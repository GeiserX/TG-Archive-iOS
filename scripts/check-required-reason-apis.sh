#!/usr/bin/env bash
# Fails when the app's sources use a Required Reason API that PrivacyInfo.xcprivacy does not declare.
# The manifest declares only UserDefaults (CA92.1), so file timestamps, boot time and disk space are off limits.
#   scripts/check-required-reason-apis.sh [dir]     check dir (default: TGArchive)
#   scripts/check-required-reason-apis.sh --self-test   prove the check can fail, on a planted file
set -euo pipefail

PATTERN='creationDate|modificationDate|contentModificationDateKey|systemUptime|volumeAvailableCapacity|volumeAvailableCapacityForImportantUsage|volumeAvailableCapacityForOpportunisticUsage|volumeTotalCapacity|statfs|mach_absolute_time'

check() {
    local dir="$1" hits
    [[ -d "$dir" ]] || { echo "no such directory: $dir" >&2; return 2; }
    # grep exits 1 on no match and 2 on an error; only a match (0) or an error fails the check.
    if hits=$(grep -rnE --include='*.swift' --include='*.m' --include='*.h' --include='*.c' "$PATTERN" "$dir"); then
        echo "Required Reason APIs not declared in PrivacyInfo.xcprivacy:" >&2
        echo "$hits" >&2
        return 1
    elif [[ $? -ne 1 ]]; then
        echo "grep failed on $dir" >&2
        return 2
    fi
    echo "no undeclared Required Reason APIs in $dir"
}

if [[ "${1:-}" == "--self-test" ]]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    printf 'let d = attrs[.creationDate]\n' > "$tmp/Planted.swift"
    set +e
    check "$tmp" 2>/dev/null
    status=$?
    set -e
    if [[ $status -ne 1 ]]; then
        echo "self-test FAILED: the check exited $status on a planted creationDate, expected 1" >&2
        exit 1
    fi
    echo "self-test: the check can fail"
    exit 0
fi

check "${1:-TGArchive}"
