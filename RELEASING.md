# Releasing hoosky

A release is a **tag**, not a worktree: `install.sh` downloads `prepare-commit-msg` and
`checksums.txt` from the `TAG` ref on GitHub. There is no CI, so every check below is local
and must be run by hand. Skipping a step ships an installer that refuses its own hook.

## Single source of truth

`TAG=` in `install.sh` is the one authoritative version. It has to be embedded there
because the documented install path is `curl … | bash` — there is no sibling file to read.
The `usage()` examples interpolate `${TAG}`, so they follow a bump automatically.

Every other literal `vX.Y.Z` in the tree (currently the two GitHub URLs in `README.md`)
must be kept in sync manually. `make check-version` fails if any tracked file disagrees
with `TAG`. `AGENTS.md` deliberately names no version, so it never needs a bump.

## Preflight

```sh
git status --short          # must be clean
git branch --show-current   # main
git fetch --tags
```

Do not release from a dirty tree or from a branch other than `main`.

## Steps

1. **Pick the new version** `vX.Y.Z` (SemVer) and bump the constant in `install.sh`:

   ```sh
   # install.sh: TAG="vX.Y.Z"
   ```

2. **Update the remaining literal references.** In `README.md`, change both the quick
   install URL and the manual-download URL to `vX.Y.Z`. Then confirm nothing drifted:

   ```sh
   make check-version        # all release references match TAG=vX.Y.Z
   ```

3. **Land the code changes** for the release (hook and/or installer). If `install.sh`
   changed, re-check `make install ARGS='--help'` — the examples must show the new tag.

4. **Regenerate the published checksums.** This is mandatory after _any_ edit to
   `prepare-commit-msg` or `install.sh`; a stale hash makes the installer reject the hook
   for every user:

   ```sh
   make checksums
   ```

5. **Run every gate.** Stop on the first red check — the Makefile is the single source of
   truth for these commands:

   ```sh
   make test
   ```

6. **Commit** the hook, installer, docs, `checksums.txt`, and any `specs/pomona/tasks.md`
   updates together. The commit is what the tag will point at.

7. **Move the tag to that commit and publish it.** For a new tag:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

   For a re-release of an existing tag (only when you must replace a bad release):

   ```sh
   git tag -f vX.Y.Z
   git push origin vX.Y.Z --force
   ```

   Force-moving a published tag is disruptive: anyone who already installed from it keeps
   the old hook. Call it out in the release notes.

8. **Verify the published tag, not the worktree.** `install.test.sh` serves files from this
   tree, so passing it proves nothing about what was pushed. From a clean directory:

   ```sh
   curl -fsSL "https://raw.githubusercontent.com/organiqlabs/hoosky/vX.Y.Z/checksums.txt"
   curl -fsSL "https://raw.githubusercontent.com/organiqlabs/hoosky/vX.Y.Z/install.sh" | bash -n
   ```

   Confirm the printed hook hash equals the `sha256sum` of the hook at that tag, and do one
   throwaway install (`--dir` into a scratch repo) so the real checksum verification runs.

## Checklist

- [ ] `TAG` bumped; `make check-version` green
- [ ] `README.md` URLs updated
- [ ] `checksums.txt` regenerated after the last hook/installer edit
- [ ] `make test` green (all gates)
- [ ] Commit contains everything above
- [ ] Tag points at that commit and is pushed
- [ ] Published tag verified from a clean directory
