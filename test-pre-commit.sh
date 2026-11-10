#!/usr/bin/env bash
# Zero-dependency test harness for ./pre-commit. Run: bash test-pre-commit.sh
# Uses real git + jq; stubs curl in scratch PATHs. Never touches the network:
# DENY_BIN/curl (which logs and exits 99) is on the PATH for every hook call
# unless a test explicitly overrides PATH with STUB_BIN.
# Working stub curl: logs argv to $ARGV_LOG, captures the -d JSON body to
# $CAPTURE_FILE, pipes stdin (the -K config) to $STDIN_LOG; emits
# $STUB_RESPONSE_FILE or ok.json; exits $STUB_EXIT when set (digits only).
set -u
cd "$(dirname "$0")" || exit 1
HOOK="$PWD/pre-commit"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
STUB_BIN="$ROOT/stub"; mkdir -p "$STUB_BIN"
DENY_BIN="$ROOT/deny"; mkdir -p "$DENY_BIN"
EMPTY_BIN="$ROOT/empty"; mkdir -p "$EMPTY_BIN"
HOME_DIR="$ROOT/home"; mkdir -p "$HOME_DIR"
printf '%s' '{"candidates":[{"content":{"parts":[{"text":"feat(scripts): add a thing\n\nBody explains why."}]}}]}' > "$ROOT/ok.json"

n=0; fail=0
ok()  { n=$((n+1)); printf 'ok   %s\n' "$1"; }
bad() { n=$((n+1)); fail=1; printf 'FAIL %s\n' "$1"; }

cat > "$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
[ -n "${ARGV_LOG:-}" ] && printf '%s\n' "$@" > "$ARGV_LOG"
while [ $# -gt 0 ]; do
  if [ "$1" = "-d" ]; then shift; [ -n "${CAPTURE_FILE:-}" ] && cp "${1#@}" "$CAPTURE_FILE"; fi
  shift
done
if [ -n "${STDIN_LOG:-}" ]; then cat > "$STDIN_LOG"; else cat > /dev/null; fi
case "${STUB_EXIT:-}" in ''|*[!0-9]*) ;; *) exit "$STUB_EXIT" ;; esac
if [ -n "${STUB_RESPONSE_FILE:-}" ]; then cat "$STUB_RESPONSE_FILE"; else cat "$ROOT_DIR/ok.json"; fi
EOF
chmod +x "$STUB_BIN/curl"

cat > "$DENY_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'DENY-NETWORK %s\n' "$*" >> "${DENY_LOG:-/dev/null}"
exit 99
EOF
chmod +x "$DENY_BIN/curl"

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

# Repo whose staged file is a long line far bigger than the 400-char cut point.
make_big_repo() {
  local d="$ROOT/big-$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  printf 'base\n' > "$d/big.txt"
  git -C "$d" add . && git -C "$d" commit -qm 'init'
  for i in $(seq 1 60); do printf 'padding line number %s with some extra words to fill space\n' "$i"; done > "$d/big.txt"
  printf 'TAILMARKER-ZZZ-UNDUNDELTA\n' >> "$d/big.txt"
  git -C "$d" add big.txt
  printf '%s' "$d"
}

# Repo whose staged diff starts with a path longer than MAX_DIFF_CHARS (fallback).
make_longname_repo() {
  local d="$ROOT/long-$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  local fname='padpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpad'
  printf 'base\n' > "$d/$fname.txt"
  git -C "$d" add . && git -C "$d" commit -qm 'init'
  printf 'change\n' >> "$d/$fname.txt"
  git -C "$d" add .
  printf '%s' "$d"
}

# Repo with a staged .env change that must never reach the API.
make_env_repo() {
  local d="$ROOT/env-$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  printf 'SECRET=SUPERSECRET-123\n' > "$d/.env"
  printf 'base\n' > "$d/file.txt"
  git -C "$d" add . && git -C "$d" commit -qm 'init'
  printf 'SECRET=SUPERSECRET-456\n' > "$d/.env"
  printf 'change\n' >> "$d/file.txt"
  git -C "$d" add .
  printf '%s' "$d"
}

# Repo with many excluded-secret sentinels plus one ordinary file.
make_leak_repo() {
  local d="$ROOT/leak-$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  printf 'base\n' > "$d/file.txt"
  git -C "$d" add . && git -C "$d" commit -qm 'init'
  printf 'change\n' >> "$d/file.txt"
  printf 'PEMSENTINEL\n' > "$d/secret.pem"
  printf 'KEYSENTINEL\n' > "$d/key.key"
  printf 'LOCKSENTINEL\n' > "$d/package-lock.json"
  printf 'MINSENTINEL\n' > "$d/bundle.min.js"
  printf 'PNPMST-SENTINEL\n' > "$d/pnpm-lock.yaml"
  git -C "$d" add .
  printf '%s' "$d"
}

fresh_msg() {  # <repo> -> message file path containing only git's comment block
  printf '\n# Please enter the commit message\n' > "$1/COMMIT_EDITMSG"
  printf '%s' "$1/COMMIT_EDITMSG"
}

BASH_BIN="$(command -v bash)"
run_hook() {  # <repo> <msg> <source> [VAR=val ...] -> exit code; stderr in $ROOT/stderr
  local repo="$1" msg="$2" src="$3"; shift 3
  rm -f "$ROOT/deny.log" "$ROOT/stderr"
  ( cd "$repo" && \
    env -i PATH="$DENY_BIN:/usr/bin:/bin" HOME="$HOME_DIR" ROOT_DIR="$ROOT" \
           DENY_LOG="$ROOT/deny.log" GIT_CONFIG_NOSYSTEM=1 "$@" \
    "$BASH_BIN" "$HOOK" "$msg" "$src" ) >/dev/null 2>"$ROOT/stderr"
  echo $?
}

deny_clean() { [ ! -s "$ROOT/deny.log" ]; }

unchanged() {  # <msgfile> <name>: pass if file still holds only git's comment block
  if ! grep -qE '^[^#[:space:]]' "$1" && grep -q '^# Please enter' "$1"; then ok "$2"; else bad "$2"; fi
}

# 1. SKIP_AI_COMMIT with key+PATH set: bypass before any git/curl call
r=$(make_repo skip); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" SKIP_AI_COMMIT=1 GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" CAPTURE_FILE="$r/p.json")
if [ "$rc" = 0 ] && [ ! -e "$r/p.json" ] && deny_clean; then unchanged "$m" "SKIP_AI_COMMIT bypass (no curl, no capture)"; else bad "SKIP_AI_COMMIT bypass (rc=$rc)"; fi

# 2. GEMINI_API_KEY unset/empty: no-op, exit 0 (empty overrides any ambient key)
r=$(make_repo nokey); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=)
if [ "$rc" = 0 ] && deny_clean; then unchanged "$m" "missing key"; else bad "missing key (rc=$rc)"; fi

# 3. Commit source tokens: no-op even with key
for src in message merge squash commit; do
  r=$(make_repo "src-$src"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "$src" GEMINI_API_KEY=fake)
  if [ "$rc" = 0 ] && deny_clean; then unchanged "$m" "source=$src"; else bad "source=$src (rc=$rc)"; fi
done

# 4. Message file already has developer text: untouched
r=$(make_repo prefill); m="$r/COMMIT_EDITMSG"
printf 'my own subject\n\n# comment\n' > "$m"
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH")
if [ "$rc" = 0 ] && grep -q '^my own subject' "$m" && ! grep -q 'feat(' "$m" && deny_clean; then ok "pre-filled message kept"; else bad "pre-filled message kept (rc=$rc)"; fi

# 5. Empty staged diff: no-op (repo with everything committed)
r=$(make_repo clean); git -C "$r" reset -q; m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && deny_clean; then unchanged "$m" "empty staged diff"; else bad "empty staged diff (rc=$rc)"; fi

# 6. Unsafe keys (LF, quote, backslash, CR): refused with warning, no network
i=0
for bad_key in $'ab\nc' 'a"b' 'a\b' $'a\rb'; do
  i=$((i+1)); r=$(make_repo "badkey-$i"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY="$bad_key" PATH="$STUB_BIN:$PATH")
  if [ "$rc" = 0 ] && grep -q 'unsafe' "$ROOT/stderr" && deny_clean; then unchanged "$m" "unsafe key #$i refused"; else bad "unsafe key #$i refused (rc=$rc)"; fi
done

# 7. No arguments at all: silent no-op
r=$(make_repo noargs)
if ( cd "$r" && env -i PATH="$DENY_BIN:/usr/bin:/bin" HOME="$HOME_DIR" GIT_CONFIG_NOSYSTEM=1 "$BASH_BIN" "$HOOK" >/dev/null 2>&1 ); then
  ok "no arguments: exit 0"; else bad "no arguments"; fi

# 8. Missing tools warn and no-op (minimal PATHs in isolation)
MIN_CURL="$ROOT/min-curl"; mkdir -p "$MIN_CURL"; ln -s "$STUB_BIN/curl" "$MIN_CURL/curl"
MIN_CJ="$ROOT/min-cj"; mkdir -p "$MIN_CJ"; ln -s "$STUB_BIN/curl" "$MIN_CJ/curl"; ln -s "$(command -v jq)" "$MIN_CJ/jq"
r=$(make_repo missed-curl); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$EMPTY_BIN" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'curl' not found" "$ROOT/stderr"; then unchanged "$m" "missing curl warns"; else bad "missing curl warns (rc=$rc)"; fi
r=$(make_repo missed-jq); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$MIN_CURL" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'jq' not found" "$ROOT/stderr"; then unchanged "$m" "missing jq warns"; else bad "missing jq warns (rc=$rc)"; fi
r=$(make_repo missed-git); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$MIN_CJ" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'git' not found" "$ROOT/stderr"; then unchanged "$m" "missing git warns"; else bad "missing git warns (rc=$rc)"; fi

# 9. Happy path: draft prepended, comment kept, body valid & carries the diff
r=$(make_repo happy); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" CAPTURE_FILE="$r/prompt.json")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts): add a thing' && grep -q '^# Please enter' "$m" \
  && jq -e '.contents[0].parts[0].text | contains("diff --git")' "$r/prompt.json" >/dev/null && deny_clean; then
  ok "happy path draft prepended"; else bad "happy path draft prepended (rc=$rc)"; fi

# 10. API error payload: warn (with API message), exit 0, file untouched
printf '{"error":{"message":"bad key"}}' > "$ROOT/err.json"
r=$(make_repo apierr); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/err.json")
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr" && grep -q 'bad key' "$ROOT/stderr"; then unchanged "$m" "api error tolerated, message surfaced"; else bad "api error tolerated (rc=$rc)"; fi

# 11. Response wrapped in code fences and leading blanks: stripped before prepend
cat > "$ROOT/fence.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"\n\n```\nfeat(x): fenced subject\n```\nbody line"}]}}]}
JSON
r=$(make_repo fence); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/fence.json")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(x): fenced subject' && ! grep -q '```' "$m"; then ok "code fences stripped"; else bad "code fences stripped (rc=$rc)"; fi

# 12. curl itself fails (non-zero exit, no output): tolerated
r=$(make_repo curlfail); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_EXIT=7)
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr"; then unchanged "$m" "curl failure tolerated"; else bad "curl failure tolerated (rc=$rc)"; fi

# 13. Oversized diff: cut at a line boundary; TAILMARKER not sent; NOTE present
r=$(make_big_repo trunc); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" CAPTURE_FILE="$r/prompt.json" GEMINI_MAX_DIFF_CHARS=400)
jq -r '.contents[0].parts[0].text' "$r/prompt.json" > "$r/prompt.txt"
# every padding line present in the sent prompt must be complete (no mid-line cut)
incomplete=$(grep -E '^[+ ]padding line number' "$r/prompt.txt" | grep -vE '^[+ ]padding line number [0-9]+ with some extra words to fill space$')
npadded=$(grep -cE '^[+ ]padding line number' "$r/prompt.txt")
if [ "$rc" = 0 ] && grep -q '(Diff truncated' "$r/prompt.txt" && ! grep -q 'TAILMARKER-ZZZ' "$r/prompt.txt" \
  && [ -z "$incomplete" ] && [ "$npadded" -ge 1 ]; then
  ok "oversized diff cut at line boundary"; else bad "oversized diff cut at line boundary (rc=$rc)"; fi

# 14. Oversized diff with no newline inside the cut: raw slice kept, no crash
r=$(make_longname_repo longn); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" CAPTURE_FILE="$r/prompt.json" GEMINI_MAX_DIFF_CHARS=40)
if [ "$rc" = 0 ] && grep -q 'Diff truncated' "$r/prompt.json"; then ok "no-newline cut falls back to raw slice"; else bad "no-newline cut falls back (rc=$rc)"; fi

# 15. Staged .env changes never reach the API body
r=$(make_env_repo env); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" CAPTURE_FILE="$r/prompt.json")
if [ "$rc" = 0 ] && grep -q 'diff --git' "$r/prompt.json" \
  && ! grep -q 'SUPERSECRET-123' "$r/prompt.json" && ! grep -q 'SUPERSECRET-456' "$r/prompt.json"; then ok ".env contents never sent"; else bad ".env contents never sent (rc=$rc)"; fi

# 16. Excluded-secret sentinels (pem, key, locks, minified) never reach the API
r=$(make_leak_repo leak); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" CAPTURE_FILE="$r/prompt.json")
if [ "$rc" = 0 ] && grep -q 'diff --git' "$r/prompt.json" \
  && ! grep -qE 'PEMSENTINEL|KEYSENTINEL|LOCKSENTINEL|MINSENTINEL|PNPMST-SENTINEL' "$r/prompt.json"; then ok "excluded sentinels never sent"; else bad "excluded sentinels never sent (rc=$rc)"; fi

# 17. Non-numeric / absurd GEMINI_MAX_DIFF_CHARS and GEMINI_TIMEOUT: fall back safely
r=$(make_repo badint); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" GEMINI_MAX_DIFF_CHARS=abc)
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts)' && ! grep -q 'integer expression' "$ROOT/stderr"; then ok "bad integer MAX_DIFF_CHARS falls back"; else bad "bad integer MAX_DIFF_CHARS (rc=$rc)"; fi
r=$(make_repo hugeint); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" GEMINI_MAX_DIFF_CHARS=99999999999999999999999)
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts)' && ! grep -q 'integer expression' "$ROOT/stderr"; then ok "absurd integer MAX_DIFF_CHARS falls back"; else bad "absurd integer MAX_DIFF_CHARS (rc=$rc)"; fi
for t in 0 abc; do
  r=$(make_repo "timeout-$t"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" GEMINI_TIMEOUT="$t")
  if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts)'; then ok "GEMINI_TIMEOUT=$t falls back"; else bad "GEMINI_TIMEOUT=$t (rc=$rc)"; fi
done

# 18. Multi-part response: parts are concatenated in order
cat > "$ROOT/two.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(x): two"},{"text":" parts joined"}]}}]}
JSON
r=$(make_repo two); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/two.json")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(x): two parts joined'; then ok "multi-part response concatenated"; else bad "multi-part response concatenated (rc=$rc)"; fi

# 19. Non-JSON response body (e.g. proxy 502 HTML): tolerated
printf '<html><body>502 Bad Gateway</body></html>' > "$ROOT/502.html"
r=$(make_repo proxy); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/502.html")
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr"; then unchanged "$m" "non-JSON 502 tolerated"; else bad "non-JSON 502 tolerated (rc=$rc)"; fi

# 20. Security contract: API key reaches curl only via stdin (-K -), never argv
key='sekrit-0123456789abcdef'
r=$(make_repo keyleak); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY="$key" PATH="$STUB_BIN:$PATH" ARGV_LOG="$r/argv.txt" STDIN_LOG="$r/stdin.txt")
if [ "$rc" = 0 ] && ! grep -qF "$key" "$r/argv.txt" && grep -qF "x-goog-api-key: $key" "$r/stdin.txt" && grep -q -- '-K' "$r/argv.txt"; then
  ok "api key travels via stdin config only"; else bad "api key travels via stdin config only (rc=$rc)"; fi

# 21. Long subject truncated to 50 by default; long body wrapped to 75 cols
cat > "$ROOT/longsubj.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(scripts): this subject line is deliberately far too long to fit within fifty characters\n\nThis body sentence is deliberately written to be far longer than seventy-five characters so the hook has to wrap it across multiple lines before writing the message file."}]}}]}
JSON
r=$(make_repo longsubj); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/longsubj.json")
subject=$(head -1 "$m")
max_body=0; body_lines=0
while IFS= read -r line; do
  case "$line" in \#*|'') continue ;; esac
  [ "${#line}" -gt "$max_body" ] && max_body="${#line}"
  body_lines=$((body_lines+1))
done < <(tail -n +2 "$m")
if [ "$rc" = 0 ] && [ "${#subject}" -le 50 ] && [ "${subject#feat}" != "$subject" ] \
  && [ "$max_body" -le 75 ] && [ "$body_lines" -ge 3 ]; then
  ok "subject truncated to 50; body wrapped to 75"
else bad "subject truncated to 50; body wrapped to 75 (rc=$rc, subj=${#subject}, body_max=$max_body, body_lines=$body_lines)"; fi

# 22. GEMINI_MAX_SUBJECT_CHARS=10 -> subject hard-cut to at most 10 chars
r=$(make_repo subj10); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/longsubj.json" GEMINI_MAX_SUBJECT_CHARS=10)
subject=$(head -1 "$m")
if [ "$rc" = 0 ] && [ -n "$subject" ] && [ "${#subject}" -le 10 ] && [ "${subject#feat}" != "$subject" ]; then
  ok "custom MAX_SUBJECT_CHARS=10 applied"; else bad "custom MAX_SUBJECT_CHARS=10 applied (rc=$rc, subj=${#subject})"; fi

# 23. GEMINI_BODY_WRAP_CHARS=20 -> body wrapped to at most 20 cols
cat > "$ROOT/wrapped.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(x): short subject\n\nalpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon physicist"}]}}]}
JSON
r=$(make_repo wrap20); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/wrapped.json" GEMINI_BODY_WRAP_CHARS=20)
max_body=0
while IFS= read -r line; do
  case "$line" in \#*|'') continue ;; esac
  [ "${#line}" -gt "$max_body" ] && max_body="${#line}"
done < <(tail -n +2 "$m")
if [ "$rc" = 0 ] && [ "$max_body" -gt 0 ] && [ "$max_body" -le 20 ]; then
  ok "custom BODY_WRAP_CHARS=20 applied"; else bad "custom BODY_WRAP_CHARS=20 applied (rc=$rc, body_max=$max_body)"; fi

# 24. Invalid GEMINI_MAX_SUBJECT_CHARS / GEMINI_BODY_WRAP_CHARS fall back to defaults
subj_fb=1
for v in abc 0 99999; do
  r=$(make_repo "badsubj-$v"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/longsubj.json" GEMINI_MAX_SUBJECT_CHARS="$v")
  s=$(head -1 "$m")
  { [ "$rc" = 0 ] && [ "${#s}" -le 50 ]; } || subj_fb=0
done
if [ "$subj_fb" = 1 ]; then ok "invalid MAX_SUBJECT_CHARS falls back to 50"; else bad "invalid MAX_SUBJECT_CHARS falls back to 50"; fi
wrap_fb=1
for v in abc 0 99999; do
  r=$(make_repo "badwrap-$v"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:$PATH" STUB_RESPONSE_FILE="$ROOT/longsubj.json" GEMINI_BODY_WRAP_CHARS="$v")
  mb=0
  while IFS= read -r line; do
    case "$line" in \#*|'') continue ;; esac
    [ "${#line}" -gt "$mb" ] && mb="${#line}"
  done < <(tail -n +2 "$m")
  { [ "$rc" = 0 ] && [ "$mb" -le 75 ]; } || wrap_fb=0
done
if [ "$wrap_fb" = 1 ]; then ok "invalid BODY_WRAP_CHARS falls back to 75"; else bad "invalid BODY_WRAP_CHARS falls back to 75"; fi

printf '%s\n' "---"
[ "$fail" = 0 ] && echo "all tests passed ($n tests)" || echo "FAILURES ($n tests)"
exit "$fail"
