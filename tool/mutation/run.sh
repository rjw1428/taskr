#!/usr/bin/env bash
# Mutation-tests the pure-logic files, one target at a time.
#
#   tool/mutation/run.sh                # every target
#   tool/mutation/run.sh goal_planning  # one target (name of a file in targets/)
#
# Each target pairs one source file with only the test files that exercise it,
# so a killed mutant costs seconds rather than a full-suite run. Targets run
# sequentially on purpose: the tool mutates files in place, so parallel runs
# would compile each other's mutants. Reports land in tool/mutation/report/.
#
# Requires: dart pub global activate mutation_test
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$PATH:$HOME/.pub-cache/bin"
command -v mutation_test >/dev/null || { echo "run: dart pub global activate mutation_test" >&2; exit 1; }

if [ -n "$(git status --porcelain lib)" ]; then
  echo "note: lib/ has uncommitted changes; the tool restores files it mutates, but commit or stash first if you want a clean safety net." >&2
fi

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=($(ls tool/mutation/targets | sed 's/\.xml$//'))

status=0
for t in "${targets[@]}"; do
  echo "===== $t"
  mutation_test -q -f md -o "tool/mutation/report/$t" "tool/mutation/targets/$t.xml" || status=1
  grep -E '^\| (Total|Undetected|Elapsed) ' "tool/mutation/report/$t/mutation-test-report.md" | tr -s ' '
  sed -n '/^## Undetected/,$p' "tool/mutation/report/$t/mutation-test-report.md" | grep -oE '^Line [0-9]+' | sed 's/^/  survived: /' || true
done

echo
echo "reports: tool/mutation/report/<target>/mutation-test-report.md"
exit $status
