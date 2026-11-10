# AGENTS.md

Standalone Gemini-backed commit-message drafting hook. Files: `pre-commit` (bash),
`test-pre-commit.sh` (zero-dep harness). Not a git repo; no manifest, CI, or build.
Don't invent toolchain commands.

## Identity / naming trap

- Header comment says `.git/hooks/prepare-commit-msg`: it pre-fills the commit editor
  from the staged diff. Install as `.git/hooks/prepare-commit-msg` (copy or symlink),
  not as `pre-commit` — the filename here is misleading.
- Not the same as `../hooks/` (sibling Bun/TypeScript project, organiqbit-hooks, with
  consent/audit/TOML config). This file is self-contained bash; don't port code between them.

## Behavior contract (preserve when editing)

- Never blocks a commit: all failure paths warn on stderr and `exit 0`. `set -u` only, no `set -e`.
- No-op when: `GEMINI_API_KEY` unset; `curl`/`jq`/`git` missing; staged diff empty;
  commit source is `message|merge|squash|commit` (i.e. `-m`, merge, squash, amend);
  or the message file already has non-comment content.
- `SKIP_AI_COMMIT=1` bypasses entirely.
- Diff excludes lockfiles, `*.min.js`, `.env*`, `*.pem`, `*.key` — keep the secret exclusions intact.
- API key goes to curl via `-K -` on stdin, never argv (keeps it out of `ps`). Don't "simplify" this.
- Diff truncates to `GEMINI_MAX_DIFF_CHARS` (default 30000) before sending; `GEMINI_MODEL`
  default `gemini-3.5-flash-lite`; `GEMINI_TIMEOUT` default 20s.
- Output: Conventional Commits, subject ≤72 chars, body wrapped at 72; strips code fences;
  prepends the draft above git's existing comment block.

## Verify

- `bash -n pre-commit`
- `bash test-pre-commit.sh` — zero-dep harness; stubs `curl` in a scratch PATH (never
  touches the network), uses real `git`+`jq` in temp repos.
