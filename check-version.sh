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

# Scan tracked files for literal vX.Y.Z tokens, so the check also works while a
# release is being staged. Restricting to tracked files keeps .gitignored local
# state (.specify/, specs/pomona/) and untracked scratch files from failing the
# gate; a doc only matters once it is added. This script contains only the regex,
# never a literal version, so it cannot flag itself.
versions="$(git grep -IhoE 'v[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null | sort -u)"

if [ -z "$versions" ] || [ "$versions" = "$tag" ]; then
  printf 'check-version: all release references match TAG=%s\n' "$tag"
  exit 0
fi

printf 'check-version: TAG=%s but the tree also references:\n%s\n' "$tag" "$versions" >&2
printf 'update README.md (and any other vX.Y.Z reference) to match; see RELEASING.md\n' >&2
exit 1
