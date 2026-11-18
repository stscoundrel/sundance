#!/bin/sh
# Bakes a sample of the assets (the sounds, the UI, the effects and one body) and fails if
# any of it draws or sounds different. Every sprite and sound is the tools' work, so this
# is how a new numpy, pillow or soundfile (a Dependabot bump) shows whether it changes the
# game's look.
#   tools/check_bake.sh                   # against what's committed (on the machine the
#                                         # assets were baked on: run it after a bump)
#   tools/check_bake.sh --against DIR     # against the same sample baked in DIR, another
#                                         # checkout (the pull request's base: what CI runs)
# $PYTHON bakes here (tools/.venv by default), $BASE_PYTHON in DIR (default $PYTHON), so
# each side can have its own packages. Comparing two bakes on one machine is the fair
# test on a runner: there a bake rounds a few pixels differently from the Mac the assets
# were baked on, whatever the versions. Here is put back as committed afterwards.
cd "$(dirname "$0")/.." || exit 1
abs() { case "$1" in */*) echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")" ;; *) echo "$1" ;; esac; }
PY=$(abs "${PYTHON:-tools/.venv/bin/python}")
if [ -n "$(git status --porcelain -- assets)" ]; then
	echo "assets/ has changes of its own: commit or stash them first"
	exit 2
fi
sample() {   # bake the sample in the checkout $1 with the Python $2
	(cd "$1" && touch assets/.bake_stamp \
		&& "$2" tools/gen_assets.py fx ui sfx \
		&& SUNDANCE_TEMPLATES=vest "$2" tools/gen_assets.py chars)
}
if [ "$1" = "--against" ]; then
	BASE=$(cd "$2" && pwd) || exit 2
	BASE_PY=$(abs "${BASE_PYTHON:-$PY}")
	# Both sides start from the base's manifest, so the only differences in it are what
	# the two bakes write.
	cp "$BASE/assets/meta.json" assets/meta.json
	echo "== the base's bake ($BASE)"
	sample "$BASE" "$BASE_PY" || exit 1
	echo "== this checkout's bake"
	sample . "$PY" || exit 1
	"$PY" tools/check_bake.py "$BASE" .
	ok=$?
	what="the base's"
else
	sample . "$PY" || exit 1
	rm -f assets/.bake_stamp
	"$PY" tools/check_bake.py
	ok=$?
	what="what's committed"
fi
rm -f assets/.bake_stamp
git checkout -q -- assets && git clean -fdq -- assets
[ $ok -eq 0 ] || exit 1
echo "bake check: OK (fx, ui, sfx and the vest body come out as $what)"
