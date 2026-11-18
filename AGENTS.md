# AGENTS.md

Standalone Gemini-backed commit-message drafting hook. Files: `prepare-commit-msg` (bash),
`prepare-commit-msg.test.sh` (POSIX-only harness), `README.md`, `ROADMAP.md` (pomona
backlog — open P1–P3 items are worked down to zero; P4 holds parked decisions,
don't implement them without asking), `.gitignore`, `.gitattributes`, `LICENSE` (MIT),
`install.sh` (curl installer for the hook; default target is the global git hooks
directory — sets `core.hooksPath` to `~/.config/git/hooks` globally after a successful
global install when unset; `--dir`/`--all` target specific repos; `--global` is the
explicit form of the default) and `checksums.txt` (published sha256 of the hook and
itself, read from the tag at install time; regenerate after any edit to `prepare-commit-msg`
or `install.sh` with `make checksums`). Git repo, branch `main`; no CI or build beyond
the Makefile. Don't invent toolchain commands. This repo is published as
`organiqlabs/hoosky` — `install.sh` downloads the release tag defined by `TAG` in
`install.sh`, not the worktree. See `RELEASING.md` for the release procedure; `TAG` is the
single source of truth and `make check-version` verifies docs match it.

## Identity

- The file is named `prepare-commit-msg`; install it as Git's `prepare-commit-msg` hook:
  `install -m755 prepare-commit-msg /path/to/repo/.git/hooks/prepare-commit-msg`.
  Dogfooding: `core.hooksPath` set anywhere (e.g. the installer's own global default,
  `~/.config/git/hooks`) shadows `$GIT_DIR/hooks` entirely — a repo-local copy then never
  runs. On hooksPath machines, dogfood by refreshing the hooksPath-resolved copy instead:
  `install -m755 prepare-commit-msg "$(git rev-parse --git-path hooks)/prepare-commit-msg"`
  (`--git-path hooks` resolves correctly either way).
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
  or a fifo; `curl`/`jq`/`git`/`grep`/`sed`/`tr`/`dirname`/`tail`/`cat` missing; `grep` cannot inspect the message file
  (rc≥2); the message directory is not writable; `GEMINI_API_KEY` unset or contains characters
  unsafe for the curl config (`"`, `\`, CR, LF); the response is unparseable, empty after
  fence-stripping, or over 10 MiB (`--max-filesize 10485760`).
- Diff excludes (case-insensitive, matched at any depth — root and nested; `*`-prefixed
  patterns apply everywhere): `*.env`, `*.env.*`, `*.envrc*`, private-key/credential material (`*.pem`, `*.key`,
  `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `*.ppk`, `*.asc`, `*.gpg`, `*id_rsa*`, `*id_dsa*`, `*id_ecdsa*`,
  `*id_ed25519*`, `*.aws/credentials`, `*.m2/settings.xml`), credential/config files
  (`*credentials*.json`, `*secrets.*`, `*.git-credentials`, `*.npmrc`, `*.pypirc`,
  `*.netrc`, `*_netrc`, `*.pgpass`, `*.htpasswd`, `*.docker/config.json`, `*.kube/config`,
  `*.dockercfg`, `*.cargo/credentials*`, `*.gem/credentials`), Terraform/Vault/Kerberos/Apple material
  (`*.tfstate*`, `*.vault-token`, `*.vault_pass`, `*vault-password*`, `*vault_password*`, `*.keytab`,
  `*.p8`), yarnrc auth (`*.yarnrc*`), and
  lockfiles/minified assets (`*.lock`, `*package-lock.json`, `*pnpm-lock.yaml`,
  `*npm-shrinkwrap.json`, `*bun.lockb`, `*.min.js`, `*.min.css`, `*.map`).
  The deny-list errs on the safe side by design: a legitimate source file whose name matches an
  exclude pattern (e.g. `*secrets.*`) is kept out of the payload; tightening it risks leaking a real
  credential. Keep these intact — they exist so secrets never reach the API.
  `prepare-commit-msg.test.sh` has sentinel matrix tests for them (`# 16`).
- API key goes to curl via `-K -` on stdin, never argv (keeps it out of `ps`). Don't "simplify" this.
- Diff cap is derived from an **input-token budget**, not a blind constant:
  `cap_chars = GEMINI_MAX_INPUT_TOKENS * 3 - 6000` (floored at 2000), because the diff has to fit
  the plan tier's input quota — a fixed 30000 chars can blow a free-tier per-minute budget and
  surface as a silent `no message generated`. `GEMINI_MAX_INPUT_TOKENS` default 8000 (⇒ 18000-char
  cap); the 3 chars/token ratio is deliberately conservative (code tokenizes denser than prose, so
  under-estimating truncates early rather than risking a rejected request). Raise it for a paid
  tier; the NOTE names the budget so a truncated payload is self-explaining. The `3` chars/token
  ratio and `6000`-char overhead are **unmeasured heuristics**, not tokenizer/quota measurements;
  keep describing them that way in docs and tune the budget empirically rather than claiming
  exact accounting.
  `GEMINI_MAX_DIFF_CHARS`, when set, is a manual override that may only **narrow**: a value above
  the derived cap is clamped down to it (the token budget is a hard ceiling), so a stale large
  value cannot silently push the request past the quota. Truncation itself is unchanged: cut at a
  line boundary, or a raw slice with different NOTE wording when no newline exists in the cut.
  `GEMINI_MODEL` default `gemini-3.5-flash-lite` (validated against `A-Za-z0-9._-`; anything else
  warns and falls back); `GEMINI_TIMEOUT` default 20s (over 2 digits ⇒ 20).
  Env-var fallback rules (all zero-style values such as `00` count as zero, which
  also falls back): `GEMINI_MAX_INPUT_TOKENS` non-numeric, ≤0, or >9 digits → 8000;
  `GEMINI_MAX_DIFF_CHARS` non-numeric, ≤0, or >15 digits → the token-derived cap;
  `GEMINI_TIMEOUT` non-numeric, ≤0, or >2 digits → 20; subject/body knobs below need
  ≤0, non-numeric, or >3 digits to fall back. `git diff` runs with `--no-ext-diff --no-textconv`
  so user config/textconv drivers can't alter or leak the payload; `--stat` is capped at
  4000 bytes (byte-accurate `wc -c` precheck; a possibly partial first tail line is dropped on cut;
  a single >4000-byte stat line with no newline is kept as the raw 4000-byte slice).
- Output: Conventional Commits is requested in the prompt, but the hook does **not** enforce a
  subject limit or re-wrap the body after the API response — the response text is written through
  verbatim after control-char/fence stripping. Strips code fences; prepends the draft above git's existing
  comment block (written via same-dir temp file + `mv`).
- `GEMINI_DETAIL_LEVEL` picks the detail tier sent in the prompt: `minimal` (default) | `standard`
  | `detailed` (case-insensitive); anything unrecognized warns and falls back to minimal. It does
  not alter the message text.

## Verify

- `make test` is the single source of truth for all local gates (defined in `Makefile`);
  `make help` lists the install/uninstall/checksums targets. Don't add a new install or test
  command to the docs without adding a Makefile target first.
- Deps: `bash`, `git`, `jq`, `grep`, `make` (curl at runtime; plus required standard userland:
  `tr`, `sed`, `wc`, `tail`, `head`, `dirname`, `cat`, `mktemp`, `mv`, `chmod`, `rm` — the
  unguarded ones degrade silently without blocking the commit).
- `make test` runs `bash -n` on the hook, installer and checker, `check-version.sh`, both
  suites, and a checksum recompute/diff. The hook suite prints `all tests passed (N tests)`
  and exits 0 (or `FAILURES (N tests)` and exits 1). Deps: git/jq + POSIX tools (seq, awk,
  sed, wc, tr, sort, ln, chmod, mktemp, cmp, sha1sum (or `shasum -a 1`), mkfifo, id, env, cp,
  dirname, cat, head, tail); the `awk`/`cmp`/`sha1sum` are not coreutils. It stubs `curl` in
  scratch PATHs, never touches the network, and runs in temp git repos with
  `GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null`.
- The installer suite stubs `curl` the same way and sandboxes `HOME`/`GIT_CONFIG_GLOBAL` per
  case, so it never touches the real home or this machine's global git config.
