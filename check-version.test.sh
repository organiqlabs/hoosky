#!/usr/bin/env bash
# check-version.sh cases. No network: each case builds a scratch dir, copies the
# checker and installer into it, and runs the checker there. Prints
# "all tests passed (N tests)" and exits 0, or "FAILURES (N tests)" and exits 1.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/check-version.sh"
INSTALLER="$HERE/install.sh"

TOTAL=0
FAILED=0
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILED=$((FAILED + 1))
}

newcase() {  # <name> -> fresh dir in $CASE, checker+installer copied in
  CASE="$(mktemp -d "$WORK/case.XXXXXX")" || { printf 'FAIL: mktemp\n' >&2; exit 1; }
  cp "$CHECKER" "$INSTALLER" "$CASE/"
}

gitcase() {  # stage everything so the files count as tracked
  git -C "$CASE" init -q &&
    git -C "$CASE" add -A &&
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$CASE" -c user.email=t@t -c user.name=t commit -qm init
}

run() {  # -> sets OUTPUT, ERR, RC
  OUTPUT="$(cd "$CASE" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null bash ./check-version.sh 2>"$CASE/.err")"
  RC=$?
  ERR="$(cat "$CASE/.err")"
}

WORK="$(mktemp -d)" || { printf 'check-version.test: mktemp failed\n' >&2; exit 1; }

# 1. Matching tree passes and says so.
TOTAL=$((TOTAL + 1))
newcase matching
printf 'See v9.9.9 docs.\n' > "$CASE/notes.md"
sed 's/^TAG="v[0-9.]*"$/TAG="v9.9.9"/' "$CASE/install.sh" > "$CASE/.tag" && mv "$CASE/.tag" "$CASE/install.sh"
gitcase || fail "1: git setup"
run
[ "$RC" -eq 0 ] || fail "1: expected rc 0, got $RC ($ERR)"
case "$OUTPUT" in *'match TAG=v9.9.9'*) : ;; *) fail "1: missing success line: $OUTPUT" ;; esac

# 2. A second reference fails with the mismatching version named.
TOTAL=$((TOTAL + 1))
newcase mismatch
printf 'See v1.2.3 docs.\n' > "$CASE/notes.md"
gitcase || fail "2: git setup"
run
[ "$RC" -eq 1 ] || fail "2: expected rc 1, got $RC"
case "$ERR" in *v1.2.3*) : ;; *) fail "2: stderr did not name v1.2.3: $ERR" ;; esac

# 3. Gitignored files never reach the gate (tracked-only scan, T013).
TOTAL=$((TOTAL + 1))
newcase ignored
printf 'notes.md\n' > "$CASE/.gitignore"
printf 'scratch v8.8.8\n' > "$CASE/notes.md"
gitcase || fail "3: git setup"
run
[ "$RC" -eq 0 ] || fail "3: ignored file failed the gate: rc=$RC ($ERR)"

# 4. Outside a work tree the scan cannot run: fail, never a vacuous pass (T014).
TOTAL=$((TOTAL + 1))
newcase nonrepo
run
[ "$RC" -eq 1 ] || fail "4: expected rc 1 in a non-repo, got $RC ($OUTPUT)"
case "$ERR" in *'could not scan tracked files'*|*'scan found no version references'*) : ;;
  *) fail "4: stderr did not explain the failed scan: $ERR" ;; esac
case "$OUTPUT" in *'all release references match'*) fail "4: reported success without scanning" ;; esac

# 5. A work tree with install.sh untracked cannot produce an empty-success either.
TOTAL=$((TOTAL + 1))
newcase untracked
git -C "$CASE" init -q && : > "$CASE/.keep"
git -C "$CASE" add .keep
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$CASE" -c user.email=t@t -c user.name=t commit -qm init || fail "5: git setup"
run
[ "$RC" -eq 1 ] || fail "5: expected rc 1 with nothing tracked, got $RC ($OUTPUT)"

if [ "$FAILED" -ne 0 ]; then
  printf 'FAILURES (%s tests)\n' "$TOTAL"
  exit 1
fi
printf 'all tests passed (%s tests)\n' "$TOTAL"
