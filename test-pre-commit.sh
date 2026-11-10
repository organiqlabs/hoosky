#!/usr/bin/env bash
# Zero-dependency test harness for ./pre-commit. Run: bash test-pre-commit.sh
# Uses real git + jq; stubs curl in a scratch PATH. Never touches the network.
set -u
cd "$(dirname "$0")" || exit 1
HOOK="$PWD/pre-commit"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STUB_BIN="$ROOT/bin"; mkdir -p "$STUB_BIN"
fail=0

ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# Each case works in a fresh scratch repo with one staged change.
make_repo() {
  local d="$ROOT/repo-$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  printf 'base\n' > "$d/file.txt"
  git -C "$d" add . && git -C "$d" commit -qm 'init'
  printf 'change\n' >> "$d/file.txt"
  git -C "$d" add file.txt
  printf '%s' "$d"
}

fresh_msg() {  # <repo> -> message file path containing only git's comment block
  printf '\n# Please enter the commit message\n' > "$1/COMMIT_EDITMSG"
  printf '%s' "$1/COMMIT_EDITMSG"
}

run_hook() {  # <repo> <msg> <source> [VAR=val ...] -> exit code; stderr in $ROOT/stderr
  local repo="$1" msg="$2" src="$3"; shift 3
  (cd "$repo" && env "$@" bash "$HOOK" "$msg" "$src") >/dev/null 2>"$ROOT/stderr"
  echo $?
}

unchanged() {  # <msgfile> <name>: pass if file still holds only git's comment block
  if ! grep -qE '^[^#[:space:]]' "$1" && grep -q '^# Please enter' "$1"; then ok "$2"; else bad "$2"; fi
}

# 1. SKIP_AI_COMMIT=1 bypasses entirely (no key present either)
r=$(make_repo skip); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" SKIP_AI_COMMIT=1)
if [ "$rc" = 0 ]; then unchanged "$m" "SKIP_AI_COMMIT bypass"; else bad "SKIP_AI_COMMIT bypass (rc=$rc)"; fi

# 2. GEMINI_API_KEY unset/empty: no-op, exit 0 (empty overrides any ambient key)
r=$(make_repo nokey); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=)
if [ "$rc" = 0 ]; then unchanged "$m" "missing key"; else bad "missing key (rc=$rc)"; fi

# 3. Commit source 'message' (git commit -m): no-op even with key
r=$(make_repo src); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" message GEMINI_API_KEY=fake)
if [ "$rc" = 0 ]; then unchanged "$m" "source=message"; else bad "source=message (rc=$rc)"; fi

# 4. Message file already has developer text: untouched
r=$(make_repo prefill); m="$r/COMMIT_EDITMSG"
printf 'my own subject\n\n# comment\n' > "$m"
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q '^my own subject' "$m" && ! grep -q 'feat(' "$m"; then ok "pre-filled message kept"; else bad "pre-filled message kept (rc=$rc)"; fi

# 5. Empty staged diff: no-op (repo with everything committed)
r=$(make_repo clean); git -C "$r" reset -q; m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ]; then unchanged "$m" "empty staged diff"; else bad "empty staged diff (rc=$rc)"; fi

# 6. Unsafe key (newline injection into curl -K config): refused
r=$(make_repo badkey); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=$'abc\nx-evil: 1')
if [ "$rc" = 0 ] && grep -q 'unsafe' "$ROOT/stderr"; then unchanged "$m" "unsafe key refused"; else bad "unsafe key refused (rc=$rc)"; fi

# 7. Happy path: stub curl emits canned Gemini response -> draft prepended, comment kept
cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(scripts): add a thing\n\nBody explains why."}]}}]}
JSON
EOF
chmod +x "$STUB_BIN/curl"
r=$(make_repo happy); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts): add a thing' && grep -q '^# Please enter' "$m"; then ok "happy path draft prepended"; else bad "happy path draft prepended (rc=$rc)"; fi

# 8. API error payload: warn, exit 0, message file untouched
cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"error":{"message":"bad key"}}'
EOF
chmod +x "$STUB_BIN/curl"
r=$(make_repo apierr); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH")
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr"; then unchanged "$m" "api error tolerated"; else bad "api error tolerated (rc=$rc)"; fi

[ "$fail" = 0 ] && echo 'all tests passed' || echo 'FAILURES'
exit "$fail"
