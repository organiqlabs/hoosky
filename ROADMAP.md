## P1 — Do First

## P2 — Quick wins

## P3 — Worth doing, plan the split

## P4 — Parking lot (don't pick)

- [ ] **Hook: FULL_DIFF captured fully in memory before 30000-char cut — streaming redesign park**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: git diff output is slurped into FULL_DIFF then truncated; a very large staged diff balloons memory first. Streaming redesign (temp file + wc/head) ~10 lines but real risk of subtle regressions in truncation NOTE semantics; parked, revisit only with a user report.

- [ ] **.gitattributes: export-ignore AGENTS/ROADMAP/tests decision; checksums.txt lacks eol=lf**
  - **File**: `.gitattributes`
  - **Source**: sub-agent static scan
  - **Details**: git archive / source zips would include non-runtime files (harmless for curl-pipe). Decide on export-ignore entries and whether checksums.txt needs eol=lf (fetched raw, not via checkout). Parked decision, not a defect.

- [ ] **Hook: sibling chmod 0644 overrides umask — AI-drafted message world-readable until mv; decide keep/drop**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: mktemp creates the sibling 0600, then chmod 0644 forces world-readable. Git's own COMMIT_EDITMSG is normally 0644 (& umask), so 0600 diverges; drop the chmod for privacy, or keep for git-parity. Needs a maintainer decision; parked.

- [ ] **Hook: knob-validation blocks duplicated 4-5 times across GEMINI\* knobs — dedup helper park**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: ~15 lines could collapse into a validate_knob helper, but touches security-audited validation with subtle 00-style semantics; benefit marginal, tests green either way. Parked unless a user-facing bug appears.

- [ ] **Post-audit deferrals: C1 control strip and CJK display-width wrap**
  - **File**: `prepare-commit-msg`
  - **Source**: this-cycle post-fix audits; explicitly deferred
  - **Details**: (1) Strip C1 UTF-8 controls (0xC2 0x80-0x9F): no portable sed/awk supports the byte range; would need GNU sed or a new dependency; threat is corner-of-corner (hostile response to an API call made with the user own key; terminal escapes only when the committer runs git log); failure already degrades to warn+exit 0. (2) wrap_text counts characters, not display columns — CJK/wide chars under-fill; documented as inherent. Extended tool-check loop (dirname/tail/cat) was implemented separately. Revisit only if a user reports harm.
