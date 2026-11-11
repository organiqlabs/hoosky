#!/usr/bin/env bash
# hoosky installer — fetches the prepare-commit-msg hook from the published tag
# and installs it into one or more git repositories. Not the hook itself:
# the hook drafts a Conventional Commits message with one Gemini request.
set -u

ORG_REPO="organiqlabs/hoosky"
TAG="v1.0.0"
RAW="https://raw.githubusercontent.com/${ORG_REPO}/${TAG}"
HOOK_NAME="prepare-commit-msg"

err()  { printf 'hoosky-install: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
hoosky installer — installs the prepare-commit-msg hook into git repo(s)

usage: install.sh [options]

  --dir PATH       install into the repo at PATH (repeatable); default: repo at cwd
  --all ROOT       discover repos under ROOT and install into each
  --uninstall      remove hoosky (only if the installed hook matches the published checksum)
  --force          overwrite an unmanaged hook, or uninstall without the checksum match
  --help           this text

Examples:
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash -s -- --all ~/src
  curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.0/install.sh | bash -s -- --uninstall
EOF
}

DIRS=()
ALL_ROOT=""
UNINSTALL=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)       shift; [ $# -gt 0 ] || { err "--dir needs a value"; exit 2; }; DIRS+=("$1") ;;
    --all)       shift; [ $# -gt 0 ] || { err "--all needs a value"; exit 2; }; ALL_ROOT="$1" ;;
    --uninstall) UNINSTALL=1 ;;
    --force)     FORCE=1 ;;
    --help|-h)   usage; exit 0 ;;
    *)           err "unknown flag '$1' (see --help)"; exit 2 ;;
  esac
  shift
done

for cmd in curl git sha256sum awk sort find; do
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' not found; install it and retry"; exit 1; }
done

# Print the deduplicated list of repo roots to act on.
discover_repos() {
  if [ ${#DIRS[@]} -gt 0 ]; then
    printf '%s\n' "${DIRS[@]}"
    return
  fi
  if [ -n "$ALL_ROOT" ]; then
    { git -C "$ALL_ROOT" rev-parse --show-toplevel 2>/dev/null;
      find "$ALL_ROOT" -name .git -prune -print 2>/dev/null | sed 's:/.git$::'; } | while IFS= read -r d; do
        git -C "$d" rev-parse --git-path hooks >/dev/null 2>&1 && printf '%s\n' "$d"
      done | sort -u
    return
  fi
  git rev-parse --show-toplevel 2>/dev/null || { err "not inside a git repository (pass --dir PATH or --all ROOT)"; exit 1; }
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

# Download once (install path only), verify once, then act per repo. Fetch the
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

install_one() {  # <repo> -> 0 ok, 1 failed
  local repo="$1" hd dest before_ts
  hd="$(repo_hooks_dir "$repo")" || { err "$repo: not a git repository; skipping"; return 1; }
  dest="$hd/$HOOK_NAME"
  before_ts="$(date +%Y%m%d%H%M%S)"

  if [ "$UNINSTALL" = 1 ]; then
    if [ ! -e "$dest" ]; then
      printf '%s\n' "$repo: no hook installed; nothing to do"
      return 0
    fi
    if [ -z "$HOOK_SUM" ]; then
      err "$repo: could not fetch checksums.txt; refusing to uninstall without --force"
      return 1
    fi
    if [ "$(file_sum "$dest")" != "$HOOK_SUM" ] && [ "$FORCE" != 1 ]; then
      err "$repo: installed hook is not the hoosky hook (checksum differs); refusing without --force"
      return 1
    fi
    mv "$dest" "$dest.uninstalled.$before_ts"
    printf '%s\n' "$repo: uninstalled (moved to $HOOK_NAME.uninstalled.$before_ts)"
    return 0
  fi

  if [ -e "$dest" ]; then
    if [ "$(file_sum "$dest")" = "$HOOK_SUM" ] && [ "$FORCE" != 1 ]; then
      printf '%s\n' "$repo: already at $TAG; refreshing anyway"
    elif [ "$FORCE" = 1 ]; then
      cp -a "$dest" "$dest.bak.$before_ts"
      printf '%s\n' "$repo: existing hook backed up to $HOOK_NAME.bak.$before_ts"
    else
      err "$repo: $HOOK_NAME exists and is not hoosky; refusing to overwrite without --force (backup will be made)"
      return 1
    fi
  fi

  mkdir -p "$hd"
  cp -a "$TMPD/$HOOK_NAME" "$dest"
  chmod 0755 "$dest"
  printf '%s\n' "$repo: hoosky installed (hook: $dest)"
}

rc=0
while IFS= read -r repo; do
  case "$repo" in '') continue ;; esac
  ( install_one "$repo" ) || rc=1
done < <(discover_repos)

if [ "$UNINSTALL" != 1 ]; then
  cat <<'EOF'

Next: export GEMINI_API_KEY=... and run `git commit` — the editor opens with an AI draft.
The hook never blocks a commit; without a key it is inert. SKIP_AI_COMMIT=1 bypasses.
Uninstall with the same command plus: --uninstall
EOF
fi
exit "$rc"
