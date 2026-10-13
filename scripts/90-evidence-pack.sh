#!/usr/bin/env bash
# docs/12-evidence-pack.md -- assemble the pack
#
#   ./scripts/90-evidence-pack.sh
#
# Creates the directory skeleton, copies in what chapters 3 through 11
# captured, checksums the result, and then tells you what is still
# missing. Makes NO call to the cluster: everything it moves is a file
# somebody already wrote. That is why it could be written before any of
# the chapters it serves has been validated.
#
# What it deliberately does NOT do:
#
#   - write README.md, cluster-description.md, exceptions-register.md or
#     deviations.md. Those are the pack's argument, they are addressed to
#     a person, and a generated one would be a template an assessor has
#     seen before.
#   - declare the pack complete. It cannot know whether a step was run
#     from a DRAFT block and never reconciled, and that is the one defect
#     in the pack nobody downstream can detect. See
#     docs/12-evidence-pack.md, "A draft is never evidence".
#
# It exits non-zero while anything required is missing. A pack that is
# not finished should not be able to report success.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "$0")/lib/common.sh"
load_env

require_vars OCP_INSTALL_ROOT
EVIDENCE="${EVIDENCE_DIR:-${OCP_INSTALL_ROOT}/evidence}"

gaps=0
note_missing() {
  warn "MISSING  $1"
  [[ -n "${2:-}" ]] && warn "         $2"
  gaps=$((gaps+1))
  return 0
}

info "Assembling the evidence pack in ${EVIDENCE}"

# --- skeleton --------------------------------------------------------------

run mkdir -p \
  "${EVIDENCE}/manual-controls" \
  "${EVIDENCE}/install" \
  "${EVIDENCE}/handoff"

# --- the build record ------------------------------------------------------
#
# These are the files that stop existing when the install host is
# cleaned up, which is why they are copied rather than referenced.

if [[ -d "${MANIFESTS_SRC:-}" ]]; then
  run cp -a "${MANIFESTS_SRC}" "${EVIDENCE}/install/manifests-src"
  ok "manifests-src/ -- what went into openshift/ before the ISO"
else
  note_missing "manifests-src/" "docs/03-manifests.md, staging point 1"
fi

# Staging point 2. Easy to lose: regenerating the ISO discards the
# edited file, so the copy kept beside the .bak files is often the only
# one left by the time anyone assembles a pack.
aci_found=0
for candidate in \
  "${OCP_INSTALL_ROOT}/cluster/cluster-manifests/agent-cluster-install.yaml" \
  "${OCP_INSTALL_ROOT}/agent-cluster-install.yaml.bak"; do
  if [[ -f "${candidate}" ]]; then
    run cp "${candidate}" "${EVIDENCE}/install/agent-cluster-install.yaml"
    ok "agent-cluster-install.yaml -- the diskEncryption block as applied"
    aci_found=1
    break
  fi
done
(( aci_found == 1 )) || note_missing "agent-cluster-install.yaml" \
  "docs/03-manifests.md, staging point 2 -- the disk encryption record"

# install-config.yaml carries the pull secret. The redaction is not
# optional and is not done here: a regex that half-redacts a credential
# is worse than one that does not run, because it produces a file
# everyone believes is safe. Chapter 12 says to redact it by hand.
if [[ -f "${EVIDENCE}/install/install-config.yaml.redacted" ]]; then
  if grep -q 'auth.*:.*[A-Za-z0-9+/]\{40,\}' "${EVIDENCE}/install/install-config.yaml.redacted"; then
    die "install-config.yaml.redacted still contains something that looks
       like a credential. Redact the pull secret before this file goes
       anywhere -- docs/12-evidence-pack.md."
  fi
  ok "install-config.yaml.redacted"
else
  note_missing "install/install-config.yaml.redacted" \
    "redact the pull secret BY HAND from ${OCP_INSTALL_ROOT}/install-config.yaml.bak"
fi

if [[ -f "${EVIDENCE}/install/node-encryption.txt" ]]; then
  ok "node-encryption.txt -- lsblk/cryptsetup per node"
else
  note_missing "install/node-encryption.txt" \
    "docs/03-manifests.md, 'Verify afterwards' -- per node, not per cluster"
fi

if compgen -G "${EVIDENCE}/install/transcript-*.log" >/dev/null; then
  ok "transcripts: $(find "${EVIDENCE}/install" -name 'transcript-*.log' | wc -l | tr -d ' ')"
else
  note_missing "install/transcript-<host>.log" \
    "one per host, READ and redacted -- it cannot be started retrospectively"
fi

# --- provenance from prep --------------------------------------------------

for f in SHA256SUMS imageset-config.yaml; do
  if [[ -f "${HANDOFF_DIR:-}/${f}" ]]; then
    run cp "${HANDOFF_DIR}/${f}" "${EVIDENCE}/handoff/${f}"
  else
    note_missing "handoff/${f}" "from prep's bundle -- provenance for the mirror"
  fi
done

# --- scan results ----------------------------------------------------------

baseline="$(find "${EVIDENCE}" -maxdepth 1 -type d -name '*-baseline' | sort | tail -1)"
after="$(find "${EVIDENCE}" -maxdepth 1 -type d -name '*-after' | sort | tail -1)"

if [[ -n "${baseline}" ]]; then
  for f in checkresults.yaml remediations.yaml scans.yaml operator-version.yaml summary.txt; do
    [[ -s "${baseline}/${f}" ]] || note_missing "$(basename "${baseline}")/${f}" \
      "docs/09-compliance-operator.md -- capturing the baseline"
  done
  ok "baseline: $(basename "${baseline}")"
else
  note_missing "<date>-baseline/" \
    "the baseline cannot be reconstructed -- a re-scan overwrites the objects in place"
fi

if [[ -n "${after}" ]]; then
  for f in checkresults.yaml remediations.yaml scans.yaml summary.txt delta.txt; do
    [[ -s "${after}/${f}" ]] || note_missing "$(basename "${after}")/${f}" \
      "docs/10-remediation.md -- delta.txt comes from scripts/72-delta.sh"
  done
  ok "after: $(basename "${after}")"
else
  note_missing "<date>-after/" "docs/10-remediation.md -- capturing the after"
fi

# --- the human-authored pages ----------------------------------------------
#
# Listed, never generated. Each one is an argument addressed to a
# person, and the pack is these files plus the evidence -- not the
# evidence with these files as a cover sheet.

for f in README.md cluster-description.md exceptions-register.md deviations.md; do
  if [[ -s "${EVIDENCE}/${f}" ]]; then
    ok "${f}"
  else
    note_missing "${f}" "written by hand -- docs/12-evidence-pack.md"
  fi
done

for f in banner.md audit-forwarding.md rbac-review.md mfa-attestation.md; do
  if [[ -s "${EVIDENCE}/manual-controls/${f}" ]]; then
    ok "manual-controls/${f}"
  else
    note_missing "manual-controls/${f}" "docs/11-manual-controls.md"
  fi
done

# --- checksums -------------------------------------------------------------
#
# So that the pack handed over is provably the pack assembled. Excludes
# itself, or it can never verify.

run_sh "cd '${EVIDENCE}' && find . -type f ! -name SHA256SUMS -print0 \
  | sort -z | xargs -0 sha256sum > SHA256SUMS"
ok "SHA256SUMS: $(wc -l < "${EVIDENCE}/SHA256SUMS" | tr -d ' ') files"

# --- what is left ----------------------------------------------------------

echo >&2
if (( gaps == 0 )); then
  ok "Every file this script knows about is present."
  warn "That is not the same as the pack being finished. This script cannot"
  warn "check the thing that matters most: whether any step was run from a"
  warn "🚧 DRAFT block and never reconciled back into the chapter."
  warn "  checklists/install-acceptance.md, section 13."
  warn "  checklists/ato-evidence.md, before you sign anything."
  exit 0
fi

die "${gaps} item(s) missing. The list above is the work remaining."
