#!/usr/bin/env bash
# Fails when the app's sources use a Required Reason API that PrivacyInfo.xcprivacy does not declare.
# The manifest declares only UserDefaults (CA92.1), so file timestamps, boot time, disk space and active
# keyboards are off limits. The names follow Apple's list of Required Reason APIs.
#   scripts/check-required-reason-apis.sh [dir]     check dir (default: TGArchive)
#   scripts/check-required-reason-apis.sh --self-test   prove the check can fail, on a planted file
set -euo pipefail

PATTERN='creationDate|modificationDate|ModificationDate|getattrlist|\b(f|l)?stat(at)?\(|systemUptime|mach_absolute_time|volumeAvailableCapacity|volumeTotalCapacity|statfs|statvfs|systemFreeSize|systemSize|activeInputModes'

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
    # Each planted line must make the check fail on its own.
    planted=(
        'let d = attrs[.creationDate]'
        'let m = values.contentModificationDate'
        'if stat(path, &info) == 0 {}'
        'let up = ProcessInfo.processInfo.systemUptime'
        'let free = values.volumeAvailableCapacityForImportantUsage'
    )
    for i in "${!planted[@]}"; do
        mkdir "$tmp/$i"
        printf '%s\n' "${planted[$i]}" > "$tmp/$i/Planted.swift"
        set +e; check "$tmp/$i" >/dev/null 2>&1; status=$?; set -e
        if [[ $status -ne 1 ]]; then
            echo "self-test FAILED: the check exited $status on '${planted[$i]}', expected 1" >&2
            exit 1
        fi
    done
    # A clean file must pass, so the pattern is not red on ordinary code.
    mkdir "$tmp/clean"
    printf '%s\n' 'let status = response.statusCode' 'let stats = ArchiveStats()' > "$tmp/clean/Clean.swift"
    if ! check "$tmp/clean" >/dev/null 2>&1; then
        echo "self-test FAILED: the check flagged a clean file" >&2
        exit 1
    fi
    echo "self-test: the check can fail"
    exit 0
fi

check "${1:-TGArchive}"
