#!/usr/bin/env bash
# check-version.sh cases. No network: each case builds a scratch dir, copies the
# checker and installer into it, and runs the checker there. Prints
# "all tests passed (N tests)" and exits 0, or "FAILURES (N tests)" and exits 1.
# Fixture versions are assembled at runtime by ver(): keeping literal release
# numbers out of tracked test code avoids a bump every time TAG changes.
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

ver() {  # <major> <minor> <patch> -> vM.m.p without a literal version in this file
  printf 'v%s.%s.%s' "$1" "$2" "$3"
}

WORK="$(mktemp -d)" || { printf 'check-version.test: mktemp failed\n' >&2; exit 1; }

# 0. The suite must not carry a literal version token of its own: pinning a release
# number in test code would need a bump every time TAG changes.
TOTAL=$((TOTAL + 1))
if grep -qE 'v[0-9]+\.[0-9]+\.[0-9]+' "$0"; then
  fail "0: suite contains a literal version token; build fixtures with ver() instead"
fi

# 1. Matching tree passes and says so.
TOTAL=$((TOTAL + 1))
V_MATCH="$(ver 9 9 9)"
newcase matching
printf 'See %s docs.\n' "$V_MATCH" > "$CASE/README.md"
sed "s/^TAG=\"v[0-9.]*\"\$/TAG=\"$V_MATCH\"/" "$CASE/install.sh" > "$CASE/.tag" && mv "$CASE/.tag" "$CASE/install.sh"
gitcase || fail "1: git setup"
run
[ "$RC" -eq 0 ] || fail "1: expected rc 0, got $RC ($ERR)"
case "$OUTPUT" in *"match TAG=$V_MATCH"*) : ;; *) fail "1: missing success line: $OUTPUT" ;; esac

# 2. A second reference fails with the mismatching version named.
TOTAL=$((TOTAL + 1))
V_BAD="$(ver 1 2 3)"
newcase mismatch
printf 'See %s docs.\n' "$V_BAD" > "$CASE/README.md"
gitcase || fail "2: git setup"
run
[ "$RC" -eq 1 ] || fail "2: expected rc 1, got $RC"
case "$ERR" in *"$V_BAD"*) : ;; *) fail "2: stderr did not name $V_BAD: $ERR" ;; esac

# 3. Gitignored files never reach the gate (tracked-only scan, T013).
TOTAL=$((TOTAL + 1))
V_IGN="$(ver 8 8 8)"
newcase ignored
printf 'README.md\n' > "$CASE/.gitignore"
printf 'scratch %s\n' "$V_IGN" > "$CASE/README.md"
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

# 6. An unrelated tracked doc may quote a historical version without blocking a bump:
# only the release-bearing allowlist is scanned (T039).
TOTAL=$((TOTAL + 1))
V_BUMP="$(ver 4 4 4)"
V_OLD="$(ver 2 0 0)"
newcase unrelated
printf 'See %s docs.\n' "$V_BUMP" > "$CASE/README.md"
printf '## History\n\n- %s: first release\n' "$V_OLD" > "$CASE/CHANGELOG.md"
sed "s/^TAG=\"v[0-9.]*\"\$/TAG=\"$V_BUMP\"/" "$CASE/install.sh" > "$CASE/.tag" && mv "$CASE/.tag" "$CASE/install.sh"
gitcase || fail "6: git setup"
run
[ "$RC" -eq 0 ] || fail "6: unrelated CHANGELOG blocked the release: rc=$RC ($ERR)"
case "$OUTPUT" in *"match TAG=$V_BUMP"*) : ;; *) fail "6: missing success line: $OUTPUT" ;; esac

if [ "$FAILED" -ne 0 ]; then
  printf 'FAILURES (%s tests)\n' "$TOTAL"
  exit 1
fi
printf 'all tests passed (%s tests)\n' "$TOTAL"
