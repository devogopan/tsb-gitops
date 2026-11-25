#!/bin/sh
# Sets RUN_ID in every steps/*/shared/config.yaml, so all preflight steps re-run with the same id.
#   ./set-run-id.sh run-012          change it
#   ./set-run-id.sh                  only show the current values
# Then: git diff, commit, push.
set -eu
cd "$(dirname "$0")"

FILES=$(ls steps/*/shared/config.yaml)

if [ $# -eq 0 ]; then
  grep -H '^  RUN_ID:' $FILES
  exit 0
fi

NEW="$1"
# it becomes part of a ConfigMap name: lower-case letters, digits and "-" only
case "$NEW" in
  ''|*[!a-z0-9-]*|-*|*-) echo "invalid RUN_ID '$NEW': use lower-case letters, digits and '-' (example: run-012)"; exit 1 ;;
esac

for f in $FILES; do
  grep -q '^  RUN_ID: ' "$f" || { echo "no RUN_ID line in $f, nothing changed after this point"; exit 1; }
  tmp="$(mktemp)"
  sed -E "s/^  RUN_ID: .*/  RUN_ID: \"$NEW\"/" "$f" > "$tmp"
  cat "$tmp" > "$f"
  echo "updated $f"
done

echo "--- check ---"
grep -H '^  RUN_ID:' $FILES
N=$(grep -h '^  RUN_ID:' $FILES | sort -u | wc -l | tr -d ' ')
[ "$N" = "1" ] || { echo "ERROR: the files do not all have the same RUN_ID"; exit 1; }
echo "OK: all $(echo "$FILES" | wc -l | tr -d ' ') files have RUN_ID \"$NEW\". Now commit and push."
