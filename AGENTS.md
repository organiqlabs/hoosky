# AGENTS.md

Standalone Gemini-backed commit-message drafting hook. Files: `pre-commit` (bash),
`test-pre-commit.sh` (zero-dep harness), `ROADMAP.md` (pomona backlog — P1–P3 empty;
P4 parking lot holds decisions that were considered and rejected, don't implement
parked items without asking). Git repo, branch `main`; no manifest, CI, or build.
Don't invent toolchain commands.

## Identity / naming trap

- Header comment says `.git/hooks/prepare-commit-msg`: it pre-fills the commit editor
  from the staged diff. Install as `.git/hooks/prepare-commit-msg`, e.g.
  `install -m755 pre-commit /path/to/repo/.git/hooks/prepare-commit-msg`. Installing
  here would run on every commit in this repo — it is **not** installed by default.
  The filename here is misleading.
- Not the pre-commit framework (pre-commit.com): no `.pre-commit-config.yaml`, no Python
  dep, no pip. Don't look for framework config here.
- Not the same as `../hooks/` (sibling Bun/TypeScript project, organiqbit-hooks, with
  consent/audit/TOML config). This file is self-contained bash; don't port code between them.

## Behavior contract (preserve when editing)

- Never blocks a commit: every failure path warns on stderr and `exit 0`.
  `set -u` only, no `set -e`.
- No-op when: `GEMINI_API_KEY` unset or contains characters unsafe for the curl config
  (`"`, `\`, CR, LF); `curl`/`jq`/`git` missing; staged diff empty;
  commit source is `message|merge|squash|commit` (i.e. `-m`, merge, squash, amend);
  or the message file already has non-comment content.
- `SKIP_AI_COMMIT=1` bypasses entirely (before any git/curl call).
- Diff excludes `.env*` (case-insensitive), private-key/credential material, and
  lockfiles/minified assets (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`,
  `id_rsa*`, `.npmrc`, `.pypirc`, `.netrc`, `.git-credentials`, `credentials*.json`,
  `secrets.*`, `*.lock`, `package-lock.json`, `pnpm-lock.yaml`, `npm-shrinkwrap.json`,
  `bun.lockb`, `*.min.js`, `*.min.css`, `*.map`). Keep these intact — they exist so
  secrets never reach the API. `test-pre-commit.sh` has sentinel tests for them.
- API key goes to curl via `-K -` on stdin, never argv (keeps it out of `ps`). Don't "simplify" this.
- Diff truncates to `GEMINI_MAX_DIFF_CHARS` (default 30000, cut at a line boundary);
  `GEMINI_MODEL` default `gemini-3.5-flash-lite`; `GEMINI_TIMEOUT` default 20s.
  Non-numeric, zero, or absurdly large `GEMINI_MAX_DIFF_CHARS`/`GEMINI_TIMEOUT`
  (>15 digits) fall back to the defaults. `git diff` runs with `--no-ext-diff --no-textconv`
  so user config/textconv drivers can't alter or leak the payload; `--stat` is capped.
- Output: Conventional Commits, subject ≤50 chars (`GEMINI_MAX_SUBJECT_CHARS`, cut at a
  word boundary) and body wrapped at 75 cols (`GEMINI_BODY_WRAP_CHARS`), both enforced after
  the API response — not merely requested in the prompt; non-numeric, zero, or >3-digit
  values fall back to the defaults. Strips code fences; prepends the draft above git's
  existing comment block (written via same-dir temp file + `mv`).

## Verify

- Deps: `bash`, `git`, `jq`.
- `bash -n pre-commit`
- `bash test-pre-commit.sh` — prints `all tests passed (N tests)` and exits 0 (or
  `FAILURES (N tests)` and exits 1). Zero deps beyond git/jq; stubs `curl` in scratch
  PATHs, never touches the network; runs in temp git repos.
