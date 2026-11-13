## High Impact

- [ ] **Identify an installed hook by a version marker instead of the current tag's hash**
  - **File**: `install.sh`
  - **Source**: architectural-layering
  - **Details**: `HOOK_SUM` is fetched from the tag being installed (`install.sh:169` via `published_sum`, `:149`), and both the upgrade check at `:219-226` and the uninstall guard at `:207-208` compare the installed file against that one hash. The first release that changes `prepare-commit-msg` makes every previously installed copy fail: an upgrade exits 1 with "exists and is not hoosky", and `--uninstall` refuses to remove a genuine hoosky hook. The documented remedy is `--force` (`README.md:21-22`), the same switch that disables the guard against clobbering a foreign hook, so the check trains users to bypass itself.

- [ ] **Add an automated check that checksums.txt matches the worktree**
  - **File**: `checksums.txt`
  - **Source**: architectural-layering
  - **Details**: `checksums.txt:1-2` publishes hashes for the hook and the installer, but `install.sh:149` only ever reads the row for `$HOOK_NAME`, so the `install.sh` row is consumed by nothing, and no script compares either row against worktree bytes. `AGENTS.md:11-12` leaves regeneration as a hand-run `sha256sum` command. `install.test.sh:34-39` serves both artifacts from the same tree on purpose (`:6-7`), so the pair is self-consistent by construction and cannot catch drift: edit and tag without regenerating, and both suites stay green while every install of that tag dies at `install.sh:180-182`.

- [ ] **Point the dogfooding refresh at the hooksPath-resolved directory**
  - **File**: `README.md`
  - **Source**: architectural-layering
  - **Details**: `README.md:52` refreshes the live hook with `install -m755 prepare-commit-msg .git/hooks/prepare-commit-msg`, but `AGENTS.md:20-24` records that any `core.hooksPath` shadows `$GIT_DIR/hooks` entirely and prescribes `$(git rev-parse --git-path hooks)`. The installer sets a global `core.hooksPath` on its first successful run (`install.sh:130-136`), i.e. on exactly the machine of anyone who installed hoosky the documented way, so the README command writes a file git never executes and the developer keeps committing through a stale tag copy.
  - **Sub-tasks**:
    - [ ] Also correct the hook's own header at `prepare-commit-msg:2-3`, which still says `Install as .git/hooks/prepare-commit-msg.`

- [ ] **Single-source the secret exclude list across hook, docs, and test fixtures**
  - **File**: `prepare-commit-msg`
  - **Source**: architectural-layering
  - **Details**: The 46 pathspecs in `EXCLUDES` (`prepare-commit-msg:145-160`) are restated by hand in `AGENTS.md:43-57`, `README.md:91-104`, and the fixture registry at `prepare-commit-msg.test.sh:158-246`. Only the last is executable and it is enumerated manually, so adding a pattern to `EXCLUDES` without a fixture line leaves it untested and no test fails — the matrix at `:453-462` only asserts registered sentinels are absent — even though `AGENTS.md:57` claims the matrix covers them. A typo in a new secret pattern would therefore ship silently.

- [ ] **Give the hook an opt-in diagnostic mode and stop discarding git diff stderr**
  - **File**: `prepare-commit-msg`
  - **Source**: large-system-architecture
  - **Details**: `prepare-commit-msg:163-164` runs `git diff ... 2>/dev/null` then `[ -n "$FULL_DIFF" ] || exit 0`, so nothing staged, every staged path excluded by the deny-list, and a real `git diff` failure (corrupt or locked index, bad pathspec) are byte-identical and silent. A user who staged only `pnpm-lock.yaml` or `.env` is filtered for security with no signal that filtering happened. No debug or verbose knob exists (only `GEMINI_*` and `SKIP_AI_COMMIT`), and test #5 (`:300`) asserts the deny-clean case but never asserts stderr is empty, so the excluded-only path is untested.

- [ ] **Surface promptFeedback blockReason and finishReason instead of a bare no-message-generated**
  - **File**: `prepare-commit-msg`
  - **Source**: large-system-architecture
  - **Details**: `MSG` is extracted only from `.candidates[0].content.parts[]` (`prepare-commit-msg:254-255`), and the failure text at `:258-261` reads only `.error.message` or curl's stderr. A 200 response carrying `promptFeedback.blockReason` or `candidates[0].finishReason: MAX_TOKENS` therefore collapses into `warn "no message generated"` with no cause, which is the one failure class whose diagnosis is already in hand. Grepping both the hook and its suite for `blockReason|promptFeedback|finishReason|MAX_TOKENS` returns zero hits, and test #10 (`:412`) pins only the `.error.message` path.

- [ ] **Warn the committer when the staged diff was truncated**
  - **File**: `prepare-commit-msg`
  - **Source**: large-system-architecture
  - **Details**: The `NOTE` built at `prepare-commit-msg:174-177` is spliced into the prompt at `:242`, so only the model learns the diff was cut, while the hook does warn the human for the cosmetic subject overflow at `:281`. With the default 18000-character cap a large refactor gets a confident draft covering roughly a tenth of the change with no reason to suspect it. Test #13 (`:431`) checks that the NOTE lands in `prompt.json` and never checks stderr, so the missing warning is baked in rather than caught.

- [ ] **Detect repos whose hooks go dark when the installer sets global core.hooksPath**
  - **File**: `install.sh`
  - **Source**: large-system-architecture
  - **Details**: `global_post_action` (`install.sh:130-136`) sets `core.hooksPath` machine-wide and only notes it on stderr; once set, git never looks at `$GIT_DIR/hooks`, so every repo using husky, lefthook, or `pre-commit install` is silently disabled. `--uninstall` (`:211-215`, `:141-144`) removes the file but deliberately leaves the config pointing at the now-empty directory, so uninstalling leaves every other hook on the machine dead. `install.test.sh` #10 (`:139`) pins this leave-config-alone behavior as correct, so the suite locks in the hazard instead of flagging it.

- [ ] **Add SPDX identifiers and copyright notices to the four bash files**
  - **File**: `prepare-commit-msg`
  - **Source**: formatting-style
  - **Details**: All four headers are purpose comments only — `prepare-commit-msg:1-5`, `install.sh:1-6`, `prepare-commit-msg.test.sh:1-8`, `install.test.sh:1-8` — with no `SPDX-License-Identifier: MIT` and no copyright line. `install.sh:232-233` copies the hook into a hooks directory, so the primary distributed artifact travels far from `LICENSE`. `LICENSE:12-13` requires the notice in all copies or substantial portions, so every installed hook currently ships without it and no REUSE/SPDX tooling can resolve the license from the file.

- [ ] **Extract the five copy-pasted numeric-knob normalizations into one helper**
  - **File**: `prepare-commit-msg`
  - **Source**: boy-scout-rule
  - **Details**: `prepare-commit-msg:41-44`, `:51-58`, `:62-65`, `:66-69`, and `:70-73` repeat the same four statements: digit check to default, digit-length ceiling, `$((10#...))`, and `-le 0` to default. Only the default and the ceiling differ. The `10#` prefix is a real leading-zero bug fix currently replicated five times, so the next fix can land in one place and miss four; a `knob <value> <default> <max-digits>` helper reproduces every branch byte-for-byte, including the `00`-to-default case test 25 pins, while the `MAX_DIFF_CHARS` clamp at `:61` stays in place.

## Low Impact

- [ ] **Generate the usage examples from TAG and expand the hooksPath default**
  - **File**: `install.sh`
  - **Source**: architectural-layering
  - **Details**: `usage()` is a quoted heredoc (`install.sh:17`), so the four example URLs at `:34-38` hardcode `v1.0.0` and `${XDG_CONFIG_HOME:-~/.config}` prints literally at `:23`. `TAG` at `:10` is the only interpolable copy, and the same literal is repeated at `README.md:13`, `README.md:39`, and `AGENTS.md:14`. Bumping the tag leaves `--help` advertising a stale install path — an old `install.sh` fetching the old hook — from the copy-paste entry point users actually run.

- [ ] **Stop grepping the hook's stderr wording from the installer suite**
  - **File**: `install.test.sh`
  - **Source**: architectural-layering
  - **Details**: Case #14 (`install.test.sh:174-178`) runs a real `git commit` and greps for `GEMINI_API_KEY not set`, a string owned by `prepare-commit-msg:132`. Any reword of that hook warning reds the installer suite for a reason unrelated to install behavior, giving the string two owners with no shared source. The case's stated purpose — proving the global hook fires — can be asserted without pinning the wording.

- [ ] **Adopt shfmt with a committed config for the four scripts**
  - **File**: `install.sh`
  - **Source**: formatting-style
  - **Details**: Brace spacing already conflicts two lines apart: `install.sh:14` `err()  {` versus `:16` `usage() {`, repeated at `install.test.sh:15-16` and `prepare-commit-msg.test.sh:30-31`, while `prepare-commit-msg:75` uses one space. Continuation indents are 3, 8, and 10 spaces within `install.test.sh` (`:66`, `:163`, `:175`). No `.shfmt` or `.editorconfig` declares the 2-space indent in use, and lines drift freely — `prepare-commit-msg.test.sh:574` is 318 characters while the hook itself enforces a 90-column wrap.

- [ ] **Add shellcheck to the Verify contract because bash -n cannot see quoting or line endings**
  - **File**: `prepare-commit-msg.test.sh`
  - **Source**: formatting-style
  - **Details**: The only static gate anywhere is labeled `45. bash -n on the hook (the Verify contract step)` at `prepare-commit-msg.test.sh:963`, matching `AGENTS.md:94-100` and `README.md:109-110`. `bash -n` exits 0 on a CRLF-mangled file, so it cannot detect the `.gitattributes` gap, and it says nothing about `ls ... | grep -q` at `install.test.sh:134`/`:143` or the unquoted `${STUB_FAIL_HOOK:+...}` at `:51`. A quoting regression in the hook is silent by design, so nothing else would announce it.

- [ ] **Make install.test.sh executable to match its three siblings**
  - **File**: `install.test.sh`
  - **Source**: formatting-style
  - **Details**: `git ls-files -s` records `install.test.sh` as `100644` while `prepare-commit-msg`, `prepare-commit-msg.test.sh`, and `install.sh` are `100755`. `./install.test.sh` fails with permission denied while `./prepare-commit-msg.test.sh` works, and because `AGENTS.md:100` and `README.md:110` prescribe `bash install.test.sh` the mismatch stays masked and keeps getting copied.

- [ ] **Keep install.sh output ASCII or apply the hook's UTF-8 locale guard**
  - **File**: `install.sh`
  - **Source**: formatting-style
  - **Details**: `install.sh:135` prints an em dash in the headline success line (also `:262-263`), but the installer performs no locale selection, while the hook explicitly probes `C.UTF-8`/`en_US.UTF-8` at `prepare-commit-msg:11-19` before emitting multibyte text. On a C/POSIX locale, common in CI and HPC shells, the installer's success message mangles the byte, and with no `.editorconfig` charset declaration nothing prevents a non-UTF-8 re-save.

- [ ] **Provide one gate command that runs both suites and reports elapsed time**
  - **File**: `prepare-commit-msg.test.sh`
  - **Source**: large-system-architecture
  - **Details**: `README.md:108-113` and `AGENTS.md:94-102` document two separate invocations with no aggregator, no Makefile, no CI, and no runtime figure, yet `install.sh:149` serves `checksums.txt` straight from the published tag, so the installer's trust story rests on a human running a 1123-line and a 211-line suite from memory. `install.test.sh` can be red while a tag publishes fine.
  - **Sub-tasks**:
    - [ ] Replace the sleep-based kill timing in tests #52/#53 (`prepare-commit-msg.test.sh:1062-1090`: `sleep 0.4` against a stub that sleeps 2s) with a synchronization primitive so a loaded runner cannot flip the assertion

- [ ] **Check the prompt.txt heredoc write like every other payload write**
  - **File**: `prepare-commit-msg`
  - **Source**: large-system-architecture
  - **Details**: `prepare-commit-msg:222` is the only payload write with no status check, unlike `jq` at `:245`, the sibling `mktemp` at `:293`, and the write-plus-mv at `:295-296`. On a full or size-capped `TMPDIR` a truncated heredoc still yields a file that `jq --rawfile` at `:245` packages happily, so the request ships with the diff cut mid-stream and the trailing NOTE dropped, producing a plausible but wrong draft with no warning. Test #38 (`:863-900`) forces `mktemp`, `jq`, and sibling-`mktemp` failures but never this write.

- [ ] **Stop describing --dir/--all as narrower scopes when a global hooksPath makes them machine-wide**
  - **File**: `install.sh`
  - **Source**: large-system-architecture
  - **Details**: `repo_hooks_dir` (`install.sh:152-156`) resolves `git rev-parse --git-path hooks`, which honors `core.hooksPath`, so with a global hooksPath set `--all ~/src` writes the same shared file N times and prints N per-repo install lines (`:234`, `:248-252`) that read like N scoped installs. The mechanism is disclosed at `:30-31` and `README.md:24-26`, but the closing guidance at `:262-263` still recommends `--dir PATH`/`--all ROOT` for narrower scopes. `install.test.sh` #6 (`:103`) tests `--all` only with no global hooksPath, so the shared-directory case is untested.

- [ ] **Name the 4000-byte stat cap as a constant and derive the 4001 offset from it**
  - **File**: `prepare-commit-msg`
  - **Source**: boy-scout-rule
  - **Details**: `4000` appears five times in `prepare-commit-msg:190-198`, paired with an unexplained `4001` at `:191` whose meaning is only implicit. Introducing `STAT_MAX_BYTES` and `skip=$((stat_bytes-STAT_MAX_BYTES-1))` changes no output, so test 27's marker grep still matches. Drift is already visible in the suite, which hand-recomputes `47` and `4073` from the same 4000 at `prepare-commit-msg.test.sh:678-683`.

- [ ] **Rename the CUT/TRIMMED scratch variables per use site**
  - **File**: `prepare-commit-msg`
  - **Source**: boy-scout-rule
  - **Details**: `prepare-commit-msg:169-178` binds `CUT` to the diff slice and `TRIMMED` to its line-boundary trim; `:278-282` rebinds the same two names to the subject slice and its word-boundary trim. This is one top-level script, so the second binding silently reuses storage a reader is still tracking as the diff, and the two trim rules differ (`${CUT##*$'\n'}` versus `${CUT% *}`). Renaming to `DIFF_CUT`/`DIFF_TRIMMED` and `SUBJ_CUT`/`SUBJ_TRIMMED` touches no external contract.

- [ ] **Split install_one's uninstall and install modes into two functions**
  - **File**: `install.sh`
  - **Source**: boy-scout-rule
  - **Details**: `install_one` (`install.sh:186-240`) is a 55-line function with two disjoint halves at `:198-217` and `:219-239`, each returning from the same `local` frame and each re-testing `[ "$kind" = global ]` separately (`:188`, `:213`, `:235`), with `before_ts` computed at `:196` before either branch decides to use it. A thin dispatcher deriving `hd`, `dest`, and `label` once keeps the code inside the existing subshell calls at `:245`/`:251`. Every `printf`/`err` string and both return codes must be carried over verbatim because `install.test.sh` cases 7-16 assert on substrings and exit status.

- [ ] **Rename grc and REM and unify message-file wording**
  - **File**: `prepare-commit-msg`
  - **Source**: boy-scout-rule
  - **Details**: `grc` at `:127` is the grep exit status with no hint in the name, consumed at `:128-129`; `REM` at `:274` is the message minus its subject, read two lines later to strip one newline. Both read clearly as `grep_rc` and `AFTER_SUBJ`. The same object is called `message file` in the guards and warn text (`:121`, `:129`, `:130`, `:300`) but `msg file` in the comment at `:291`, which is where a reader goes to understand the atomic write.

- [ ] **Rename gh and before_ts in the installer**
  - **File**: `install.sh`
  - **Source**: boy-scout-rule
  - **Details**: `install.sh:244` binds `gh="$(global_hooks_dir)"` in a tool whose entire subject is git config, so `gh` reads as the GitHub CLI, while the adjacent function calls the same concept `hd` (`:128`, `:187`). `before_ts` at `:196` is `date +%Y%m%d%H%M%S` plus `-$$`, a unique stamp rather than a timestamp. `global_hd` and `stamp` are pure local renames, but the resulting `.bak.`/`.uninstalled.` filenames must stay byte-identical because tests 10 and 18 check them.

- [ ] **Hoist the ptext helper above the inline jq extractions it duplicates**
  - **File**: `prepare-commit-msg.test.sh`
  - **Source**: boy-scout-rule
  - **Details**: `ptext() { jq -r '.contents[0].parts[0].text' "$1" 2>/dev/null; }` is defined at `prepare-commit-msg.test.sh:770`, but the identical inline form is copy-pasted at `:344`, `:371`, `:396`, `:507`, `:517`, `:526`, `:535`, `:544`, `:904`, `:924`, and `:975`. Definition order is the only reason the earlier sites cannot use it; bash resolves at execution, so moving it next to `run_hook` around `:251` is behavior-preserving.

- [ ] **Fix the ENVKEEP-3 fixture name, which contradicts its own assertion**
  - **File**: `prepare-commit-msg.test.sh`
  - **Source**: architectural-layering
  - **Details**: Test #46 (`prepare-commit-msg.test.sh:967-980`) stages `SEN-ENVKEEP-3` in `config.env.backup.js`, then asserts at `:979` that it must NOT reach the API, because `*.env.*` (`prepare-commit-msg:146`) excludes it. The `-KEEP-` sentinel naming and the test title's `source keeps .env names` wording say the opposite, so the next person tightening the deny-list reads the fixture as a case that must survive. Rename the sentinel (for example `SEN-ENVDOT-3`) and state the `*.env.*` rule in the title.
