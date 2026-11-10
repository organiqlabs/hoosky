## P1 — Do First

## P2 — Quick wins

## P3 — Worth doing, plan the split

## P4 — Parking lot (don't pick)

- [ ] **Locale-dependent slice/length semantics accepted (jq tolerates U+FFFD)**
  - **File**: `pre-commit`
  - **Source**: sub-agent static scan
  - **Details**: LC_ALL=C wrapping of length/slice expansions is possible but ugly through subshells; residual risk is NOTE wording only since jq tolerates invalid UTF-8 as U+FFFD. Deferred park; revisit only if a user reports garbled diff content.
