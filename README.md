# organiqbit/scripts

One Gemini request drafts a Conventional Commits message from your staged diff and
pre-fills the commit editor. It never blocks a commit: every failure path falls
back to the normal empty message.

## Install

```sh
install -m755 pre-commit /path/to/.git/hooks/prepare-commit-msg
```

The file is named `pre-commit`, but it is neither the `pre-commit.com` framework
nor a pre-commit hook — it is a `prepare-commit-msg` hook. It is not installed
anywhere by default; it lives in this repo uninstalled on purpose. Not to be
confused with the sibling `organiqbit-hooks` TypeScript project either.

## Use

```sh
git commit                  # editor opens pre-filled with an AI draft
SKIP_AI_COMMIT=1 git commit # bypass entirely
```

Set `GEMINI_API_KEY` first. Without it, or on any failure — missing `curl`/`jq`/`git`, an unparseable API response, unsafe key characters — the hook warns on stderr and exits 0 without modifying your message, so the commit behaves exactly as if the hook weren't installed. It also stays out of the way when you pass `-m`, merge,
squash, amend, or the message file already has content.

| Variable                   | Default                 | Meaning                                             |
| -------------------------- | ----------------------- | --------------------------------------------------- |
| `GEMINI_API_KEY`           | —                       | Required. Sent to curl via stdin config, never argv |
| `GEMINI_MODEL`             | `gemini-3.5-flash-lite` | Model ID                                            |
| `GEMINI_MAX_DIFF_CHARS`    | `30000`                 | Diff is truncated at a line boundary                |
| `GEMINI_TIMEOUT`           | `20`                    | Seconds before curl gives up                        |
| `GEMINI_MAX_SUBJECT_CHARS` | `50`                    | Subject limit; cut at a word boundary               |
| `GEMINI_BODY_WRAP_CHARS`   | `75`                    | Body wrap width                                     |

Staged secret material never reaches the API: `.env*` files, private keys and
certificates, credential files (`.npmrc`, `.netrc`, `credentials*.json`, …),
lockfiles, and minified assets are excluded from the diff that is sent. The
`.git` history and hooks are not part of the payload, and the API key is never
exposed in `ps` output.

## Development

```sh
bash -n pre-commit        # syntax check
bash test-pre-commit.sh   # full suite; stubs curl, never touches the network
```

Deps: `bash`, `git`, `jq` (curl at runtime). No build, no CI, no manifest.
Repo conventions for agents: [AGENTS.md](AGENTS.md).

## License

None declared.
