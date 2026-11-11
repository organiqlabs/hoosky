# AGENTS.md

Standalone Gemini-backed commit-message drafting hook. Files: `prepare-commit-msg` (bash),
`prepare-commit-msg.test.sh` (zero-dep harness), `README.md`, `ROADMAP.md` (pomona
backlog — open P1–P3 items are worked down to zero; P4 holds parked decisions,
don't implement them without asking). Git repo, branch `main`; no manifest, CI,
or build. Don't invent toolchain commands.

## Identity

- The file is named `prepare-commit-msg`; install it as Git's `prepare-commit-msg` hook:
  `install -m755 prepare-commit-msg /path/to/repo/.git/hooks/prepare-commit-msg`.
  This repo has it installed at `.git/hooks/prepare-commit-msg` for dogfooding, so commits
  here fire the hook when `GEMINI_API_KEY` is set. Refresh it after hook changes:
  `install -m755 prepare-commit-msg .git/hooks/prepare-commit-msg`.
- Not the pre-commit framework (pre-commit.com): no `.pre-commit-config.yaml`, no Python
  dep, no pip. Don't look for framework config here.
- Not the same as `../hooks/` (sibling Bun/TypeScript project, organiqbit-hooks, with
  consent/audit/TOML config). This file is self-contained bash; don't port code between them.

## Behavior contract (preserve when editing)

- Never blocks a commit: every failure path warns on stderr and `exit 0`.
  `set -u` only, no `set -e`. Sole exception: SIGINT/SIGTERM (the user or git aborts the commit
  anyway) clean up and exit 130/143.
- Silent no-op when: no message-file argument; `SKIP_AI_COMMIT=1` (checked before any git/curl
  call); commit source is `message|merge|squash|commit` (i.e. `-m`, merge, squash, amend); the
  message file already has non-comment content; the staged diff is empty.
- Warns and exits 0 (message/file untouched) when: the message file is not readable, a directory,
  or a fifo; `curl`/`jq`/`git`/`grep`/`sed`/`tr` missing; `grep` cannot inspect the message file
  (rc≥2); the message directory is not writable; `GEMINI_API_KEY` unset or contains characters
  unsafe for the curl config (`"`, `\`, CR, LF); the response is unparseable, empty after
  fence-stripping, or over 10 MiB (`--max-filesize 10485760`).
- Diff excludes (case-insensitive, matched at any depth — root and nested; `*`-prefixed
  patterns apply everywhere): `.env*`, private-key/credential material (`*.pem`, `*.key`,
  `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `*.ppk`, `*id_rsa*`, `*id_dsa*`, `*id_ecdsa*`,
  `*id_ed25519*`, `*.aws/credentials`, `*.m2/settings.xml`), credential/config files
  (`*credentials*.json`, `*secrets.*`, `*.git-credentials`, `*.npmrc`, `*.pypirc`,
  `*.netrc`, `*.pgpass`, `*.htpasswd`, `*.docker/config.json`, `*.kube/config`), and
  lockfiles/minified assets (`*.lock`, `*package-lock.json`, `*pnpm-lock.yaml`,
  `*npm-shrinkwrap.json`, `*bun.lockb`, `*.min.js`, `*.min.css`, `*.map`).
  Keep these intact — they exist so secrets never reach the API. `prepare-commit-msg.test.sh`
  has sentinel matrix tests for them (`# 16`).
- API key goes to curl via `-K -` on stdin, never argv (keeps it out of `ps`). Don't "simplify" this.
- Diff truncates to `GEMINI_MAX_DIFF_CHARS` (default 30000, cut at a line boundary — or kept as a
  raw slice with a different NOTE wording when the first 30000 chars contain no newline);
  `GEMINI_MODEL` default `gemini-3.5-flash-lite` (validated against `A-Za-z0-9._-`; anything else
  warns and falls back); `GEMINI_TIMEOUT` default 20s (over 2 digits ⇒ 20).
  Env-var fallback rules (all zero-style values such as `00` count as zero, which
  also falls back): `GEMINI_MAX_DIFF_CHARS` non-numeric, ≤0, or >15 digits → 30000;
  `GEMINI_TIMEOUT` non-numeric, ≤0, or >2 digits → 20; subject/body knobs below need
  ≤0, non-numeric, or >3 digits to fall back. `git diff` runs with `--no-ext-diff --no-textconv`
  so user config/textconv drivers can't alter or leak the payload; `--stat` is capped at
  4000 bytes (byte-accurate `wc -c` precheck; a possibly partial first tail line is dropped on cut).
- Output: Conventional Commits, subject ≤50 chars (`GEMINI_MAX_SUBJECT_CHARS`, cut at a
  word boundary) and body wrapped at 75 cols (`GEMINI_BODY_WRAP_CHARS`), both enforced after
  the API response — not merely requested in the prompt; non-numeric, ≤0 (incl. 00-style),
  or >3-digit values fall back to the defaults. Strips code fences; prepends the draft above git's
  existing comment block (written via same-dir temp file + `mv`).
- `GEMINI_DETAIL_LEVEL` picks the detail tier sent in the prompt: `minimal` (default) | `standard`
  | `detailed` (case-insensitive); anything unrecognized warns and falls back to minimal. It never
  loosens the subject/body limits.

## Verify

- Deps: `bash`, `git`, `jq`, `grep` (curl at runtime; `tr`/`sed` are required POSIX tools).
- `bash -n prepare-commit-msg`
- `bash prepare-commit-msg.test.sh` — prints `all tests passed (N tests)` and exits 0 (or
  `FAILURES (N tests)` and exits 1). Zero deps beyond git/jq and coreutils POSIX tools
  (seq, sed, wc, tr, sort, ln, chmod, mktemp); stubs `curl` in scratch
  PATHs, never touches the network; runs in temp git repos.
