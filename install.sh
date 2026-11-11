#!/usr/bin/env bash
# hoosky installer — fetches the prepare-commit-msg hook from the published tag
# and installs it. Default: the global git hooks directory (setting
# core.hooksPath globally when unset); --dir/--all target specific repos.
# Not the hook itself: the hook drafts a Conventional Commits message with one
# Gemini request.
set -u

ORG_REPO="organiqlabs/hoosky"
TAG="v1.0.0"
RAW="https://raw.githubusercontent.com/${ORG_REPO}/${TAG}"
HOOK_NAME="prepare-commit-msg"

err()  { printf 'hoosky-install: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
hoosky installer — installs the prepare-commit-msg hook

usage: install.sh [options]

  --global         install into the global git hooks directory (default); sets
                   core.hooksPath globally to ${XDG_CONFIG_HOME:-~/.config}/git/hooks if unset
  --dir PATH       install into the repo at PATH (repeatable)
  --all ROOT       discover repos under ROOT and install into each
  --uninstall      remove hoosky (only if the installed hook matches the published checksum)
  --force          overwrite an unmanaged hook, or uninstall without the checksum match
  --help           this text

Note: when core.hooksPath is set anywhere (global or local), --dir/--all install into the
hooks directory git resolves for those repos (possibly a shared global dir), not .git/hooks.

Examples:
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash -s -- --global
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash -s -- --dir ~/src/myrepo
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash -s -- --all ~/src
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash -s -- --uninstall
EOF
}

DIRS=()
ALL_ROOT=""
GLOBAL=0
UNINSTALL=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)       shift; [ $# -gt 0 ] || { err "--dir needs a value"; exit 2; }; DIRS+=("$1") ;;
    --all)       shift; [ $# -gt 0 ] || { err "--all needs a value"; exit 2; }; ALL_ROOT="$1" ;;
    --global)    GLOBAL=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --force)     FORCE=1 ;;
    --help|-h)   usage; exit 0 ;;
    *)           err "unknown flag '$1' (see --help)"; exit 2 ;;
  esac
  shift
done

if [ "$GLOBAL" = 1 ] && { [ ${#DIRS[@]} -gt 0 ] || [ -n "$ALL_ROOT" ]; }; then
  err "--global cannot be combined with --dir/--all"
  exit 2
fi

for cmd in curl git sha256sum awk sort find; do
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' not found; install it and retry"; exit 1; }
done

# Print the deduplicated list of repo roots to act on (--dir/--all targets only).
discover_repos() {
  if [ ${#DIRS[@]} -gt 0 ]; then
    printf '%s\n' "${DIRS[@]}" | sort -u
    return
  fi
  { git -C "$ALL_ROOT" rev-parse --show-toplevel 2>/dev/null;
    find "$ALL_ROOT" -name .git -prune -print 2>/dev/null | sed 's:/.git$::'; } | while IFS= read -r d; do
      git -C "$d" rev-parse --git-path hooks >/dev/null 2>&1 && printf '%s\n' "$d"
    done | sort -u
}

# Expand a core.hooksPath value into an absolute path. Handles a leading
# ~/ and a bare ~. Returns 1 for anything else that is not already absolute
# (git resolves those relative to each repo's hook working directory, so
# there is no single directory to act on globally).
expand_hooks_path() {
  case "$1" in
    "~/"*) printf '%s\n' "$HOME/${1#'~/'}" ;;
    "~")   printf '%s\n' "$HOME" ;;
    /*)    printf '%s\n' "$1" ;;
    *)     return 1 ;;
  esac
}

# Print the directory git will use for global hooks, resolving the global
# core.hooksPath without mutating it. Setting core.hooksPath happens only
# after a successful global install (see global_post_action), so a failed
# install never hijacks repos that rely on $GIT_DIR/hooks.
global_hooks_dir() {
  local hp expanded xdg
  hp="$(git config --global core.hooksPath 2>/dev/null)" || hp=""
  if [ -n "$hp" ]; then
    if ! expanded="$(expand_hooks_path "$hp")"; then
      err "global core.hooksPath '$hp' is relative; git resolves it relative to each repo's hook working directory, so there is no single directory hoosky can install into. Set an absolute path (e.g. git config --global core.hooksPath \"\$HOME/.config/git/hooks\") or pass --dir/--all."
      return 1
    fi
    printf '%s\n' "$expanded"
    return 0
  fi
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    case "$XDG_CONFIG_HOME" in
      /*) xdg="$XDG_CONFIG_HOME" ;;
      *)  err "XDG_CONFIG_HOME='$XDG_CONFIG_HOME' is relative; ignoring it"; xdg="$HOME/.config" ;;
    esac
  else
    xdg="$HOME/.config"
  fi
  printf '%s\n' "$xdg/git/hooks"
}

# After a global install: point core.hooksPath at $hd if it isn't set yet,
# otherwise the hook is installed where git never looks. After a global
# uninstall: leave the config alone, but say so when it still points at the
# directory the hook was removed from.
global_post_action() {  # <hd> <install|uninstall> -> 0 ok, 1 failed
  local hd="$1" phase="$2" cur
  if [ "$phase" = install ]; then
    if git config --global core.hooksPath >/dev/null 2>&1; then
      return 0
    fi
    if git config --global core.hooksPath "$hd"; then
      err "set global core.hooksPath to $hd — hoosky now runs in every git repository"
      return 0
    fi
    err "installed, but could not set global core.hooksPath; run: git config --global core.hooksPath '$hd'"
    return 1
  fi
  cur="$(git config --global core.hooksPath 2>/dev/null || true)"
  if [ -n "$cur" ] && cur="$(expand_hooks_path "$cur")" && [ "$cur" = "$hd" ]; then
    err "note: global core.hooksPath still points at $hd; restore per-repo hooks with: git config --global --unset core.hooksPath"
  fi
  return 0
}

published_sum() {  # <filename> -> the sha256 published in the tag, or empty
  curl -fsSL --proto '=https' --tlsv1.2 "$RAW/checksums.txt" | awk -v f="$1" '$2 == f { print $1; exit }'
}

repo_hooks_dir() {  # <repo> -> absolute hooks dir
  local hd
  hd="$(git -C "$1" rev-parse --git-path hooks)" || return 1
  case "$hd" in /*) printf '%s\n' "$hd" ;; *) printf '%s\n' "$1/$hd" ;; esac
}

file_sum() { sha256sum "$1" | awk '{ print $1 }'; }

# Download once (install path only), verify once, then act per target. Fetch the
# published checksum exactly once either way.
TMPD=""
HOOK_SUM="$(published_sum "$HOOK_NAME")"
if [ "$UNINSTALL" != 1 ]; then
  TMPD="$(mktemp -d)" || { err 'mktemp -d failed'; exit 1; }
  trap 'rm -rf "$TMPD"' EXIT
  curl -fsSL --proto '=https' --tlsv1.2 -o "$TMPD/$HOOK_NAME" "$RAW/$HOOK_NAME" \
    || { err "download of $RAW/$HOOK_NAME failed"; exit 1; }
  if [ -z "$HOOK_SUM" ]; then
    err 'could not fetch checksums.txt from the tag; refusing to install unverified code'
    exit 1
  fi
  have="$(file_sum "$TMPD/$HOOK_NAME")"
  if [ "$HOOK_SUM" != "$have" ]; then
    err "checksum mismatch for $HOOK_NAME (want $HOOK_SUM, got $have); refusing to install"
    exit 1
  fi
fi

install_one() {  # <global|repo> <target> -> 0 ok, 1 failed
  local kind="$1" target="$2" hd dest before_ts label
  if [ "$kind" = global ]; then
    hd="$target"
    label="global"
  else
    hd="$(repo_hooks_dir "$target")" || { err "$target: not a git repository; skipping"; return 1; }
    label="$target"
  fi
  dest="$hd/$HOOK_NAME"
  before_ts="$(date +%Y%m%d%H%M%S)-$$"

  if [ "$UNINSTALL" = 1 ]; then
    if [ ! -e "$dest" ]; then
      printf '%s\n' "$label: no hook installed; nothing to do"
      return 0
    fi
    if [ -z "$HOOK_SUM" ]; then
      err "$label: could not fetch checksums.txt; refusing to uninstall without --force"
      return 1
    fi
    if [ "$(file_sum "$dest")" != "$HOOK_SUM" ] && [ "$FORCE" != 1 ]; then
      err "$label: installed hook is not the hoosky hook (checksum differs); refusing without --force"
      return 1
    fi
    mv "$dest" "$dest.uninstalled.$before_ts" || { err "$label: could not move $dest aside; hook left in place"; return 1; }
    printf '%s\n' "$label: uninstalled (moved to $HOOK_NAME.uninstalled.$before_ts)"
    if [ "$kind" = global ]; then
      global_post_action "$hd" uninstall
    fi
    return 0
  fi

  if [ -e "$dest" ]; then
    if [ "$(file_sum "$dest")" = "$HOOK_SUM" ] && [ "$FORCE" != 1 ]; then
      printf '%s\n' "$label: already at $TAG; refreshing anyway"
    elif [ "$FORCE" = 1 ]; then
      cp -a "$dest" "$dest.bak.$before_ts" || { err "$label: backup of $dest failed; refusing to overwrite"; return 1; }
      printf '%s\n' "$label: existing hook backed up to $HOOK_NAME.bak.$before_ts"
    else
      err "$label: $HOOK_NAME exists and is not hoosky; refusing to overwrite without --force (backup will be made)"
      return 1
    fi
  fi

  mkdir -p "$hd" || { err "$label: cannot create hooks dir $hd"; return 1; }
  cp -a "$TMPD/$HOOK_NAME" "$dest" || { err "$label: could not copy hook to $dest"; return 1; }
  chmod 0755 "$dest" || { err "$label: chmod 0755 $dest failed; git ignores non-executable hooks"; return 1; }
  printf '%s\n' "$label: hoosky installed (hook: $dest)"
  if [ "$kind" = global ]; then
    global_post_action "$hd" install
    return $?
  fi
  return 0
}

rc=0
if [ "$GLOBAL" = 1 ] || { [ ${#DIRS[@]} -eq 0 ] && [ -z "$ALL_ROOT" ]; }; then
  gh="$(global_hooks_dir)" || exit 1
  ( install_one global "$gh" ) || rc=1
else
  found=0
  while IFS= read -r repo; do
    case "$repo" in '') continue ;; esac
    found=1
    ( install_one repo "$repo" ) || rc=1
  done < <(discover_repos)
  if [ "$found" = 0 ]; then
    err "no git repositories found${ALL_ROOT:+ under '$ALL_ROOT'}"
    rc=1
  fi
fi

if [ "$UNINSTALL" != 1 ] && [ "$rc" = 0 ]; then
  cat <<'EOF'

Next: export GEMINI_API_KEY=... and run `git commit` — the editor opens with an AI draft.
Installed globally by default, the hook runs in every git repository; use --dir PATH (per repo) or --all ROOT for narrower scopes, or --uninstall to remove it.
The hook never blocks a commit; without a key it is inert. SKIP_AI_COMMIT=1 bypasses.
EOF
fi
exit "$rc"
