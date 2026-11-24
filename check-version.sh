#!/usr/bin/env bash
# Verify that install.sh's TAG is the single source of truth for the release version.
# The installer runs via `curl | bash`, so the tag must live inside install.sh; docs that
# spell out the version are checked here instead. See RELEASING.md.
set -u
cd "$(dirname "$0")" || exit 1

tag="$(sed -n 's/^TAG="\(v[0-9][0-9.]*\)"$/\1/p' install.sh | head -1)"
if [ -z "$tag" ]; then
  printf 'check-version: could not read TAG="v..." from install.sh\n' >&2
  exit 1
fi

# Scan only the release-bearing files. install.sh owns TAG; README.md carries the
# two published install URLs. Unrelated tracked docs may quote historical versions
# (CHANGELOGs, migration notes, examples) without blocking a bump — an allowlist
# scales better than an exemption list, which would need editing for every new doc.
# Restricting to tracked files keeps .gitignored local state (.specify/,
# specs/pomona/) and untracked scratch files out of the gate. This script contains
# only the regex, never a literal version, so it cannot flag itself.
RELEASE_FILES=(install.sh README.md)
#
# No version reference at all means the scan did not run, not that the tree is
# clean: install.sh's TAG line is tracked, so a successful scan always matches at
# least once. Fail instead of reporting a vacuous pass (a source archive has no
# .git, and `git grep` exits 128 there).
matches="$(git grep -IhoE 'v[0-9]+\.[0-9]+\.[0-9]+' -- "${RELEASE_FILES[@]}")"
grc=$?
if [ "$grc" -ne 0 ] && [ "$grc" -ne 1 ]; then                 # 128 = no work tree; 1 = no matches
  printf 'check-version: could not scan tracked files; run this from a git clone (git grep exited %s)\n' "$grc" >&2
  exit 1
fi
versions="$(printf '%s\n' "$matches" | sort -u)"

if [ -z "$versions" ]; then                                   # rc 1, or an empty tree: same vacuous pass
  printf 'check-version: scan found no version references (expected TAG=%s from install.sh)\n' "$tag" >&2
  printf 'run this from a git clone with install.sh tracked; see RELEASING.md\n' >&2
  exit 1
fi

if [ "$versions" = "$tag" ]; then
  printf 'check-version: all release references match TAG=%s\n' "$tag"
  exit 0
fi

printf 'check-version: TAG=%s but these release-bearing files disagree:\n%s\n' "$tag" "$versions" >&2
printf 'update %s to match; see RELEASING.md\n' "${RELEASE_FILES[*]}" >&2
exit 1
