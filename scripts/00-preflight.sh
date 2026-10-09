#!/usr/bin/env bash
# docs/01-intake.md -- intake checks
# Run on: THE INSTALL HOST
#
#   ./scripts/00-preflight.sh
#
# Checks only. Changes nothing.
#
# This covers the part of chapter 1 that can be checked from the install
# host. It deliberately does NOT cover the environment checks -- DNS, VIPs,
# NTP, registry reachability -- because those must be run from the node
# network, and running them here would produce a pass that means nothing.
# See docs/01-intake.md, "The environment, checked from where it matters".

source "$(dirname "$0")/lib/common.sh"
load_env

failures=0

# Run a check in a SUBSHELL so an assertion that calls die() records a
# failure instead of exiting here. The value of this script is a complete
# picture in one run. The final tally still exits non-zero.
check() { if ( "$@" ); then :; else failures=$((failures+1)); fi; }

info "Intake preflight -- install host"

# --- OS --------------------------------------------------------------------

if [[ -r /etc/redhat-release ]]; then
  ok "OS: $(cat /etc/redhat-release)"
  grep -qE 'release 9' /etc/redhat-release \
    || warn "Not RHEL 9 -- these procedures are only tested on RHEL 9."
else
  warn "Not a Red Hat host. The FIPS/STIG workarounds assume RHEL 9."
fi

# --- FIPS ------------------------------------------------------------------
#
# Unlike prep, this is a hard failure. Prep's hosts do not need FIPS mode to
# mirror; this host runs openshift-install-fips, and Red Hat requires that
# to run from a RHEL 9 host in FIPS mode for a fips: true cluster.

check require_fips_host

# --- hardening posture -----------------------------------------------------

ok "SELinux: $(getenforce 2>/dev/null || echo unknown)"
info "umask: $(umask)"

if command -v fapolicyd >/dev/null 2>&1 && systemctl is-active --quiet fapolicyd 2>/dev/null; then
  info "fapolicyd is active. Binaries must be allowlisted before they will run."
fi

# --- tooling ---------------------------------------------------------------

if command -v oc >/dev/null 2>&1; then
  check assert_executes oc version --client
else
  warn "oc not on PATH. It is in the handoff bundle -- see docs/01-intake.md."
  failures=$((failures+1))
fi

if command -v openshift-install-fips >/dev/null 2>&1; then
  check assert_executes openshift-install-fips version
else
  warn "openshift-install-fips not on PATH. It is in the handoff bundle."
  warn "  The generic openshift-install will NOT do for a fips: true cluster."
  failures=$((failures+1))
fi

# --- install tree ----------------------------------------------------------

if [[ -n "${OCP_INSTALL_ROOT:-}" ]]; then
  if [[ -d "${OCP_INSTALL_ROOT}" ]]; then
    ok "OCP_INSTALL_ROOT exists: ${OCP_INSTALL_ROOT}"
    df -h "${OCP_INSTALL_ROOT}" >&2
  else
    warn "OCP_INSTALL_ROOT does not exist: ${OCP_INSTALL_ROOT}"
    failures=$((failures+1))
  fi
else
  warn "OCP_INSTALL_ROOT is unset. See docs/01-intake.md."
  failures=$((failures+1))
fi

# --- handoff bundle --------------------------------------------------------

HANDOFF="${OCP_INSTALL_ROOT:-}/handoff"
if [[ -d "${HANDOFF}" ]]; then
  if [[ -f "${HANDOFF}/SHA256SUMS" ]]; then
    if ( cd "${HANDOFF}" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); then
      ok "Handoff bundle checksums verify"
    else
      warn "Handoff bundle checksums DO NOT verify. Re-transfer before going further."
      failures=$((failures+1))
    fi
  else
    warn "No SHA256SUMS in ${HANDOFF}. Provenance cannot be established."
    failures=$((failures+1))
  fi

  # The six artifacts prep owes the install side.
  # https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md
  for f in install-config-fragment.yaml \
           pull-secret.json \
           certs/rootCA.pem \
           imageset-config.yaml \
           bin/openshift-install-fips \
           bin/oc; do
    if [[ -e "${HANDOFF}/${f}" ]]; then
      ok "handoff: ${f}"
    else
      warn "handoff: MISSING ${f}"
      failures=$((failures+1))
    fi
  done

  if [[ -d "${HANDOFF}/cluster-resources" ]]; then
    ok "handoff: cluster-resources/ ($(find "${HANDOFF}/cluster-resources" -type f | wc -l | tr -d ' ') files)"
  else
    warn "handoff: MISSING cluster-resources/"
    failures=$((failures+1))
  fi

  # imageDigestSources is the most commonly forgotten item in a disconnected
  # install, and prep's own generator shipped an empty block once. An IDMS
  # with no entries is worse than a missing file: it applies cleanly.
  IDMS="${HANDOFF}/cluster-resources/idms-oc-mirror.yaml"
  if [[ -f "${IDMS}" ]]; then
    n=$(grep -c '^[[:space:]]*- mirrors:' "${IDMS}" || true)
    if (( n > 0 )); then
      ok "IDMS has ${n} mirror entries -- install-config.yaml must have the same count"
    else
      warn "IDMS at ${IDMS} has NO mirror entries. Go back to prep."
      failures=$((failures+1))
    fi
  fi
else
  warn "No handoff bundle at ${HANDOFF}."
  failures=$((failures+1))
fi

# --- what this script cannot check -----------------------------------------

echo >&2
warn_wrong_host "NOT CHECKED HERE: registry reachability, DNS for api./*.apps., NTP, VIPs."
warn "  A pass from this host proves nothing about what a node sees."
warn "  docs/01-intake.md -- 'The environment, checked from where it matters'"
warn "NOT CHECKED HERE: that the mirror contains the compliance content"
warn "  chapters 9-13 install. docs/01-intake.md -- 'The mirror gate'."

echo >&2
if (( failures == 0 )); then
  ok "Install-host checks passed. The environment checks are still yours to run."
  exit 0
fi
die "${failures} check(s) failed."
