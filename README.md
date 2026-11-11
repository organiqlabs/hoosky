# organiqbit/scripts

One Gemini request drafts a Conventional Commits message from your staged diff and
pre-fills the commit editor. It never blocks a commit: every failure path falls
back to the normal empty message. (Sole exception: Ctrl-C/kill aborts the commit
— and cleans up its temp files — as any interrupt would.)

## Install

```sh
install -m755 prepare-commit-msg /path/to/repo/.git/hooks/prepare-commit-msg
test -x /path/to/repo/.git/hooks/prepare-commit-msg && echo hook-installed
```

The file is named `prepare-commit-msg`, and that's what it installs as — Git's
`prepare-commit-msg` hook. It is not the `pre-commit.com` framework and not the
sibling `organiqbit-hooks` TypeScript project. This repo has it installed at
`.git/hooks/prepare-commit-msg` for dogfooding; refresh the installed copy after
hook changes with `install -m755 prepare-commit-msg .git/hooks/prepare-commit-msg`.

## Use

```sh
git commit                  # editor opens pre-filled with an AI draft
SKIP_AI_COMMIT=1 git commit # bypass entirely
```

Set `GEMINI_API_KEY` first. On the warning paths — e.g. a missing tool, an unreadable or
fifo message file, an unparseable or oversized API response, an unwritable message directory,
a backend tool failure (mktemp/jq/mv), an unsafe or unset key — the hook prints a one-line
reason to stderr and exits 0 without modifying your message. On `SKIP_AI_COMMIT=1`, `-m`/merge/squash/amend, a message file that already has content, or an empty staged diff it exits 0 silently. Either way, the commit behaves exactly as if the hook weren't installed.

| Variable                   | Default                 | Meaning                                             |
| -------------------------- | ----------------------- | --------------------------------------------------- |
| `GEMINI_API_KEY`           | —                       | Required. Sent to curl via stdin config, never argv |
| `GEMINI_MODEL`             | `gemini-3.5-flash-lite` | Model ID                                            |
| `GEMINI_MAX_DIFF_CHARS`    | `30000`                 | Diff is truncated at a line boundary                |
| `GEMINI_TIMEOUT`           | `20`                    | Seconds before curl gives up                        |
| `GEMINI_MAX_SUBJECT_CHARS` | `50`                    | Subject limit; cut at a word boundary               |
| `GEMINI_BODY_WRAP_CHARS`   | `75`                    | Body wrap width                                     |
| `GEMINI_DETAIL_LEVEL`      | `minimal`               | Detail tier: `minimal` \| `standard` \| `detailed`  |

Knob fallbacks: values that are non-numeric, zero-style (e.g. `00`), or oversized fall back to the
default (`>15`-digit diff, `>2`-digit timeout, `>3`-digit subject/body). An invalid `GEMINI_MODEL`
id warns and falls back to `gemini-3.5-flash-lite`. If the first `GEMINI_MAX_DIFF_CHARS` characters
(default 30000) of the diff contain no newline, the raw slice is used and the truncation note says so. API responses over 10 MiB are refused by curl.

Staged secret/credential material is excluded from the diff sent to the API, matched
at any depth (root and nested), case-insensitively: `.env`, `.env.*` and `.envrc`
files, private keys and certificates (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`,
`*.ppk`, `*.asc`, `*.gpg`, SSH key material incl. `id_rsa`/`id_dsa`/`id_ecdsa`/`id_ed25519`), cloud and tool
credentials (`.aws/credentials`, `.m2/settings.xml`, `.npmrc`, `.netrc`/`_netrc`, `.git-credentials`,
`.pgpass`, `.htpasswd`, `.pypirc`, `*credentials*.json`, `*secrets.*`, Docker/Kubernetes config,
`.dockercfg`, cargo/gem credentials), Terraform state (`*.tfstate*`), Vault material
(`.vault-token`, `.vault_pass`, `*vault-password*`/`*vault_password*`), Kerberos keytabs (`*.keytab`),
Apple keys (`*.p8`), yarnrc auth (`*.yarnrc*`),
lockfiles (`*.lock`, `*package-lock.json`, `*pnpm-lock.yaml`, `*npm-shrinkwrap.json`, `*bun.lockb`),
and minified assets (`*.min.js`, `*.min.css`, `*.map`). The exclude list deliberately errs on the safe
side: a legitimate file whose name matches an exclude pattern (e.g. `*secrets.*`) is kept out of
the payload — that is intentional. `.git` history and hook files
are not part of the payload, and the API key is never exposed in `ps` output.

## Development

```sh
bash -n prepare-commit-msg        # syntax check
bash prepare-commit-msg.test.sh   # full suite; stubs curl, never touches the network
```

Deps: `bash`, `git`, `jq`, `grep` (curl at runtime; plus required standard userland — `tr`/`sed`/`wc`/`tail`/`head`/`dirname`/`cat`/`mktemp`/`mv`/`chmod`/`rm`; unguarded tools degrade silently). No build, no CI, no manifest.
Repo conventions for agents: [AGENTS.md](AGENTS.md).

## License

None declared.
