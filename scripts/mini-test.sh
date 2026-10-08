#!/usr/bin/env bash
# Builds and tests this checkout on a Mac with Xcode over ssh, so the editing machine never runs xcodebuild.
# It copies the checkout to the build Mac, generates the project, runs the unit and UI tests on a simulator,
# and fails unless the result bundle counts at least MIN_TESTS tests and none failed, the same gate as CI.
#   scripts/mini-test.sh
# Env:
#   MINI_HOST           ssh destination of the build Mac (required, for example a host alias from ~/.ssh/config)
#   MINI_ROOT           scratch folder on it (default tg-archive-ios-build, relative to the remote home)
#   MINI_LANE           subfolder for this checkout (default: the checkout's folder name); the sources go to
#                       $MINI_ROOT/$MINI_LANE/src, the results to .../build and the full log to .../test.log
#   MIN_TESTS           lowest acceptable totalTestCount (default: the floor in .github/workflows/ci.yml)
#   TGARCHIVE_DEMO_URL  demo server address handed to the test run (the UI tests read it)
set -euo pipefail

cd "$(dirname "$0")/.."
MINI_HOST=${MINI_HOST:?set MINI_HOST to the ssh destination of the build Mac}
MINI_ROOT=${MINI_ROOT:-tg-archive-ios-build}
MINI_LANE=${MINI_LANE:-$(basename "$PWD")}
if [[ -z "${MIN_TESTS:-}" ]]; then
    MIN_TESTS=$(sed -n 's/.*total >= \([0-9][0-9]*\) and failed == 0.*/\1/p' .github/workflows/ci.yml)
    [[ -n "$MIN_TESTS" ]] || { echo "could not read the test-count floor from ci.yml; set MIN_TESTS" >&2; exit 2; }
fi
LANE_DIR="$MINI_ROOT/$MINI_LANE"

ssh "$MINI_HOST" "mkdir -p $(printf '%q' "$LANE_DIR/src")"
rsync -a --delete --exclude .git --exclude build --exclude '*.xcodeproj' --exclude demo-data --exclude demo-src ./ "$MINI_HOST:$LANE_DIR/src/"

# shellcheck disable=SC2029 # the arguments are quoted here on purpose and expanded by the remote shell
ssh "$MINI_HOST" "bash -s -- $(printf '%q ' "$LANE_DIR" "$MIN_TESTS" "${TGARCHIVE_DEMO_URL:-}")" <<'REMOTE'
# Wrapped in a function so bash reads the whole script before running it: a command that reads stdin
# would otherwise swallow the rest of the script.
main() {
set -euo pipefail
lane_dir=$1 min_tests=$2 demo_url=$3
cd "$lane_dir/src"
xcodegen generate --quiet
udid=$(scripts/pick-simulator.sh)
rm -rf "$lane_dir/build/results.xcresult"
mkdir -p "$lane_dir/build"
echo "testing on simulator $udid, at least $min_tests tests"

# xcodebuild hands TEST_RUNNER_<NAME> to the test process as <NAME>.
set +e
TEST_RUNNER_TGARCHIVE_DEMO_URL="$demo_url" xcodebuild test \
    -project TGArchive.xcodeproj -scheme TGArchive \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$lane_dir/build/dd" -resultBundlePath "$lane_dir/build/results.xcresult" \
    -parallel-testing-enabled NO >"$lane_dir/test.log" 2>&1
build_status=$?
set -e

grep -a -E "error:|Test Case .* failed|✘" "$lane_dir/test.log" | head -n 40 || true
# The XCTest summary lines are indented with a tab, so match leading whitespace.
grep -a -E "^[[:space:]]*Executed [0-9]+ tests?|Test run with [0-9]+ tests?|\*\* TEST (SUCCEEDED|FAILED)" "$lane_dir/test.log" || true

if [[ ! -d "$lane_dir/build/results.xcresult" ]]; then
    echo "no result bundle: the build failed before any test ran (full log: $lane_dir/test.log)" >&2
    exit 1
fi
xcrun xcresulttool get test-results summary --path "$lane_dir/build/results.xcresult" --compact \
    | python3 -c '
import json, sys
s = json.load(sys.stdin)
total, failed, floor = s.get("totalTestCount", 0), s.get("failedTests", 0), int(sys.argv[1])
print(f"totalTestCount={total} failedTests={failed} (floor {floor})")
sys.exit(0 if total >= floor and failed == 0 else 1)
' "$min_tests"
exit "$build_status"
}
main "$@"
REMOTE
