## P1 — Do First

## P2 — Quick wins

## P3 — Worth doing, plan the split

## P4 — Parking lot (don't pick)

- [ ] **Locale-dependent slice/length semantics accepted (jq tolerates U+FFFD)**
  - **File**: `prepare-commit-msg`
  - **Source**: sub-agent static scan
  - **Details**: In a byte-counting locale (e.g. C), `${#var}` counts bytes and `${var:0:N}` cuts bytes, so multibyte (UTF-8) subjects/bodies can be miscounted or mis-cut by `wrap_text` and by the subject truncation — i.e. message content, not just the truncation NOTE wording as originally assessed. jq tolerates invalid UTF-8 as U+FFFD in the harness. LC_ALL=C wrapping of the length/slice expansions is possible but ugly through subshells. Deferred park; revisit only if a user reports garbled diff content.
