#!/bin/sh
# Runs the headless test suite in parallel (8 at a time), one log per test, and
# prints the ones that failed (non-zero exit, a FAIL line, or a script error).
#   tools/run_tests.sh                    # every tests/test_*.gd but the perf test
#   tools/run_tests.sh tests/test_kegs.gd tests/test_rally.gd
# Logs go to .godot/test_logs/ (or $SUNDANCE_LOGS). The tests are deterministic, so
# one that fails here but passes alone means wall-clock time is leaking into the
# game (see CLAUDE.md).
# The longest tests start first (by how long each took last time, kept in
# .godot/test_times; a new one counts as long), so the suite doesn't end on one
# slow test running alone while the other slots sit idle.
cd "$(dirname "$0")/.." || exit 1
LOGS=${SUNDANCE_LOGS:-.godot/test_logs}
TIMES=.godot/test_times
rm -rf "$LOGS" && mkdir -p "$LOGS" && touch "$TIMES"
export LOGS
if [ $# -gt 0 ]; then
	TESTS="$*"
else
	TESTS=$(ls tests/test_*.gd | grep -v perf)
fi
for t in $TESTS; do
	echo "$(awk -v n="$(basename "$t" .gd)" '$2 == n { s = $1 } END { print (s == "" ? 99999 : s) }' "$TIMES") $t"
done | sort -rn | cut -d' ' -f2 | xargs -P 8 -I {} sh -c '
	n=$(basename {} .gd)
	s=$(date +%s)
	godot --headless --path . --fixed-fps 60 -s {} > "$LOGS/$n.log" 2>&1
	echo $? > "$LOGS/$n.exit"
	echo "$(($(date +%s) - s)) $n" > "$LOGS/$n.secs"'
cat "$LOGS"/*.secs "$TIMES" 2>/dev/null | awk '!seen[$2]++' > "$TIMES.new" && mv "$TIMES.new" "$TIMES"
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
