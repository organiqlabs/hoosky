#!/usr/bin/env bash
# Regenerate every copy of the staged-diff deny-list from secret-excludes.registry.
# Run via `make generate-excludes`; `make test` runs `make check-generated`.
# Never hand-edit a generated block — the registry is the only source of truth.
set -eu

ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
REG="$ROOT/secret-excludes.registry"

HOOK="$ROOT/prepare-commit-msg"
TEST="$ROOT/prepare-commit-msg.test.sh"
README="$ROOT/README.md"
AGENTS="$ROOT/AGENTS.md"

B_HOOK='# BEGIN GENERATED EXCLUDES'
E_HOOK='# END GENERATED EXCLUDES'
B_SENT='# BEGIN GENERATED SENTINELS'
E_SENT='# END GENERATED SENTINELS'
B_RDM='<!-- BEGIN GENERATED DENY-LIST -->'
E_RDM='<!-- END GENERATED DENY-LIST -->'
B_AG='  <!-- BEGIN GENERATED DENY-LIST -->'
E_AG='  <!-- END GENERATED DENY-LIST -->'

FILES=( "$HOOK" "$TEST" "$README" "$AGENTS" )
BEGINS=( "$B_HOOK" "$B_SENT" "$B_RDM" "$B_AG" )
ENDS=( "$E_HOOK" "$E_SENT" "$E_RDM" "$E_AG" )

CHECK=0
case "${1:-}" in
  '') ;;
  --check) CHECK=1 ;;
  *) printf 'usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac

for f in "$REG" "${FILES[@]}"; do
  [ -f "$f" ] || { printf 'generate-excludes: missing %s\n' "$f" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Refuse to write anything if any marker is missing: a partial rewrite of a
# security contract is worse than no rewrite at all.
for i in 0 1 2 3; do
  for marker in "${BEGINS[$i]}" "${ENDS[$i]}"; do
    grep -Fqx -- "$marker" "${FILES[$i]}" || {
      printf 'generate-excludes: marker not found in %s: %s\n' "${FILES[$i]}" "$marker" >&2
      exit 1
    }
  done
done

# Parse the registry once, emitting each generated payload into $TMP.
awk -F'|' \
  -v oh="$TMP/p-hook" -v os="$TMP/p-sentinels" \
  -v rdoc="$TMP/p-readme" -v oa="$TMP/p-agents" '
function fail(msg) { printf "generate-excludes: %s\n", msg > "/dev/stderr"; exit 1 }
BEGIN { sec=""; nc=0; np=0; ns=0; q=sprintf("%c", 39) }
/^[[:space:]]*($|#)/ { next }
$0 == "[CATEGORIES]" { sec="c"; next }
$0 == "[PATTERNS]"   { sec="p"; next }
$0 == "[SENTINELS]"  { sec="s"; next }
sec == "c" {
  if (NF < 2 || $1 == "" || $2 == "") fail("bad CATEGORIES line " NR)
  if ($1 in LABEL) fail("duplicate category on line " NR)
  LABEL[$1] = $2
  next
}
sec == "p" {
  if (NF < 2 || $1 == "" || $2 == "") fail("bad PATTERNS line " NR)
  if ($1 in SEENP) fail("duplicate pattern on line " NR)
  SEENP[$1] = 1
  np++; G[np] = $1; C[np] = $2
  if (!($2 in CATSEEN)) { CATSEEN[$2] = 1; K[++nc] = $2 }
  next
}
sec == "s" {
  if (NF < 2 || $1 == "" || $2 == "") fail("bad SENTINELS line " NR)
  if ($1 in SEENS) fail("duplicate sentinel path on line " NR)
  SEENS[$1] = 1
  S[++ns] = $0
  next
}
{ fail("unexpected line " NR) }
END {
  if (nc == 0 || np == 0 || ns == 0) fail("registry sections are empty")
  for (j = 1; j <= nc; j++)
    if (!(K[j] in LABEL)) fail("no label for category " K[j])

  # The hook stays self-contained: bake the pathspecs into the EXCLUDES array.
  printf "EXCLUDES=(%s:(exclude,icase)%s%s%s\n", q, G[1], q, (np == 1 ? ")" : "") > oh
  for (i = 2; i <= np; i++)
    printf "          %s:(exclude,icase)%s%s%s\n", q, G[i], q, (i == np ? ")" : "") > oh

  # Docs: one grouped line per category, rendered from the very same globs.
  for (j = 1; j <= nc; j++) {
    line = ""
    for (i = 1; i <= np; i++)
      if (C[i] == K[j]) line = line (line == "" ? "" : ", ") "`" G[i] "`"
    printf "- %s: %s.\n", LABEL[K[j]], line > rdoc
    printf "  - %s: %s.\n", LABEL[K[j]], line > oa
  }

  # Test fixture: the representative case matrix, verbatim from the registry.
  for (i = 1; i <= ns; i++) print S[i] > os
}
' "$REG"

for f in "$TMP/p-hook" "$TMP/p-sentinels" "$TMP/p-readme" "$TMP/p-agents"; do
  [ -s "$f" ] || { printf 'generate-excludes: empty payload %s\n' "$f" >&2; exit 1; }
done

PAYLOADS=( "$TMP/p-hook" "$TMP/p-sentinels" "$TMP/p-readme" "$TMP/p-agents" )
NAMES=( hook sentinels README AGENTS )

for i in 0 1 2 3; do
  cp "${FILES[$i]}" "$TMP/copy"
  awk -v b="${BEGINS[$i]}" -v e="${ENDS[$i]}" -v s="${PAYLOADS[$i]}" '
    $0 == b { print; while ((getline line < s) > 0) print line; close(s); inside=1; next }
    inside && $0 == e { print; inside=0; next }
    inside { next }
    { print }
  ' "$TMP/copy" > "$TMP/out"
  [ -s "$TMP/out" ] || { printf 'generate-excludes: empty rewrite of %s\n' "${NAMES[$i]}" >&2; exit 1; }
  if [ "$CHECK" -eq 1 ]; then
    cmp -s "$TMP/out" "${FILES[$i]}" || {
      printf 'generate-excludes: generated block is stale in %s (run make generate-excludes)\n' \
        "${FILES[$i]}" >&2
      exit 1
    }
  else
    cat "$TMP/out" > "${FILES[$i]}"
  fi
done

if [ "$CHECK" -eq 1 ]; then
  printf 'generated deny-list blocks are current\n'
else
  printf 'regenerated deny-list in hook, tests, README and AGENTS from %s\n' "$REG"
fi
