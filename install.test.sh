#!/usr/bin/env bash
# Zero-dependency test harness for ./install.sh. Run: bash install.test.sh
# Stubs curl in scratch PATHs; never touches the network or the real HOME/gitconfig.
# Every case gets HOME=<case>/home and GIT_CONFIG_GLOBAL=<case>/gitconfig (plus
# GIT_CONFIG_NOSYSTEM=1), so this machine's global git config is invisible.
# The stub curl serves checksums.txt and prepare-commit-msg from this tree — no
# hardcoded hashes, so the suite never rots against the worktree.
set -u
cd "$(dirname "$0")" || exit 1
REPO="$PWD"
ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT

n=0; fail=0
ok()  { n=$((n+1)); printf 'ok   %s\n' "$1"; }
bad() { n=$((n+1)); fail=1; printf 'FAIL %s\n' "$1"; }

# <case name> -> prints the case dir; creates home/, bin/ (with the curl stub), src/
mk_env() {
  local d="$ROOT/$1"
  mkdir -p "$d/home" "$d/bin" "$d/src"
  cat > "$d/bin/curl" <<STUB
#!/usr/bin/env bash
url=""; out=""
args=("\$@")
for ((i=0;i<\${#args[@]};i++)); do
  case "\${args[i]}" in
    -o)    out="\${args[i+1]}" ;;
    http*) url="\${args[i]}" ;;
  esac
done
[ -n "\$url" ] || { echo "stub curl: no url" >&2; exit 2; }
case "\$url" in
  */checksums.txt)
    if [ "\${STUB_BAD_CHECKSUMS:-0}" = 1 ]; then BODY=\$(printf 'deadbeef  prepare-commit-msg\n');
    else BODY=\$(cat "$REPO/checksums.txt"); fi ;;
  */prepare-commit-msg)
    if [ "\${STUB_FAIL_HOOK:-0}" = 1 ]; then echo "stub curl: hook download failed" >&2; exit 22; fi
    BODY=\$(cat "$REPO/prepare-commit-msg") ;;
  *) echo "stub curl: unexpected url \$url" >&2; exit 2 ;;
esac
if [ -n "\$out" ]; then printf '%s\n' "\$BODY" >"\$out"; else printf '%s\n' "\$BODY"; fi
STUB
  chmod 755 "$d/bin/curl"
  printf '%s\n' "$d"
}

# <case dir> [args...] -> sandboxed installer run; stderr in <case>/err
run() {
  local d="$1"; shift
  env -u XDG_CONFIG_HOME ${STUB_FAIL_HOOK:+STUB_FAIL_HOOK="$STUB_FAIL_HOOK"} ${STUB_BAD_CHECKSUMS:+STUB_BAD_CHECKSUMS="$STUB_BAD_CHECKSUMS"} \
      HOME="$d/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$d/gitconfig" \
      PATH="$d/bin:/usr/bin:/bin" bash "$REPO/install.sh" "$@"
}

# <case dir> [git args...] -> git with the same sandbox
git_q() {
  local d="$1"; shift
  env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$d/gitconfig" HOME="$d/home" git "$@"
}
config_get() { env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$1/gitconfig" git config --global core.hooksPath 2>/dev/null; }

# 1. Default, hooksPath unset: creates ~/.config/git/hooks, sets config, installs
d="$(mk_env t1)"; out="$(run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && [ -x "$d/home/.config/git/hooks/prepare-commit-msg" ] \
   && [ "$(config_get "$d")" = "$d/home/.config/git/hooks" ] && grep -q 'set global core.hooksPath' "$d/err"; then
  ok "default: global hooks dir created, config set, hook installed"
else bad "default: global hooks dir created, config set, hook installed (rc=$rc)"; fi

# 2. Default, hooksPath pre-set to an absolute path: installed there, config untouched
d="$(mk_env t2)"; mkdir -p "$d/myhooks"
git_q "$d" config --global core.hooksPath "$d/myhooks"
out="$(run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && [ -x "$d/myhooks/prepare-commit-msg" ] && [ "$(config_get "$d")" = "$d/myhooks" ] \
   && ! grep -q 'set global core.hooksPath' "$d/err"; then
  ok "pre-set absolute hooksPath: reused verbatim, config untouched"
else bad "pre-set absolute hooksPath: reused verbatim, config untouched (rc=$rc)"; fi

# 3. Default, hooksPath relative: refuses, config unchanged
d="$(mk_env t3)"
git_q "$d" config --global core.hooksPath .githooks
out="$(run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 1 ] && grep -q 'relative' "$d/err" && [ "$(config_get "$d")" = ".githooks" ]; then
  ok "relative hooksPath: refused with explanation"
else bad "relative hooksPath: refused with explanation (rc=$rc)"; fi

# 4. Default, hooksPath '~/myhooks': expands to \$HOME
d="$(mk_env t4)"
git_q "$d" config --global core.hooksPath '~/myhooks'
out="$(run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && [ -x "$d/home/myhooks/prepare-commit-msg" ]; then
  ok "tilde hooksPath: expanded to HOME"
else bad "tilde hooksPath: expanded to HOME (rc=$rc)"; fi

# 5. --dir: per-repo install only; global config untouched
d="$(mk_env t5)"
git_q "$d" init -q "$d/src/repo"
out="$(run "$d" --dir "$d/src/repo" 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && [ -x "$d/src/repo/.git/hooks/prepare-commit-msg" ] && [ -z "$(config_get "$d")" ]; then
  ok "--dir: installed into the repo, global config untouched"
else bad "--dir: installed into the repo, global config untouched (rc=$rc)"; fi

# 6. --all: every repo under ROOT gets the hook
d="$(mk_env t6)"
git_q "$d" init -q "$d/src/r1"; git_q "$d" init -q "$d/src/sub/r2"
out="$(run "$d" --all "$d/src" 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && [ -x "$d/src/r1/.git/hooks/prepare-commit-msg" ] && [ -x "$d/src/sub/r2/.git/hooks/prepare-commit-msg" ]; then
  ok "--all: hook installed into every repo found"
else bad "--all: hook installed into every repo found (rc=$rc)"; fi

# 7. Hook download fails: exit 1; core.hooksPath NOT set (a failed install must not hijack repos)
d="$(mk_env t7)"
out="$(STUB_FAIL_HOOK=1 run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 1 ] && [ -z "$(config_get "$d")" ] && [ ! -e "$d/home/.config/git/hooks/prepare-commit-msg" ]; then
  ok "download failure: config not set, nothing installed"
else bad "download failure: config not set, nothing installed (rc=$rc)"; fi

# 8. Checksum mismatch: refuses; core.hooksPath NOT set
d="$(mk_env t8)"
out="$(STUB_BAD_CHECKSUMS=1 run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 1 ] && grep -q 'refusing to install' "$d/err" && [ -z "$(config_get "$d")" ]; then
  ok "checksum mismatch: refuses to install unverified code"
else bad "checksum mismatch: refuses to install unverified code (rc=$rc)"; fi

# 9. Unmanaged existing hook: refused without --force; --force backs up, then overwrites
d="$(mk_env t9)"; mkdir -p "$d/home/.config/git/hooks"
printf '#!/bin/sh\necho not-hoosky\n' > "$d/home/.config/git/hooks/prepare-commit-msg"; chmod +x "$d/home/.config/git/hooks/prepare-commit-msg"
out="$(run "$d" 2>"$d/err")"; rc=$?
refusal_ok=0
[ $rc -eq 1 ] && grep -q not-hoosky "$d/home/.config/git/hooks/prepare-commit-msg" && [ -z "$(config_get "$d")" ] && refusal_ok=1
out="$(run "$d" --force 2>"$d/err")"; rc=$?
force_ok=0
[ $rc -eq 0 ] && cmp -s "$REPO/prepare-commit-msg" "$d/home/.config/git/hooks/prepare-commit-msg" \
  && ls "$d/home/.config/git/hooks/" | grep -q '^prepare-commit-msg\.bak\.' && force_ok=1
if [ "$refusal_ok" = 1 ] && [ "$force_ok" = 1 ]; then
  ok "unmanaged hook: refused without --force; --force backs up and overwrites"
else bad "unmanaged hook: refused without --force (refusal=$refusal_ok) / --force backup+overwrite (force=$force_ok)"; fi

# 10. Uninstall: default global target; hook moved aside; config deliberately left alone (with hint)
d="$(mk_env t10)"
run "$d" >/dev/null 2>&1
out="$(run "$d" --uninstall 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && ls "$d/home/.config/git/hooks/" | grep -q '^prepare-commit-msg\.uninstalled\.' \
   && grep -q 'core.hooksPath still points' "$d/err" && [ -n "$(config_get "$d")" ]; then
  ok "--uninstall: hook moved aside; global hooksPath left alone with hint"
else bad "--uninstall: hook moved aside; global hooksPath left alone with hint (rc=$rc)"; fi

# 11. --global combined with --dir: usage error
d="$(mk_env t11)"
out="$(run "$d" --global --dir "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 2 ]; then ok "--global with --dir: exits 2"; else bad "--global with --dir: exits 2 (rc=$rc)"; fi

# 12. --uninstall with nothing installed: exit 0, global config NOT set
d="$(mk_env t12)"
out="$(run "$d" --uninstall 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'nothing to do' && [ -z "$(config_get "$d")" ]; then
  ok "--uninstall, nothing installed: exit 0, config not set"
else bad "--uninstall, nothing installed: exit 0, config not set (rc=$rc)"; fi

# 13. Relative XDG_CONFIG_HOME is ignored (falls back to ~/.config), with a warning
d="$(mk_env t13)"
out="$(env HOME="$d/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$d/gitconfig" XDG_CONFIG_HOME=rel/path \
        PATH="$d/bin:/usr/bin:/bin" bash "$REPO/install.sh" 2>"$d/err")"; rc=$?
if [ $rc -eq 0 ] && [ -x "$d/home/.config/git/hooks/prepare-commit-msg" ] && grep -q 'relative' "$d/err"; then
  ok "relative XDG_CONFIG_HOME: ignored, fell back to ~/.config"
else bad "relative XDG_CONFIG_HOME: ignored, fell back to ~/.config (rc=$rc)"; fi

# 14. End-to-end: the globally installed hook fires for a fresh repo's commit
d="$(mk_env t14)"
run "$d" >/dev/null 2>&1
git_q "$d" init -q "$d/src/e2e"
printf 'hello\n' > "$d/src/e2e/f.txt"
git_q "$d" -C "$d/src/e2e" add f.txt
out="$( cd "$d/src/e2e" && env -u GEMINI_API_KEY HOME="$d/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$d/gitconfig" \
          PATH="$d/bin:/usr/bin:/bin" EDITOR=true git -c user.name=t -c user.email=t@e commit 2>&1 )"
if printf '%s' "$out" | grep -q 'GEMINI_API_KEY not set'; then
  ok "e2e: fresh repo commit fires the global hook"
else bad "e2e: fresh repo commit fires the global hook"; fi

# 15. --all on a nonexistent root: exits 1 with a message (not silent success)
d="$(mk_env t15)"
out="$(run "$d" --all "$d/does-not-exist" 2>"$d/err")"; rc=$?
if [ $rc -eq 1 ] && grep -q 'no git repositories found' "$d/err"; then
  ok "--all on missing root: exit 1 with message"
else bad "--all on missing root: exit 1 with message (rc=$rc)"; fi

# 16. Hook copy fails mid-install: exit 1, failure not printed as success, config NOT set
d="$(mk_env t16)"
printf '#!/usr/bin/env bash\necho "stub cp: forced failure" >&2; exit 1\n' > "$d/bin/cp"; chmod +x "$d/bin/cp"
out="$(run "$d" 2>"$d/err")"; rc=$?
if [ $rc -eq 1 ] && ! printf '%s' "$out" | grep -q 'hoosky installed' && [ -z "$(config_get "$d")" ]; then
  ok "copy failure: reported as failure, core.hooksPath not set"
else bad "copy failure: reported as failure, core.hooksPath not set (rc=$rc)"; fi

# 17. --help: exits 0
d="$(mk_env t17)"
out="$(run "$d" --help 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'usage:'; then ok "--help: exits 0"; else bad "--help: exits 0 (rc=$rc)"; fi

printf '%s\n' "---"
[ "$fail" = 0 ] && echo "all tests passed ($n tests)" || echo "FAILURES ($n tests)"
exit "$fail"
