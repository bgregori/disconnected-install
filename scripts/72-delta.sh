#!/usr/bin/env bash
# docs/10-remediation.md -- the baseline/after delta
#
#   ./scripts/72-delta.sh [<baseline-dir> [<after-dir>]]
#
# With no arguments it takes the most recent *-baseline and *-after
# directories under ${OCP_INSTALL_ROOT}/evidence.
#
# Reads only. Writes only delta.txt and transitions.txt into the after
# directory. Makes NO call to the cluster -- everything here is
# arithmetic on two files that chapters 9 and 10 already captured, which
# is why this one could be written before any of it has been validated
# against hardware. Run it wherever the evidence directory lives.
#
# The delta is the single most useful page in the evidence pack, and the
# way it goes wrong is not an error: it is two blank columns diffing
# cleanly against each other and reading as "nothing changed". This
# script refuses to produce a delta it cannot show you the inputs for.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
load_env

require_vars OCP_INSTALL_ROOT
EVIDENCE="${EVIDENCE_DIR:-${OCP_INSTALL_ROOT}/evidence}"

# --- locate the two result sets --------------------------------------------

BASELINE="${1:-}"
AFTER="${2:-}"

newest() {
  # Most recent directory matching a suffix. Sorted by name, because the
  # directories are date-prefixed and a name sort is the date sort --
  # mtime is not, once a directory has been copied off a host and back.
  find "${EVIDENCE}" -maxdepth 1 -type d -name "*-$1" 2>/dev/null | sort | tail -1
}

[[ -n "${BASELINE}" ]] || BASELINE="$(newest baseline)"
[[ -n "${AFTER}"    ]] || AFTER="$(newest after)"

[[ -n "${BASELINE}" ]] || die "No *-baseline directory under ${EVIDENCE}.
       The baseline is captured in docs/09-compliance-operator.md and it
       cannot be reconstructed -- a re-scan overwrites the result objects
       in place. If it was never copied off the cluster, it is gone."
[[ -n "${AFTER}" ]] || die "No *-after directory under ${EVIDENCE}.
       Capture it first -- docs/10-remediation.md, 'Capturing the after'."

info "baseline: ${BASELINE}"
info "after:    ${AFTER}"

# --- the inputs have to be real --------------------------------------------
#
# chapter 9: "A blank column diffs cleanly against another blank column
# and reads as 'nothing changed'." This is that check, and it is the
# reason this script exists rather than a one-line diff in the docs.

check_summary() {
  local file="$1" label="$2" rows statuses blank
  [[ -f "${file}" ]] || die "${label}: no summary.txt at ${file}"
  [[ -s "${file}" ]] || die "${label}: summary.txt is zero bytes. Nothing was captured."

  rows=$(wc -l < "${file}" | tr -d ' ')
  blank=$(awk 'NF < 2 || $2 == "" || $2 == "<none>"' "${file}" | wc -l | tr -d ' ')
  statuses=$(awk '{print $2}' "${file}" | sort -u | tr '\n' ' ')

  if (( blank > 0 )); then
    die "${label}: ${blank} of ${rows} rows have no status column.
       The custom-columns field path is wrong, and the delta computed from
       this file would be meaningless in a way that looks clean. Re-capture
       with the field paths confirmed -- docs/09-compliance-operator.md."
  fi

  ok "${label}: ${rows} checks, statuses: ${statuses}"
}

check_summary "${BASELINE}/summary.txt" "baseline"
check_summary "${AFTER}/summary.txt"    "after"

# --- counts ----------------------------------------------------------------

counts() { awk '{print $2}' "$1" | sort | uniq -c | sort -rn; }

echo >&2
info "baseline counts:"
counts "${BASELINE}/summary.txt" >&2
echo >&2
info "after counts:"
counts "${AFTER}/summary.txt" >&2

# --- the delta -------------------------------------------------------------

run_sh "diff '${BASELINE}/summary.txt' '${AFTER}/summary.txt' > '${AFTER}/delta.txt' || true"

# A per-check transition table, which is what "read the diff in both
# directions" actually means. A raw diff buries a PASS -> FAIL among
# sixty FAIL -> PASS lines, and PASS -> FAIL is the one nobody looks for.
run_sh "join -j1 \
  <(awk '{print \$1, \$2}' '${BASELINE}/summary.txt' | sort) \
  <(awk '{print \$1, \$2}' '${AFTER}/summary.txt' | sort) \
  | awk '\$2 != \$3 {print \$2 \" -> \" \$3 \"\t\" \$1}' \
  | sort > '${AFTER}/transitions.txt'"

# Checks present in one set and not the other. Usually the content
# version moved under you -- see docs/09-compliance-operator.md.
run_sh "comm -3 \
  <(awk '{print \$1}' '${BASELINE}/summary.txt' | sort) \
  <(awk '{print \$1}' '${AFTER}/summary.txt' | sort) \
  > '${AFTER}/appeared-or-vanished.txt'"

# --- read it back ----------------------------------------------------------

echo >&2
regressions=$(grep -c '^PASS -> FAIL' "${AFTER}/transitions.txt" || true)
improvements=$(grep -c '^FAIL -> PASS' "${AFTER}/transitions.txt" || true)
moved=$(wc -l < "${AFTER}/appeared-or-vanished.txt" | tr -d ' ')

ok    "FAIL -> PASS: ${improvements}  (what you intended)"
if (( regressions > 0 )); then
  warn "PASS -> FAIL: ${regressions}  <-- read these before anything else"
  grep '^PASS -> FAIL' "${AFTER}/transitions.txt" >&2
else
  ok  "PASS -> FAIL: 0"
fi

if (( moved > 0 )); then
  warn "${moved} check(s) appeared or vanished between the two scans."
  warn "  That usually means the content version changed under you."
  warn "  docs/09-compliance-operator.md -- content versions move independently"
fi

echo >&2
ok "Wrote delta.txt, transitions.txt, appeared-or-vanished.txt to ${AFTER}"
info "None of this is a judgement. Every remaining FAIL still has to be"
info "labelled Scheduled / Waived / Deviation by a human -- docs/10-remediation.md."
