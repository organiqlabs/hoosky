#!/usr/bin/env bash
# Zero-dependency test harness for ./prepare-commit-msg. Run: bash prepare-commit-msg.test.sh
# Uses real git + jq; stubs curl in scratch PATHs. Never touches the network:
# DENY_BIN/curl (which logs and exits 99) is on the PATH for hook calls that do not
# explicitly override PATH (e.g. with STUB_BIN, EMPTY_BIN, or the MIN_* dirs).
# Working stub curl: logs argv to $ARGV_LOG, captures the -d JSON body to
# $CAPTURE_FILE, pipes stdin (the -K config) to $STDIN_LOG; emits
# $STUB_RESPONSE_FILE or ok.json; exits $STUB_EXIT when set (digits only).
set -u
cd "$(dirname "$0")" || exit 1
HOOK="$PWD/prepare-commit-msg"
ROOT="$(mktemp -d)" || exit 1
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
case "${STUB_EXIT:-}" in '' ) ;; *[!0-9]*) printf 'stub: invalid STUB_EXIT "%s" (digits only)\n' "$STUB_EXIT" >&2; exit 2 ;; *) exit "$STUB_EXIT" ;; esac
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

# Sentinel registry: path|sentinel pairs staged into the same repo; every
# sentinel must never reach the API payload (root, nested, and icase variants).
make_sentinel_repo() {
  local d="$ROOT/sent-$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  printf 'base\n' > "$d/file.txt"
  git -C "$d" add . && git -C "$d" commit -qm 'init'
  printf 'change\n' >> "$d/file.txt"
  mkdir -p "$d/sub/deep" "$d/.ssh"
  local path sentinel
  while IFS='|' read -r path sentinel; do
    [ -z "$path" ] && continue
    mkdir -p "$d/$(dirname "$path")"
    printf '%s\n' "$sentinel" > "$d/$path"
  done <<'FIX'
secret.pem|SEN-PEM-1
key.key|SEN-KEY-1
package-lock.json|SEN-LOCK-1
bundle.min.js|SEN-MIN-1
pnpm-lock.yaml|SEN-PNPM-1
bun.lockb|SEN-BUN-1
npm-shrinkwrap.json|SEN-NPM-1
.env|SEN-ENV-1
sub/.env|SEN-ENVS-1
sub/.ENV|SEN-ENVIC-1
root.env|SEN-ENVROOT-1
credentials.json|SEN-CREDJSON-1
sub/credentials2.json|SEN-CREDSJ-1
CREDENTIALS/TEAM.JSON|SEN-CREDSCASE-1
secrets.yaml|SEN-SECRET-1
sub/secrets.yaml|SEN-SECRETS-1
sub/deep/my-secrets.json|SEN-SECRETSD-1
id_rsa|SEN-IDRSA-1
sub/id_rsa_k|SEN-IDRSF-1
.ssh/id_dsa|SEN-IDDSA-1
.ssh/id_ecdsa|SEN-IDECSA-1
.ssh/id_ed25519|SEN-IDED-1
sub/deep/id_ecdsa.old|SEN-IDECSAO-1
.npmrc|SEN-NPMRC-1
sub/.npmrc|SEN-NPMRCS-1
.pypirc|SEN-PYPIRC-1
sub/.pypirc|SEN-PYPIRCS-1
.netrc|SEN-NETRC-1
sub/.netrc|SEN-NETRCS-1
.git-credentials|SEN-GCRED-1
sub/.git-credentials|SEN-GCREDS-1
.pgpass|SEN-PGPASS-1
sub/.pgpass|SEN-PGPASSS-1
.htpasswd|SEN-HTPASS-1
sub/.htpasswd|SEN-HTPASSS-1
.docker/config.json|SEN-DCF-1
sub/.docker/config.json|SEN-DCFS-1
.kube/config|SEN-KUBE-1
k8s/.kube/config|SEN-KUBES-1
.aws/credentials|SEN-AWSC-1
sub/.aws/credentials|SEN-AWSCS-1
.m2/settings.xml|SEN-M2-1
home/.m2/settings.xml|SEN-M2S-1
pu.ppk|SEN-PPK-1
sub/pu.PPK|SEN-PPKS-1
cert.p12|SEN-P12-1
sub/cert.p12|SEN-P12S-1
cert.pfx|SEN-PFX-1
sub/cert.PFX|SEN-PFXS-1
cert.jks|SEN-JKS-1
sub/cert.JKS|SEN-JKSS-1
cert.keystore|SEN-KST-1
sub/cert.KEYSTORE|SEN-KSTS-1
sub/Gemfile.lock|SEN-GEMLOCK-1
SUB/GEMFILE.LOCK|SEN-GEMLOCKIC-1
pkg/package-lock.json|SEN-PKGLOCK2-1
sub/npm-shrinkwrap.json|SEN-NPMSHRNK-1
sub/pnpm-lock.yaml|SEN-PNPMNEST-1
a/b/c/bun.lockb|SEN-BUNNEST-1
sub/bundle.min.js|SEN-MINNEST-1
sub/deep/x.PEM|SEN-PEMNESTIC-1
sub/deep/x.KEY|SEN-KEYNESTIC-1
x.map|SEN-MAP-1
sub/x.map|SEN-MAPS-1
bundle.min.css|SEN-MINCS-1
sub/deep/bundle.MIN.CSS|SEN-MINCSS-1
FIX
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
rc=$(run_hook "$r" "$m" "" SKIP_AI_COMMIT=1 GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/p.json")
if [ "$rc" = 0 ] && [ ! -e "$r/p.json" ]; then unchanged "$m" "SKIP_AI_COMMIT bypass (no curl, no capture)"; else bad "SKIP_AI_COMMIT bypass (rc=$rc)"; fi

# 2. GEMINI_API_KEY unset/empty: no-op, exit 0 (an explicit empty string is treated as unset)
r=$(make_repo nokey); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=)
if [ "$rc" = 0 ] && deny_clean && grep -q 'GEMINI_API_KEY not set' "$ROOT/stderr"; then unchanged "$m" "missing key"; else bad "missing key (rc=$rc)"; fi

# 3. Commit source tokens: no-op even with key
for src in message merge squash commit; do
  r=$(make_repo "src-$src"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "$src" GEMINI_API_KEY=fake)
  if [ "$rc" = 0 ] && deny_clean; then unchanged "$m" "source=$src"; else bad "source=$src (rc=$rc)"; fi
done

# 4. Message file already has developer text: untouched
r=$(make_repo prefill); m="$r/COMMIT_EDITMSG"
printf 'my own subject\n\n# comment\n' > "$m"
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin")
if [ "$rc" = 0 ] && grep -q '^my own subject' "$m" && ! grep -q 'feat(' "$m"; then ok "pre-filled message kept"; else bad "pre-filled message kept (rc=$rc)"; fi

# 5. Empty staged diff: no-op (repo with everything committed)
r=$(make_repo clean); git -C "$r" reset -q; m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && deny_clean; then unchanged "$m" "empty staged diff"; else bad "empty staged diff (rc=$rc)"; fi

# 6. Unsafe keys (LF, quote, backslash, CR): refused with warning, no network
i=0
for bad_key in $'ab\nc' 'a"b' 'a\b' $'a\rb'; do
  i=$((i+1)); r=$(make_repo "badkey-$i"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY="$bad_key" PATH="$STUB_BIN:/usr/bin:/bin")
  if [ "$rc" = 0 ] && grep -q 'unsafe' "$ROOT/stderr"; then unchanged "$m" "unsafe key #$i refused"; else bad "unsafe key #$i refused (rc=$rc)"; fi
done

# 7. No arguments at all: silent no-op
r=$(make_repo noargs)
if ( cd "$r" && env -i PATH="$DENY_BIN:/usr/bin:/bin" HOME="$HOME_DIR" GIT_CONFIG_NOSYSTEM=1 "$BASH_BIN" "$HOOK" >/dev/null 2>&1 ); then
  ok "no arguments: exit 0"; else bad "no arguments"; fi

# 8. Missing tools warn and no-op (minimal PATHs in isolation)
MIN_CURL="$ROOT/min-curl"; mkdir -p "$MIN_CURL"; ln -s "$STUB_BIN/curl" "$MIN_CURL/curl"
MIN_CJ="$ROOT/min-cj"; mkdir -p "$MIN_CJ"; ln -s "$STUB_BIN/curl" "$MIN_CJ/curl"; ln -s "$(command -v jq)" "$MIN_CJ/jq"
MIN_CJG="$ROOT/min-cjg"; mkdir -p "$MIN_CJG"; ln -s "$STUB_BIN/curl" "$MIN_CJG/curl"; ln -s "$(command -v jq)" "$MIN_CJG/jq"; ln -s "$(command -v git)" "$MIN_CJG/git"
r=$(make_repo missed-curl); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$EMPTY_BIN" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'curl' not found" "$ROOT/stderr"; then unchanged "$m" "missing curl warns"; else bad "missing curl warns (rc=$rc)"; fi
r=$(make_repo missed-jq); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$MIN_CURL" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'jq' not found" "$ROOT/stderr"; then unchanged "$m" "missing jq warns"; else bad "missing jq warns (rc=$rc)"; fi
r=$(make_repo missed-git); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$MIN_CJ" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'git' not found" "$ROOT/stderr"; then unchanged "$m" "missing git warns"; else bad "missing git warns (rc=$rc)"; fi
r=$(make_repo missed-grep); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" PATH="$MIN_CJG" GEMINI_API_KEY=fake)
if [ "$rc" = 0 ] && grep -q "'grep' not found" "$ROOT/stderr"; then unchanged "$m" "missing grep warns"; else bad "missing grep warns (rc=$rc)"; fi

# 9. Happy path: draft prepended, comment kept, body valid & carries the diff
r=$(make_repo happy); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
jq -r '.contents[0].parts[0].text' "$r/prompt.json" 2>/dev/null > "$r/prompt.txt"
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts): add a thing' && grep -q '^# Please enter' "$m" \
  && jq -e '.contents[0].parts[0].text | contains("diff --git")' "$r/prompt.json" >/dev/null \
  && grep -qE '^Branch: .+' "$r/prompt.txt" && grep -q 'Recent commit subjects' "$r/prompt.txt" \
  && ! compgen -G "$r/COMMIT_EDITMSG.ai-commit.*" >/dev/null; then
  ok "happy path draft prepended"; else bad "happy path draft prepended (rc=$rc)"; fi

# 10. API error payload: warn (with API message), exit 0, file untouched
printf '{"error":{"message":"bad key"}}' > "$ROOT/err.json"
r=$(make_repo apierr); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/err.json")
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr" && grep -q 'bad key' "$ROOT/stderr"; then unchanged "$m" "api error tolerated, message surfaced"; else bad "api error tolerated (rc=$rc)"; fi

# 11. Response wrapped in code fences and leading blanks: stripped before prepend
cat > "$ROOT/fence.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"\n\n```\nfeat(x): fenced subject\n```\nbody line"}]}}]}
JSON
r=$(make_repo fence); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/fence.json")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(x): fenced subject' && ! grep -q '```' "$m"; then ok "code fences stripped"; else bad "code fences stripped (rc=$rc)"; fi

# 12. curl itself fails (non-zero exit, no output): tolerated
r=$(make_repo curlfail); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_EXIT=7)
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr"; then unchanged "$m" "curl failure tolerated"; else bad "curl failure tolerated (rc=$rc)"; fi

# 13. Oversized diff: cut at a line boundary; TAILMARKER not sent; NOTE present
r=$(make_big_repo trunc); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json" GEMINI_MAX_DIFF_CHARS=400)
jq -r '.contents[0].parts[0].text' "$r/prompt.json" > "$r/prompt.txt"
# every padding line present in the sent prompt must be complete (no mid-line cut)
incomplete=$(grep -E '^[+ ]padding line number' "$r/prompt.txt" | grep -vE '^[+ ]padding line number [0-9]+ with some extra words to fill space$')
npadded=$(grep -cE '^[+ ]padding line number' "$r/prompt.txt")
if [ "$rc" = 0 ] && grep -q '(Diff truncated' "$r/prompt.txt" && ! grep -q 'TAILMARKER-ZZZ' "$r/prompt.txt" \
  && [ -z "$incomplete" ] && [ "$npadded" -ge 1 ]; then
  ok "oversized diff cut at line boundary"; else bad "oversized diff cut at line boundary (rc=$rc)"; fi

# 14. Oversized diff with no newline inside the cut: raw slice kept, no crash
r=$(make_longname_repo longn); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json" GEMINI_MAX_DIFF_CHARS=40)
if [ "$rc" = 0 ] && grep -q 'Diff truncated' "$r/prompt.json"; then ok "no-newline cut falls back to raw slice"; else bad "no-newline cut falls back (rc=$rc)"; fi

# 15. Staged .env changes never reach the API body
r=$(make_env_repo env); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
if [ "$rc" = 0 ] && grep -q 'diff --git' "$r/prompt.json" \
  && ! grep -q 'SUPERSECRET-123' "$r/prompt.json" && ! grep -q 'SUPERSECRET-456' "$r/prompt.json"; then ok ".env contents never sent"; else bad ".env contents never sent (rc=$rc)"; fi

# 16. Sentinel matrix: every exclusion that has fixtures below is excluded at root and nested (icase where applicable)
r=$(make_sentinel_repo matrix); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
hits=$(grep -oE 'SEN-[A-Z0-9-]+' "$r/prompt.json" 2>/dev/null | sort -u | tr '\n' ' ')
if [ "$rc" = 0 ] && grep -q 'diff --git' "$r/prompt.json" && [ -z "$hits" ]; then
  ok "sentinel matrix: no excluded file content sent"
else bad "sentinel matrix: leaked sentinels: ${hits:-none} (rc=$rc)"; fi

# 17. Non-numeric / absurd GEMINI_MAX_DIFF_CHARS and GEMINI_TIMEOUT: fall back safely
r=$(make_repo badint); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" GEMINI_MAX_DIFF_CHARS=abc)
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts)' && ! grep -q 'integer expression' "$ROOT/stderr"; then ok "bad integer MAX_DIFF_CHARS falls back"; else bad "bad integer MAX_DIFF_CHARS (rc=$rc)"; fi
r=$(make_repo hugeint); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" GEMINI_MAX_DIFF_CHARS=99999999999999999999999)
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts)' && ! grep -q 'integer expression' "$ROOT/stderr"; then ok "absurd integer MAX_DIFF_CHARS falls back"; else bad "absurd integer MAX_DIFF_CHARS (rc=$rc)"; fi
for t in 0 abc 100; do
  r=$(make_repo "timeout-$t"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" GEMINI_TIMEOUT="$t")
  if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(scripts)'; then ok "GEMINI_TIMEOUT=$t falls back"; else bad "GEMINI_TIMEOUT=$t (rc=$rc)"; fi
done

# 18. Multi-part response: parts are concatenated in order
cat > "$ROOT/two.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(x): two"},{"text":" parts joined"}]}}]}
JSON
r=$(make_repo two); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/two.json")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(x): two parts joined'; then ok "multi-part response concatenated"; else bad "multi-part response concatenated (rc=$rc)"; fi

# 19. Non-JSON response body (e.g. proxy 502 HTML): tolerated
printf '<html><body>502 Bad Gateway</body></html>' > "$ROOT/502.html"
r=$(make_repo proxy); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/502.html")
if [ "$rc" = 0 ] && grep -q 'no message generated' "$ROOT/stderr"; then unchanged "$m" "non-JSON 502 tolerated"; else bad "non-JSON 502 tolerated (rc=$rc)"; fi

# 20. Security contract: API key reaches curl only via stdin (-K -), never argv
key='sekrit-0123456789abcdef'
r=$(make_repo keyleak); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY="$key" PATH="$STUB_BIN:/usr/bin:/bin" ARGV_LOG="$r/argv.txt" STDIN_LOG="$r/stdin.txt")
if [ "$rc" = 0 ] && ! grep -qF "$key" "$r/argv.txt" && grep -qF "x-goog-api-key: $key" "$r/stdin.txt" && grep -q -- '-K' "$r/argv.txt"; then
  ok "api key travels via stdin config only"; else bad "api key travels via stdin config only (rc=$rc)"; fi

# 21. Long subject truncated to 50 by default; long body wrapped to 75 cols
cat > "$ROOT/longsubj.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(scripts): this subject line is deliberately far too long to fit within fifty characters\n\nThis body sentence is deliberately written to be far longer than seventy-five characters so the hook has to wrap it across multiple lines before writing the message file."}]}}]}
JSON
r=$(make_repo longsubj); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/longsubj.json")
subject=$(head -1 "$m")
max_body=0; body_lines=0
while IFS= read -r line; do
  case "$line" in \#*|'') continue ;; esac
  [ "${#line}" -gt "$max_body" ] && max_body="${#line}"
  body_lines=$((body_lines+1))
done < <(tail -n +2 "$m")
expected_subj='feat(scripts): this subject line is deliberately'
if [ "$rc" = 0 ] && [ "$subject" = "$expected_subj" ] && grep -q 'subject exceeds 50 chars; truncated' "$ROOT/stderr" \
  && [ "$max_body" -le 75 ] && [ "$body_lines" -ge 3 ]; then
  ok "subject cut at word boundary to 50; truncation warned; body wrapped to 75"
else bad "subject cut at word boundary to 50; truncation warned; body wrapped to 75 (rc=$rc, subj='$subject')"; fi

# 22. GEMINI_MAX_SUBJECT_CHARS=10 -> subject hard-cut to at most 10 chars
r=$(make_repo subj10); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/longsubj.json" GEMINI_MAX_SUBJECT_CHARS=10)
subject=$(head -1 "$m")
if [ "$rc" = 0 ] && [ -n "$subject" ] && [ "${#subject}" -le 10 ] && [ "${subject#feat}" != "$subject" ]; then
  ok "custom MAX_SUBJECT_CHARS=10 applied"; else bad "custom MAX_SUBJECT_CHARS=10 applied (rc=$rc, subj=${#subject})"; fi

# 23. GEMINI_BODY_WRAP_CHARS=20 -> body wrapped to at most 20 cols
cat > "$ROOT/wrapped.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(x): short subject\n\nalpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon physicist"}]}}]}
JSON
r=$(make_repo wrap20); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/wrapped.json" GEMINI_BODY_WRAP_CHARS=20)
max_body=0
while IFS= read -r line; do
  case "$line" in \#*|'') continue ;; esac
  [ "${#line}" -gt "$max_body" ] && max_body="${#line}"
done < <(tail -n +2 "$m")
if [ "$rc" = 0 ] && [ "$max_body" -gt 0 ] && [ "$max_body" -le 20 ]; then
  ok "custom BODY_WRAP_CHARS=20 applied"; else bad "custom BODY_WRAP_CHARS=20 applied (rc=$rc, body_max=$max_body)"; fi

# 24. Invalid GEMINI_MAX_SUBJECT_CHARS / GEMINI_BODY_WRAP_CHARS fall back to defaults
subj_fb=1
for v in abc 0 00 0000 99999; do
  r=$(make_repo "badsubj-$v"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/longsubj.json" GEMINI_MAX_SUBJECT_CHARS="$v")
  s=$(head -1 "$m")
  { [ "$rc" = 0 ] && [ -n "$s" ] && [ "${#s}" -le 50 ] && [ "${s#feat}" != "$s" ]; } || subj_fb=0
done
if [ "$subj_fb" = 1 ]; then ok "invalid MAX_SUBJECT_CHARS falls back to 50"; else bad "invalid MAX_SUBJECT_CHARS falls back to 50"; fi
wrap_fb=1
for v in abc 0 00 0000 99999; do
  r=$(make_repo "badwrap-$v"); m=$(fresh_msg "$r")
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/longsubj.json" GEMINI_BODY_WRAP_CHARS="$v")
  mb=0
  while IFS= read -r line; do
    case "$line" in \#*|'') continue ;; esac
    [ "${#line}" -gt "$mb" ] && mb="${#line}"
  done < <(tail -n +2 "$m")
  { [ "$rc" = 0 ] && [ "$mb" -gt 0 ] && [ "$mb" -le 75 ]; } || wrap_fb=0
done
if [ "$wrap_fb" = 1 ]; then ok "invalid BODY_WRAP_CHARS falls back to 75"; else bad "invalid BODY_WRAP_CHARS falls back to 75"; fi

# 25. Zero-bypass regression: 00-style values fall back to the defaults (argv-verified)
r=$(make_repo zeros1); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" ARGV_LOG="$r/argv.txt" GEMINI_TIMEOUT=00 GEMINI_MAX_DIFF_CHARS=00)
if [ "$rc" = 0 ] && grep -A1 -- '--max-time' "$r/argv.txt" | tail -1 | grep -qx '20' \
  && grep -A1 -- '--max-filesize' "$r/argv.txt" | tail -1 | grep -qx '10485760' \
  && head -1 "$m" | grep -q '^feat('; then
  ok "TIMEOUT=00 / MAX_DIFF_CHARS=00 fall back to defaults"; else bad "TIMEOUT=00 / MAX_DIFF_CHARS=00 fall back to defaults (rc=$rc)"; fi
r=$(make_repo zeros2); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" GEMINI_MAX_SUBJECT_CHARS=00 GEMINI_BODY_WRAP_CHARS=00)
s=$(head -1 "$m")
mb=0
while IFS= read -r line; do
  case "$line" in \#*|'') continue ;; esac
  [ "${#line}" -gt "$mb" ] && mb="${#line}"
done < <(tail -n +2 "$m")
if [ "$rc" = 0 ] && [ -n "$s" ] && [ "${#s}" -le 50 ] && [ "${s#feat}" != "$s" ] && [ "$mb" -le 75 ]; then
  ok "MAX_SUBJECT_CHARS=00 / BODY_WRAP_CHARS=00 fall back to defaults"; else bad "MAX_SUBJECT_CHARS=00 / BODY_WRAP_CHARS=00 fall back (rc=$rc)"; fi

# 26. --no-ext-diff --no-textconv: repo-local diff drivers cannot rewrite the payload
r="$ROOT/difftool"; mkdir -p "$r"
git -C "$r" init -q; git -C "$r" config user.email test@example.com; git -C "$r" config user.name test
printf 'base\n' > "$r/file.txt"; printf 'baseext\n' > "$r/ext.txt"
git -C "$r" add . && git -C "$r" commit -qm init
printf 'change\n' >> "$r/file.txt"; printf 'changeext\n' >> "$r/ext.txt"; git -C "$r" add .
git -C "$r" config diff.extdriver.command 'printf EXT-DIFF-INJECTED-SENTINEL'
git -C "$r" config diff.mydriver.textconv 'printf TEXCONVB-SENTINEL'
printf 'file.txt diff=mydriver\next.txt diff=extdriver\n' > "$r/.gitattributes"; git -C "$r" add .gitattributes
m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
if [ "$rc" = 0 ] && grep -q '+change' "$r/prompt.json" && grep -q '+changeext' "$r/prompt.json" \
  && ! grep -qE 'TEXCONVB-SENTINEL|EXT-DIFF-INJECTED-SENTINEL' "$r/prompt.json"; then
  ok "repo-local diff drivers not applied to the payload"; else bad "repo-local diff drivers not applied to the payload (rc=$rc)"; fi

# 27. '--stat is capped': the stat payload sent to the API stays within bytes
r="$ROOT/manystat"; mkdir -p "$r"
git -C "$r" init -q; git -C "$r" config user.email test@example.com; git -C "$r" config user.name test
pad='padpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpadpa'
for i in $(seq 1 150); do printf 'base %s\n' "$i" > "$r/${pad}${i}.txt"; done
git -C "$r" add . && git -C "$r" commit -qm 'many baseline'
for i in $(seq 1 150); do printf 'change %s\n' "$i" >> "$r/${pad}${i}.txt"; done
git -C "$r" add .
m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
jq -r '.contents[0].parts[0].text' "$r/prompt.json" > "$r/prompt.txt" 2>/dev/null
# bytes between the section markers incl. them ("Staged diff:\n" is not part of the section)
full=$(sed -n '/^Diff stat:$/,/^Staged diff:$/p' "$r/prompt.txt" | wc -c)
# overhead vs the raw STAT bytes: "Diff stat:\n" (11) + newline after ${STAT} in the
# template (1) + the blank line before "Staged diff:" (1) + "Staged diff:\n" (13) = 26
if [ "$rc" = 0 ] && grep -q '^Diff stat:$' "$r/prompt.txt" \
  && grep -q 'padpad' "$r/prompt.txt" && [ -n "$full" ] && [ "$full" -gt 26 ] && [ "$full" -le 4026 ]; then
  ok "stat section capped at 4000 bytes (got $full incl. markers)"
else bad "stat section capped at 4000 bytes (rc=$rc, full=$full)"; fi

# 28. Failure paths warn + exit 0: unreadable msg file; unwritable msg dir (skipped as root)
if [ "$(id -u)" != 0 ]; then
  r=$(make_repo unread); m=$(fresh_msg "$r")
  before=$(sha1sum "$m")
  chmod 000 "$m"
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin")
  chmod 644 "$m"
  after=$(sha1sum "$m")
  if [ "$rc" = 0 ] && grep -q 'not readable' "$ROOT/stderr" && [ "$before" = "$after" ]; then
    ok "unreadable message file: warns, exits 0, leaves file unchanged"
  else bad "unreadable message file: warns, exits 0, leaves file unchanged (rc=$rc)"; fi

  r=$(make_repo rowrite); d="$ROOT/readonly-$$"; mkdir -p "$d"
  m="$d/COMMIT_EDITMSG"; printf '\n# Please enter the commit message\n' > "$m"; chmod 555 "$d"
  # NOTE: with the writability pre-check, the hook exits before the API call (no curl is
  # burned), so the mv-failure tail path is intentionally not exercised here.
  rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
  if [ "$rc" = 0 ] && grep -q 'not writable' "$ROOT/stderr" \
    && [ ! -e "$r/prompt.json" ] && ! compgen -G "$d/.ai-commit.*" >/dev/null && grep -q '^# Please enter' "$m"; then
    ok "unwritable msg dir: warns before API call, exits 0, no curl, no sibling"
  else bad "unwritable msg dir: warns before API call, exits 0, no curl, no sibling (rc=$rc)"; fi
  chmod 755 "$d"
fi

# 29. GEMINI_MODEL default, override, and invalid-id fallback (argv-verified)
d="$ROOT/model-check"; rm -rf "$d"; mkdir -p "$d"
r=$(make_repo model-default); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" ARGV_LOG="$d/argv-default.txt" >/dev/null
cp "$ROOT/stderr" "$d/err-default.txt"
r=$(make_repo model-override); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" ARGV_LOG="$d/argv-override.txt" GEMINI_MODEL=my-test-model-1 >/dev/null
cp "$ROOT/stderr" "$d/err-override.txt"
r=$(make_repo model-bad); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" ARGV_LOG="$d/argv-bad.txt" GEMINI_MODEL='bad model id' >/dev/null
cp "$ROOT/stderr" "$d/err-bad.txt"
mc=0
grep -qF 'models/gemini-3.5-flash-lite:generateContent' "$d/argv-default.txt" || mc=1
grep -qF 'models/my-test-model-1:generateContent'     "$d/argv-override.txt" || mc=1
grep -qF 'models/gemini-3.5-flash-lite:generateContent' "$d/argv-bad.txt"    || mc=1
grep -q 'not a valid model id' "$d/err-bad.txt"                                || mc=1
! grep -q 'ai-commit:' "$d/err-default.txt"                                    || mc=1
! grep -q 'ai-commit:' "$d/err-override.txt"                                   || mc=1
if [ "$mc" = 0 ]; then ok "gemini model default/override/invalid-id fallback"; else bad "gemini model default/override/invalid-id fallback"; fi

# 30. C0/ESC control chars from the response are stripped; tabs become spaces
cat > "$ROOT/esc.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"feat(x): esc test\n\nbody with \u001b[31mred\u001b[0m and \u0007bell and tab\there"}]}}]}
JSON
r=$(make_repo esc); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/esc.json")
if [ "$rc" = 0 ] && ! LC_ALL=C grep -q $'\x1b' "$m" && ! LC_ALL=C grep -q $'\x07' "$m" \
  && [ "$(LC_ALL=C grep -c $'\t' "$m")" = 0 ] && grep -q 'red' "$m" && grep -q 'tab here' "$m"; then
  ok "C0 control chars stripped; tabs expanded to spaces"
else bad "C0 control chars stripped; tabs expanded to spaces (rc=$rc)"; fi

# 31. GEMINI_DETAIL_LEVEL: default minimal; STANDARD/Detailed honored; bogus falls back
d="$ROOT/detail-check"; rm -rf "$d"; mkdir -p "$d"
r=$(make_repo detail-default); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$d/default.json" >/dev/null
cp "$ROOT/stderr" "$d/err-default.txt"
r=$(make_repo detail-standard); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$d/standard.json" GEMINI_DETAIL_LEVEL=STANDARD >/dev/null
cp "$ROOT/stderr" "$d/err-standard.txt"
r=$(make_repo detail-detailed); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$d/detailed.json" GEMINI_DETAIL_LEVEL=Detailed >/dev/null
cp "$ROOT/stderr" "$d/err-detailed.txt"
r=$(make_repo detail-bogus); m=$(fresh_msg "$r")
run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$d/bogus.json" GEMINI_DETAIL_LEVEL=bogus >/dev/null
cp "$ROOT/stderr" "$d/err-bogus.txt"
ptext() { jq -r '.contents[0].parts[0].text' "$1" 2>/dev/null; }
dc=0
ptext "$d/default.json"  | grep -q 'Required detail level (minimal): Minimal:'  || dc=1
ptext "$d/standard.json" | grep -q 'Required detail level (standard): Standard:' || dc=1
ptext "$d/detailed.json" | grep -q 'Required detail level (detailed): Detailed:' || dc=1
ptext "$d/bogus.json"    | grep -q 'Required detail level (minimal): Minimal:'   || dc=1
grep -q 'not one of minimal' "$d/err-bogus.txt"                                  || dc=1
! grep -q 'ai-commit:' "$d/err-default.txt"                                      || dc=1
! grep -q 'ai-commit:' "$d/err-standard.txt"                                     || dc=1
! grep -q 'ai-commit:' "$d/err-detailed.txt"                                     || dc=1
if [ "$dc" = 0 ]; then ok "GEMINI_DETAIL_LEVEL selects the tier (default minimal; bogus falls back)"; else bad "GEMINI_DETAIL_LEVEL tier selection (dc=$dc)"; fi

# 32. Opening fence with a language tag is stripped too
cat > "$ROOT/langfence.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"```diff\nfeat(x): fenced subject\n```\nbody line"}]}}]}
JSON
r=$(make_repo langfence); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/langfence.json")
if [ "$rc" = 0 ] && head -1 "$m" | grep -q '^feat(x): fenced subject' && ! grep -q '```' "$m"; then
  ok "opening fence with a language tag stripped"; else bad "opening fence with a language tag stripped (rc=$rc)"; fi

# 33. Response wrapped in only fences and blanks: warns, exits 0, file unchanged
cat > "$ROOT/onlyfence.json" <<'JSON'
{"candidates":[{"content":{"parts":[{"text":"\n```\n```\n\n~~~\n"}]}}]}
JSON
r=$(make_repo onlyfence); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$STUB_BIN:/usr/bin:/bin" STUB_RESPONSE_FILE="$ROOT/onlyfence.json")
if [ "$rc" = 0 ] && grep -q 'only formatting noise' "$ROOT/stderr" && ! grep -qE '^[^#[:space:]]' "$m"; then
  ok "all-fence response: warns, exits 0, file unchanged"
else bad "all-fence response: warns, exits 0, file unchanged (rc=$rc)"; fi

# 34. grep exists but errors (exit 2): warns, exits 0, file unchanged
GTWO="$ROOT/gt-two"; mkdir -p "$GTWO"
cat > "$GTWO/grep" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "$GTWO/grep"
r=$(make_repo greptwo); m=$(fresh_msg "$r")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$GTWO:$STUB_BIN:/usr/bin:/bin")
if [ "$rc" = 0 ] && grep -q 'could not inspect' "$ROOT/stderr" && ! grep -qE '^[^#[:space:]]' "$m"; then
  ok "grep rc>=2: warns, exits 0, file unchanged"
else bad "grep rc>=2: warns, exits 0, file unchanged (rc=$rc)"; fi

# 35. mv fails at prepend time: warn, sibling cleaned, msg untouched
MV_FAIL="$ROOT/mv-fail"; mkdir -p "$MV_FAIL"
cat > "$MV_FAIL/mv" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MV_FAIL/mv"
r=$(make_repo mvfail); m=$(fresh_msg "$r")
before=$(sha1sum "$m")
rc=$(run_hook "$r" "$m" "" GEMINI_API_KEY=fake PATH="$MV_FAIL:$STUB_BIN:/usr/bin:/bin" CAPTURE_FILE="$r/prompt.json")
after=$(sha1sum "$m")
if [ "$rc" = 0 ] && grep -q 'could not write' "$ROOT/stderr" && [ "$before" = "$after" ] \
  && ! compgen -G "$r/COMMIT_EDITMSG.ai-commit.*" >/dev/null; then
  ok "mv failure: warns, exits 0, sibling cleaned, msg unchanged"
else bad "mv failure: warns, exits 0, sibling cleaned, msg unchanged (rc=$rc)"; fi

printf '%s\n' "---"
[ "$fail" = 0 ] && echo "all tests passed ($n tests)" || echo "FAILURES ($n tests)"
exit "$fail"
