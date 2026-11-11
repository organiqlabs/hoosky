## P1 — Do First

## P2 — Quick wins

## P3 — Worth doing, plan the split

## P4 — Parking lot (don't pick)

- [ ] **Locale-dependent slice/length semantics accepted (jq tolerates U+FFFD)**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: In a byte-counting locale (e.g. C), `${#var}` counts bytes and `${var:0:N}` cuts bytes, so multibyte (UTF-8) subjects/bodies can be miscounted or mis-cut by `wrap_text` and by the subject truncation — i.e. message content, not just the truncation NOTE wording as originally assessed. jq tolerates invalid UTF-8 as U+FFFD in the harness. LC_ALL=C wrapping of the length/slice expansions is possible but ugly through subshells. Deferred park; revisit only if a user reports garbled diff content.

- [ ] **Post-audit deferrals: C1 control strip, CJK display-width wrap, extended tool loop**
  - **File**: `prepare-commit-msg`
  - **Source**: this-cycle post-fix audits; explicitly deferred
  - **Details**: (1) Strip C1 UTF-8 controls (0xC2 0x80-0x9F): requires GNU-specific sed or a new dependency; threat is corner-of-corner (hostile response to an API call made with the user own key; terminal escapes only when the committer runs git log); failure already degrades to warn+exit 0. (2) wrap_text counts characters, not display columns — CJK/wide chars under-fill; documented as inherent (LC_ALL=C semantics parked with the existing locale item). (3) Extending the tool-check loop to dirname/tail/cat/mktemp: unguarded-tool failures degrade without blocking the commit (some silently); tr/sed were added because the response path needs them unconditionally. Revisit only if a user reports harm.
