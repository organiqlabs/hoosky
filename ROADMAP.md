## P1 — Do First

## P2 — Quick wins

## P3 — Worth doing, plan the split

## P4 — Parking lot (don't pick)

- [ ] **Locale-dependent slice/length semantics accepted (jq tolerates U+FFFD)**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: In a byte-counting locale (e.g. C), `${#var}` counts bytes and `${var:0:N}` cuts bytes, so multibyte (UTF-8) subjects/bodies can be miscounted or mis-cut by `wrap_text` and by the subject truncation — i.e. message content, not just the truncation NOTE wording as originally assessed. jq tolerates invalid UTF-8 as U+FFFD in the harness. LC_ALL=C wrapping of the length/slice expansions is possible but ugly through subshells. Deferred park; revisit only if a user reports garbled diff content.

- [ ] **Hook: FULL_DIFF captured fully in memory before 30000-char cut — streaming redesign park**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: git diff output is slurped into FULL_DIFF then truncated; a very large staged diff balloons memory first. Streaming redesign (temp file + wc/head) ~10 lines but real risk of subtle regressions in truncation NOTE semantics; parked, revisit only with a user report.

- [ ] **.gitattributes: export-ignore AGENTS/ROADMAP/tests decision; checksums.txt lacks eol=lf**
  - **File**: `.gitattributes`
  - **Source**: sub-agent static scan
  - **Details**: git archive / source zips would include non-runtime files (harmless for curl-pipe). Decide on export-ignore entries and whether checksums.txt needs eol=lf (fetched raw, not via checkout). Parked decision, not a defect.

- [ ] **Post-audit deferrals: C1 control strip, CJK display-width wrap, extended tool loop**
  - **File**: `prepare-commit-msg`
  - **Source**: this-cycle post-fix audits; explicitly deferred
  - **Details**: (1) Strip C1 UTF-8 controls (0xC2 0x80-0x9F): requires GNU-specific sed or a new dependency; threat is corner-of-corner (hostile response to an API call made with the user own key; terminal escapes only when the committer runs git log); failure already degrades to warn+exit 0. (2) wrap_text counts characters, not display columns — CJK/wide chars under-fill; documented as inherent (LC_ALL=C semantics parked with the existing locale item). (3) Extending the tool-check loop to dirname/tail/cat/mktemp: unguarded-tool failures degrade without blocking the commit (some silently); tr/sed were added because the response path needs them unconditionally. Revisit only if a user reports harm.

- [ ] **Hook: sibling chmod 0644 overrides umask — AI-drafted message world-readable until mv; decide keep/drop**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: mktemp creates the sibling 0600, then chmod 0644 forces world-readable. Git's own COMMIT_EDITMSG is normally 0644 (& umask), so 0600 diverges; drop the chmod for privacy, or keep for git-parity. Needs a maintainer decision; parked.

- [ ] _*Hook: knob-validation blocks duplicated 4-5 times across GEMINI_* knobs — dedup helper park_*
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: ~15 lines could collapse into a validate_knob helper, but touches security-audited validation with subtle 00-style semantics; benefit marginal, tests green either way. Parked unless a user-facing bug appears.
