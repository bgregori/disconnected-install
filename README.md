# disconnected-install

Installing OpenShift from an airgapped mirror, FIPS-enabled and
STIG-hardened, and producing the evidence an ISSO will ask for.

This repository starts where
[disconnected-prep](https://github.com/bgregori/disconnected-prep) ends —
at its handoff bundle — and ends with a hardened cluster, a scan baseline,
a remediation record and an evidence pack. It does not mirror anything.
Content is prep's job, and if something is missing from the registry the
answer here is always "go back across the airgap", never "pull it".

## Scope

```
   disconnected-prep                    THE INSTALL HOST
   ┌──────────────────┐                ┌──────────────────────┐
   │ mirror content   │                │ intake the bundle    │
   │ build registry   │ ── handoff ──> │ install-config.yaml  │
   │ verify ✓         │    bundle      │ manifests + ignition │
   └──────────────────┘                │ agent ISO            │
                                       └──────────┬───────────┘
   ══════════ start of this repository ═══════════╪═══════════
                                                  ▼
                                       THE CLUSTER
                                       ┌──────────────────────┐
                                       │ day-1 config         │
                                       │ identity (external)  │
                                       │ encryption at rest   │
                                       │ scan → remediate →   │
                                       │   re-scan            │
                                       │ evidence pack        │
                                       └──────────────────────┘
```

**In scope:** `install-config.yaml`, the manifest window before ignition,
agent ISO generation and boot, day-1 cluster configuration, external
identity, encryption at rest, the Compliance Operator baseline/remediate/
re-scan loop, the controls scans mark MANUAL, and the evidence pack.

**Out of scope:** everything prep owns — mirroring, the registry, the
transfer, the installer binary. When this repo needs new content it hands
back to [prep's Day-2 delta loop](https://github.com/bgregori/disconnected-prep/blob/main/docs/09-day2-delta.md).

## Status

> ⚠️ **This repository is a first draft.** The chapter structure, the
> conventions and the decisions that have to be made are real. The
> procedures are now written, and **94 of them are marked**
> `> 🚧 **DRAFT -- NOT VALIDATED.**`.
>
> **Nothing here has been executed against a cluster.** Where a command
> appears without a draft marker, it was carried across from
> disconnected-prep, which was run end to end — see
> [VALIDATION.md](VALIDATION.md) for exactly which. **Everything else is
> a draft: written from documentation and reasoning, never run.**
>
> A draft is a starting point for validation, not an instruction. Read
> [the draft convention](#documentation-conventions) before you run any
> of it, and treat every drafted block as wrong until you have proven
> otherwise. The count above going down is this repository's progress.

## Start here

Work through the docs in order. Each chapter that offers a script also
shows what that script runs, under a **"By hand"** heading.

| | Doc | Script | Where |
|---|---|---|---|
| 1 | [Intake](docs/01-intake.md) | `00-preflight.sh` | install host |
| 2 | [install-config.yaml](docs/02-install-config.md) | — | install host |
| 3 | [Manifests before ignition](docs/03-manifests.md) | — | install host |
| 4 | [Agent ISO and boot](docs/04-agent-iso.md) | — | install host |
| 5 | [First access and bootstrap](docs/05-first-access.md) | — | install host |
| 6 | [Day-1 cluster config](docs/06-day1-cluster-config.md) | — | cluster |
| 7 | [Identity](docs/07-identity.md) | — | cluster |
| 8 | [Encryption at rest](docs/08-encryption-at-rest.md) | — | cluster |
| 9 | [Compliance Operator](docs/09-compliance-operator.md) | — | cluster |
| 10 | [Remediation](docs/10-remediation.md) | `72-delta.sh` | cluster |
| 11 | [Manual controls](docs/11-manual-controls.md) | — | cluster |
| 12 | [Evidence pack](docs/12-evidence-pack.md) | `90-evidence-pack.sh` | cluster |
| 13 | [Day-2](docs/13-day2.md) | — | both |

Topology deltas are separate, because they are the only part that differs
per cluster shape: [single node](docs/topologies/sno.md) ·
[three-node compact](docs/topologies/compact.md). The numbered chapters are
written for the general case; read the topology page alongside them rather
than instead of them.

Also: [troubleshooting](docs/troubleshooting.md) ·
[STIG on a cluster](docs/appendix-stig-cluster.md) ·
[install acceptance checklist](checklists/install-acceptance.md) ·
[ATO evidence checklist](checklists/ato-evidence.md) ·
[validation record](VALIDATION.md)

## Done looks like

`checklists/install-acceptance.md` and `checklists/ato-evidence.md` are
fully ticked. At that point you hold:

- a `fips: true` cluster installed entirely from the mirror, with no
  outbound pull attempt in any node's logs
- encrypted boot disks, and etcd encrypted at rest
- authentication against the external IdP, `kubeadmin` deleted, and at
  least one real human in a group bound to `cluster-admin`
- a Compliance Operator **baseline** scan result captured before any
  remediation, and an after result, and the delta between them
- an exceptions register: every remaining failure either remediated,
  waived with a reason, or documented as a deviation
- a dated evidence pack an ISSO can read without you in the room

## Documentation conventions

These match [disconnected-prep](https://github.com/bgregori/disconnected-prep)
exactly. If you have used that repo, nothing here will surprise you.

**The docs are self-contained. You do not need this repository to use it.**

In many environments the repo cannot be carried into the enclave, and the
person doing the work is typing commands by hand from a printed or PDF
copy. Every chapter therefore shows the real commands, with the variables
written out. Where a chapter offers a script, it also shows what that
script runs, under a **"By hand"** heading. Following the docs alone
produces exactly the same result.

**Every code block says where to run it**, on its first line:

```sh
# ===== RUN ON: THE INSTALL HOST =====
cat /proc/sys/crypto/fips_enabled
```

The marker is inside the block rather than above it so that it survives a
copy-paste into a terminal, a runbook or a change request. Running the
right command on the wrong host is the most common way these procedures go
wrong, and here it is worse than in prep: `oc` on the install host and `oc`
in a node debug shell accept many of the same commands and mean entirely
different things by them.

The labels used are:

| Label | Means |
|---|---|
| `THE INSTALL HOST` | where `openshift-install-fips` runs and the install directory lives. Must itself be in FIPS mode — see [prep 01](https://github.com/bgregori/disconnected-prep/blob/main/docs/01-prerequisites.md#fips-mode-host-versus-cluster). |
| `THE CLUSTER` | an authenticated `oc` session against the cluster API, from wherever you hold a kubeconfig |
| `A NODE` | inside a node — a debug shell or the console. Checks that must *not* run on the install host, because the install host's view of DNS, routing and disks proves nothing about a node's. |
| `THE IDP HOST` | the services host running Red Hat build of Keycloak, outside the cluster. No block uses it yet — the Keycloak-side configuration in [07](docs/07-identity.md) is unwritten — but the label is reserved so that when it is written, it cannot be mistaken for a cluster command. |
| `ANYWHERE` | the repository's own tooling, which touches no infrastructure. Used by exactly one thing, [`scripts/check-docs.py`](scripts/README.md), and deliberately not available to a procedure — if a step genuinely runs anywhere, the question of where it runs has not been thought about yet. |

Blocks that are file content rather than commands are marked `EDIT IN:`
with the path:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
fips: true
```

**Paths are written as `${OCP_INSTALL_ROOT}`, which you choose.** You
export it once, durably, in
[01-intake.md](docs/01-intake.md#where-the-install-tree-lives), and every
later block uses it. By-hand blocks that depend on it open with a guard:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
```

It is a no-op when the variable is set, and stops the block running
against your home directory when it is not — which is what an unset
`${OCP_INSTALL_ROOT}` would otherwise mean to `cd`. Here it also stops
`openshift-install ... --dir` being handed a path that is not the install
directory, which is a failure that presents several steps later as missing
manifests.

Scripts are a convenience for repeat runs, not the product. They contain no
hidden logic and echo every command before executing it, so the terminal
transcript doubles as evidence of what was run — which matters more in this
repo than in prep, because that transcript is itself an accreditation
artifact. See [12-evidence-pack.md](docs/12-evidence-pack.md).

Scripts are numbered to sort into execution order, with gaps for
insertions. Odd-numbered scripts are optional.

Markers used throughout:

> ⚠️ **STIG** — a step that exists only because of hardening, and that will
> fail confusingly on a hardened build if skipped.

> 📌 **Handoff** — a fact another team needs. The IdP owner, the network
> team, the ISSO. Collected in
> [12-evidence-pack.md](docs/12-evidence-pack.md).

> **TODO:** — a procedure that has not been validated and so has not been
> written. Treat an empty section as empty, not as "obvious".

> 🚧 **DRAFT -- NOT VALIDATED.** — a procedure written from documentation
> and reasoning, but never executed against a cluster. Verify before
> running.

That exact string is the marker, and it is the only form that counts.
When writing *about* the convention rather than marking a block — as
this section does, and as
[the install checklist](checklists/install-acceptance.md) does — use the
bare 🚧 **DRAFT** instead. A near-miss between the two is a marker that
vanishes from the count, which is why
[`scripts/check-docs.py`](scripts/README.md) rejects anything that is
neither.

The difference between the last two matters, and it is the only place
this repository knowingly departs from "empty rather than plausible".

A `TODO` is a gap nobody has attempted. A `DRAFT` is a gap somebody has
attempted on paper: it states what the step is believed to require, so
that the person at the keyboard has something to verify rather than
something to invent. It is a starting point for validation, **not an
instruction**.

Treat every `DRAFT` block as wrong until you have run it. When you do run
it, replace the block with the command as executed — not as drafted, if
the two differ — and move the chapter's row in
[VALIDATION.md](VALIDATION.md#not-verified--the-honest-list). The drafts
are scaffolding, and a chapter is not finished until its last one is gone.

The marker is deliberately loud, and deliberately inside the prose rather
than a footnote, because the failure this repository is built around is a
reader with a printed copy who cannot tell a verified command from an
invented one. A `DRAFT` block that reaches an evidence pack unchallenged
is exactly the trap [VALIDATION.md](VALIDATION.md) describes.

The count is checked rather than remembered.
[`scripts/check-docs.py`](scripts/README.md) reconciles every marker in
`docs/` against the table in `VALIDATION.md` and the headline above, and
fails if they disagree — along with checking that every runnable block
carries a host label and every cross-reference resolves. It runs on
every push. A draft count that drifts **low** makes this repository look
more validated than it is, and that is the one defect here a reader
cannot catch.

## On STIG rule IDs

Rule IDs are cited **only** where the rule has been read and the control
confirmed. Five are cited in this repository, all concerning
authentication:

| Rule | Requirement | Chapter |
|---|---|---|
| CNTR-OS-000030 | The IdP must be LDAP or OpenID. HTPasswd is prohibited. | [07](docs/07-identity.md) |
| CNTR-OS-000460 | As above — the same prohibition, stated for a different control family. | [07](docs/07-identity.md) |
| CNTR-OS-000040 | The `kubeadmin` credential must be removed. | [07](docs/07-identity.md) |
| CNTR-OS-000430 | Multifactor authentication. Satisfied at the IdP, not in the cluster. | [07](docs/07-identity.md), [11](docs/11-manual-controls.md) |
| CNTR-OS-000760 | `accessTokenMaxAgeSeconds` no greater than 28800. | [07](docs/07-identity.md) |

Everywhere else this repo describes *what the scan checks* without naming
a rule. A wrong rule ID in an evidence pack is worse than no rule ID: it
survives review, gets copied into the SSP, and is found by the assessor.
When you verify a rule against your own benchmark revision, add it — and
record the revision, because the IDs are not stable across them.

## Versions

Written against OpenShift 4.21, to match
[disconnected-prep](https://github.com/bgregori/disconnected-prep)'s
measured run. Compliance Operator content versions are tied to the
operator version mirrored, not to the cluster version, and the two move
independently — see [09-compliance-operator.md](docs/09-compliance-operator.md).
