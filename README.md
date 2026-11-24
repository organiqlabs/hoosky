# hoosky

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

One Gemini request drafts a Conventional Commits message from your staged diff and
pre-fills the commit editor. It never blocks a commit: every failure path falls
back to the normal empty message. (Sole exception: Ctrl-C/kill aborts the commit
— and cleans up its temp files — as any interrupt would.)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.1/install.sh | bash
```

That installs the `prepare-commit-msg` hook into your **global git hooks directory** —
`~/.config/git/hooks` by default, or the directory your global `core.hooksPath` points at —
so it runs in every repository. If `core.hooksPath` isn't set yet, the installer creates
`~/.config/git/hooks`, sets `core.hooksPath` globally to point at it, and warns loudly:
**a global `core.hooksPath` makes Git ignore every repository's `.git/hooks` directory, so
any pre-existing repo-local hooks stop running.** Use `--dir PATH` or `--all ROOT` to avoid
that. Other modes: `--dir PATH` (one repo at PATH; repeatable), `--all ~/src` (every repo under a root),
`--global` (explicit form of the default), `--uninstall` (removes only if it matches the
published checksum; add `--force` to override). The installer verifies the downloaded hook
against `checksums.txt` from the same tag and refuses to install unverified code.
Note: when `core.hooksPath` is set anywhere (global or repo-local), `--dir`/`--all` install
into the hooks directory git resolves for those repos — possibly a shared global directory —
not `.git/hooks`.
Then verify:

```sh
test -x "$(git config --global core.hooksPath)/prepare-commit-msg" && echo hook-installed
```

Prefer no curl-pipe? The manual equivalent:

```sh
mkdir -p "$HOME/.config/git/hooks"
[ -n "$(git config --global core.hooksPath)" ] || git config --global core.hooksPath "$HOME/.config/git/hooks"
curl -fsSL -o "$(git config --global core.hooksPath)/prepare-commit-msg" \
  https://raw.githubusercontent.com/organiqlabs/hoosky/v1.0.1/prepare-commit-msg
chmod 0755 "$(git config --global core.hooksPath)/prepare-commit-msg"
```

Per-repo instead of global? Swap `$(git config --global core.hooksPath)` for
`$(git rev-parse --git-path hooks)` and skip the config line. To go back,
`git config --global --unset core.hooksPath` restores per-repo hooks. `--uninstall` does
that automatically when hoosky set the path and no other hooks share the directory; it
never removes a `core.hooksPath` you configured yourself.

The default/global install resolves `~/...` and the XDG config dir from `HOME`; if `HOME`
is unset it exits with a clear error telling you to set it or use `--dir`/`--all`.
Per-repo installs do not need `HOME`.

The file is named `prepare-commit-msg`, and that's what it installs as — Git's
`prepare-commit-msg` hook. It is not the `pre-commit.com` framework and not the
sibling `organiqbit-hooks` TypeScript project. For dogfooding, refresh the hook in the
directory Git actually resolves for this repo. When `core.hooksPath` is set — the installer
sets it globally by default — a copy in `.git/hooks` is shadowed and never runs:

```sh
install -m755 prepare-commit-msg "$(git rev-parse --git-path hooks)/prepare-commit-msg"
```

`git rev-parse --git-path hooks` resolves correctly with or without `core.hooksPath`.

## Use

```sh
git commit                  # editor opens pre-filled with an AI draft
SKIP_AI_COMMIT=1 git commit # bypass entirely
```

Set `GEMINI_API_KEY` first. On the warning paths — e.g. a missing tool, an unreadable or
fifo message file, an unparseable or oversized API response, an unwritable message directory,
a backend tool failure (mktemp/jq/mv), an unsafe or unset key — the hook prints a one-line
reason to stderr and exits 0 without modifying your message. On `SKIP_AI_COMMIT=1`, `-m`/merge/squash/amend, a message file that already has content, or an empty staged diff it exits 0 silently. Either way, the commit behaves exactly as if the hook weren't installed.

The draft is post-processed once: trailing dangling connector words (e.g. a response ending in
"and the") are dropped, and the body is re-wrapped to 82 columns while the subject line is left
as the model wrote it.

| Variable                  | Default                 | Meaning                                             |
| ------------------------- | ----------------------- | --------------------------------------------------- |
| `GEMINI_API_KEY`          | —                       | Required. Sent to curl via stdin config, never argv |
| `GEMINI_MODEL`            | `gemini-3.5-flash-lite` | Model ID                                            |
| `GEMINI_MAX_INPUT_TOKENS` | `8000`                  | Input token budget; derives the diff cap            |
| `GEMINI_MAX_DIFF_CHARS`   | (derived: `18000`)      | Manual cap override; may only narrow the budget     |
| `GEMINI_TIMEOUT`          | `20`                    | Seconds before curl gives up                        |
| `GEMINI_DETAIL_LEVEL`     | `minimal`               | Detail tier: `minimal` \| `standard` \| `detailed`  |

Knob fallbacks: values that are non-numeric, zero-style (e.g. `00`), or oversized fall back to the
default (`>9`-digit token budget, `>15`-digit diff, `>2`-digit timeout). An invalid `GEMINI_MODEL`
id warns and falls back to `gemini-3.5-flash-lite`.

The diff cap is derived from the input token budget rather than fixed, so it tracks your plan
tier: `cap = GEMINI_MAX_INPUT_TOKENS * 3 - 6000`, floored at 2000 characters. The default 8000
tokens yields an 18000-character cap. **This is a heuristic, not exact token accounting:** the
`3` chars/token ratio and the `6000`-character overhead are conservative rules of thumb that
have never been measured against Gemini's tokenizer or a real per-minute quota. The formula
deliberately truncates early (code tokenizes denser than prose, and the cushion reserves room
for the prompt and model output) rather than risk a request the API rejects. Treat the default
as a safe starting point and tune `GEMINI_MAX_INPUT_TOKENS` empirically: **on a free tier,
lower it; on a paid tier, raise it.**
Setting `GEMINI_MAX_DIFF_CHARS` explicitly overrides the derived value but can only narrow it — a
larger value is clamped down, because the token budget is the hard ceiling. If the cap falls
mid-line, the raw slice is used and the truncation note says so; the note also names the token
budget that caused the cut. API responses over 10 MiB are refused by curl.

Staged secret/credential material is excluded from the diff sent to the API, matched
at any depth (root and nested), case-insensitively. The generated deny-list is:

<!-- BEGIN GENERATED DENY-LIST -->
- Environment files: `*.env`, `*.env.*`, `*.envrc*`.
- Credential and config files: `*.npmrc`, `*.pypirc`, `*.netrc`, `*.git-credentials`, `*credentials*.json`, `*secrets.*`, `*.pgpass`, `*.htpasswd`, `*.docker/config.json`, `*.kube/config`, `*.aws/credentials`, `*.m2/settings.xml`, `*.dockercfg`, `*_netrc`, `*.cargo/credentials*`, `*.gem/credentials`.
- Private keys and certificates: `*id_rsa*`, `*id_dsa*`, `*id_ecdsa*`, `*id_ed25519*`, `*.ppk`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `*.pem`, `*.key`, `*.asc`, `*.gpg`.
- Terraform material: `*.tfstate*`.
- Vault material: `*.vault-token`, `*.vault_pass`, `*vault-password*`, `*vault_password*`.
- Kerberos material: `*.keytab`.
- Apple keys: `*.p8`.
- Yarnrc auth: `*.yarnrc*`.
- Lockfiles: `*.lock`, `*package-lock.json`, `*npm-shrinkwrap.json`, `*pnpm-lock.yaml`, `*bun.lockb`.
- Minified assets: `*.min.js`, `*.min.css`, `*.map`.
<!-- END GENERATED DENY-LIST -->

The exclude list deliberately errs on the safe side: a legitimate file whose name matches an
exclude pattern (e.g. `*secrets.*`) is kept out of the payload — that is intentional. `.git` history and
hook files are not part of the payload, and the API key is never exposed in `ps` output.
The list above is generated from [secret-excludes.registry](secret-excludes.registry); edit the
registry and run `make generate-excludes`, never the generated block.

## Development

The [Makefile](Makefile) is the single source of truth for the install and verification
commands. Run every local gate with:

```sh
make test                  # syntax, generated-block drift, version, suites, checksums
make generate-excludes     # regenerate the four deny-list copies from the registry
make check-installed-hook  # dogfooding: does the installed hook match checksums.txt?
make help                  # all targets (install, uninstall, checksums, ...)
```

From a checkout, `make install` runs the installer (global by default); pass
`make install ARGS="--dir PATH"` for a narrower scope. The plain `curl … | bash` command
above remains the way to install without a checkout.

Deps: `bash`. The installer needs `curl`, `git`, `awk`, `sed`, `sort`, `find`, and
`sha256sum` (or `shasum` on BSD/macOS) — checked up front, exit 1 if missing — plus
`mktemp`, `mkdir`, `cp`, `chmod` and `mv` (unchecked; the install fails without them).
The hook guards `curl`/`jq`/`git`/`grep`/`sed`/`tr`/`dirname`/`tail`/`cat` (warn + exit 0);
its other userland (`wc`/`head`/`mktemp`/`mv`/`chmod`/`rm`/`dd`/`od`) degrades silently.
The diff-stat cap uses POSIX `dd`/`od`, so it works on BSD/macOS without coreutils.
`make test` adds `make`, `awk` and `sort`. No build, no CI, no manifest beyond the Makefile.

Release procedure (bumping the tag, checksums, and docs): [RELEASING.md](RELEASING.md). `TAG` in `install.sh` is the single source of truth for the version.
Repo conventions for agents: [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE). © 2026 Abdulwahab
