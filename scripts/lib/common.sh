#!/usr/bin/env bash
# Shared helpers. Sourced by every script in scripts/.
#
# Adapted from disconnected-prep's scripts/lib/common.sh. Deliberately
# minimal: this library adds variable loading, logging and preflight
# assertions. It does not wrap, retry, or reinterpret any oc /
# openshift-install command. Every command these scripts run is echoed
# verbatim before execution so the terminal transcript is an accurate
# record of what happened -- which matters more here than in prep,
# because that transcript is itself an accreditation artifact. See
# docs/12-evidence-pack.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# --- output ----------------------------------------------------------------

if [[ -t 2 ]]; then
  _c_red=$'\033[31m'; _c_yellow=$'\033[33m'; _c_green=$'\033[32m'
  _c_blue=$'\033[34m'; _c_reset=$'\033[0m'
else
  _c_red=''; _c_yellow=''; _c_green=''; _c_blue=''; _c_reset=''
fi

info()  { printf '%s[INFO]%s  %s\n'  "${_c_blue}"   "${_c_reset}" "$*" >&2; }
warn()  { printf '%s[WARN]%s  %s\n'  "${_c_yellow}" "${_c_reset}" "$*" >&2; }
ok()    { printf '%s[ OK ]%s  %s\n'  "${_c_green}"  "${_c_reset}" "$*" >&2; }
die()   { printf '%s[FAIL]%s  %s\n'  "${_c_red}"    "${_c_reset}" "$*" >&2; exit 1; }

# Echo a command, then run it. The echoed line is copy-pasteable.
run() {
  printf '%s+%s %s\n' "${_c_green}" "${_c_reset}" "$*" >&2
  "$@"
}

# Same, but for commands that must run through a shell (pipes, redirects).
run_sh() {
  printf '%s+%s %s\n' "${_c_green}" "${_c_reset}" "$1" >&2
  bash -c "$1"
}

# --- configuration ---------------------------------------------------------

load_env() {
  local env_file="${REPO_ROOT}/config/install.env"
  [[ -f "${env_file}" ]] || die "Missing ${env_file}. Copy config/install.env.example and edit it."
  # Deliberately NOT `set -a`. Nothing in this file needs to be in the
  # environment of a child process -- every value is passed to tools as an
  # explicit flag -- and exporting REGISTRY_* in particular collides with
  # the docker/distribution configuration namespace, which bit prep hard
  # enough to be worth not repeating.
  # shellcheck disable=SC1090
  source "${env_file}"
  # OCP_INSTALL_ROOT resolves from the environment first (install.env uses
  # :-), so an exported value from /etc/profile.d wins over the file's
  # default. Print what it resolved to: two sources, one path, and the
  # transcript should say which one won.
  info "OCP_INSTALL_ROOT: ${OCP_INSTALL_ROOT:-<unset>}"
}

require_vars() {
  local missing=()
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || missing+=("${v}")
  done
  (( ${#missing[@]} == 0 )) || die "Unset in config/install.env: ${missing[*]}"
}

require_cmds() {
  local missing=()
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || missing+=("${c}")
  done
  (( ${#missing[@]} == 0 )) || die "Not on PATH: ${missing[*]}"
}

# --- assertions ------------------------------------------------------------

# require_space <path> <gb>
require_space() {
  local path="$1" need_gb="$2" avail_gb
  # Walk up to the nearest existing ancestor so this works before mkdir.
  while [[ ! -d "${path}" && "${path}" != "/" ]]; do path="$(dirname "${path}")"; done
  avail_gb=$(df -BG --output=avail "${path}" 2>/dev/null | tail -1 | tr -dc '0-9')
  [[ -n "${avail_gb}" ]] || { warn "Could not determine free space on ${path}"; return 0; }
  if (( avail_gb < need_gb )); then
    die "${path} has ${avail_gb} GB free, need at least ${need_gb} GB."
  fi
  ok "${path}: ${avail_gb} GB free (need ${need_gb} GB)"
}

registry_ref() { printf '%s:%s' "${REGISTRY_HOST}" "${REGISTRY_PORT}"; }

# The host that runs openshift-install-fips must itself be in FIPS mode.
# Red Hat requires the installation program to run from a RHEL 9 computer
# configured to operate in FIPS mode, and this is independent of which
# binary is used -- so neither check substitutes for the other.
# See docs/01-intake.md and prep's docs/01-prerequisites.md.
require_fips_host() {
  local enabled="unknown"
  [[ -r /proc/sys/crypto/fips_enabled ]] && enabled="$(cat /proc/sys/crypto/fips_enabled)"
  if [[ "${enabled}" == "1" ]]; then
    ok "Host FIPS mode: enabled"
    return 0
  fi
  die "Host FIPS mode is '${enabled}', must be 1.
       A fips: true cluster requires openshift-install-fips to run from a
       RHEL 9 host that is itself in FIPS mode. This is a host rebuild, not
       a setting. See docs/01-intake.md."
}

# Assert a binary actually executes. On a fapolicyd host a freshly installed
# binary can be denied, and the trust database update is not instantaneous --
# so retry briefly before giving up. Each tool needs its own version
# invocation; probing with the wrong one reports a working binary as broken.
assert_executes() {
  local bin="$1"; shift
  local -a verargs=("${@:-version}")
  local tries=5 out
  for ((i=1; i<=tries; i++)); do
    if out="$("${bin}" "${verargs[@]}" 2>&1)"; then
      if [[ -n "${out}" ]] && ! grep -qi 'operation not permitted\|permission denied' <<<"${out}"; then
        printf '%s\n' "${out}" | head -1
        return 0
      fi
    fi
    sleep 2
  done
  die "${bin} does not execute. Relabel then allowlist, in that order:
         sudo restorecon -v ${bin}
         sudo fapolicyd-cli --file add ${bin}
         sudo fapolicyd-cli --update
       The trust database is per-host. See docs/troubleshooting.md."
}

# Blocking confirmation, for genuinely destructive choices only.
# Never silently consumes EOF: under nohup/CI stdin is closed, and a bare
# `read` there yields an empty answer that looks like a deliberate refusal.
confirm() {
  local prompt="${1:-Continue?}"
  [[ "${ASSUME_YES:-false}" == "true" ]] && return 0
  if [[ ! -t 0 ]]; then
    die "Confirmation needed but stdin is not a terminal: ${prompt}
Re-run interactively, or set ASSUME_YES=true to accept this automatically."
  fi
  read -r -p "${prompt} [y/N] " reply
  [[ "${reply}" =~ ^[Yy]$ ]] || die "Aborted by user."
}

# Advisory check: long runs should be inside tmux so a dropped SSH session
# does not kill them. Advice, not a gate -- it must never block automation.
advise_tmux() {
  [[ -n "${TMUX:-}" ]] && return 0
  command -v tmux >/dev/null 2>&1 || return 0
  warn "Not inside tmux. This runs for a long time; a dropped SSH session kills it."
  warn "  systemd-run --scope --user tmux new -s ${1:-install}"
  if [[ -t 0 && "${ASSUME_YES:-false}" != "true" ]]; then
    confirm "Continue anyway?"
  else
    warn "  (non-interactive -- continuing)"
  fi
}

# Many checks in this repository are meaningless on the install host: the
# question is always what a *cluster node* sees. The install host frequently
# sits on a management VLAN with its own resolver and its own routes, and a
# name that resolves there and not on the node network is the most common
# cause of an agent install that hangs at bootstrap. Scripts that wrap such
# a check must say so rather than quietly passing.
warn_wrong_host() {
  warn "$1"
  warn "  Run it from a host on the NODE network, or a node debug shell."
}
