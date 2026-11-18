#!/bin/sh
# Bakes a sample of the assets (the sounds, the UI, the effects and one body) and fails if
# any of it comes out different from what's committed. Every sprite and sound is the
# tools' work, so this is how a new numpy, pillow or soundfile (a Dependabot bump) shows
# whether it changes the game's look: run it after installing the new versions.
#   tools/check_bake.sh                   # with tools/.venv
#   PYTHON=python3 tools/check_bake.sh    # with another interpreter (CI)
# A clean checkout is needed: it compares against git, and puts the baked files back.
cd "$(dirname "$0")/.." || exit 1
PY=${PYTHON:-tools/.venv/bin/python}
if [ -n "$(git status --porcelain -- assets)" ]; then
	echo "assets/ has changes of its own: commit or stash them first"
	exit 2
fi
"$PY" tools/gen_assets.py fx ui sfx || exit 1
SUNDANCE_TEMPLATES=vest "$PY" tools/gen_assets.py chars || exit 1
"$PY" tools/check_bake.py
ok=$?
git checkout -q -- assets && git clean -fdq -- assets
[ $ok -eq 0 ] || exit 1
echo "bake check: OK (fx, ui, sfx and the vest body come out as committed)"
