#!/bin/sh
# Runs the headless test suite in parallel (8 at a time), one log per test, and
# prints the ones that failed (non-zero exit, a FAIL line, or a script error).
#   tools/run_tests.sh                    # every tests/test_*.gd but the perf test
#   tools/run_tests.sh tests/test_kegs.gd tests/test_rally.gd
# Logs go to .godot/test_logs/ (or $SUNDANCE_LOGS). Heavy parallel load makes a
# few behaviour tests wobble now and then (test_downed most often): rerun a lone
# failure on its own before believing it.
cd "$(dirname "$0")/.." || exit 1
LOGS=${SUNDANCE_LOGS:-.godot/test_logs}
rm -rf "$LOGS" && mkdir -p "$LOGS"
export LOGS
if [ $# -gt 0 ]; then
	TESTS="$*"
else
	TESTS=$(ls tests/test_*.gd | grep -v perf)
fi
printf '%s\n' $TESTS | xargs -P 8 -I {} sh -c '
	n=$(basename {} .gd)
	godot --headless --path . --fixed-fps 60 -s {} > "$LOGS/$n.log" 2>&1
	echo $? > "$LOGS/$n.exit"'
bad=0
for f in "$LOGS"/*.log; do
	n=$(basename "$f" .log)
	if [ "$(cat "$LOGS/$n.exit")" != 0 ] || grep -q "FAIL\|SCRIPT ERROR" "$f"; then
		echo "FAILED $n"
		grep -m 5 "FAIL\|SCRIPT ERROR" "$f" | sed 's/^/    /'
		bad=$((bad + 1))
	fi
done
echo "$(ls "$LOGS"/*.log | wc -l | tr -d ' ') tests, $bad failed (logs in $LOGS)"
[ $bad -eq 0 ]
