# Versions

Everything in this repository that is true of a particular OpenShift
release and not of OpenShift in general.

**This repository was written and measured against 4.21.** That is the
initial target, not a pin. The procedures are meant to carry forward,
and the only way they can is if the facts that move with the version
are collected somewhere a person can walk through when they move —
rather than scattered through fourteen chapters as monospaced numbers
that look permanent.

So: before using these docs against anything other than 4.21, work down
this page. It is short on purpose.

---

## How a version-coupled fact is marked

In the chapters, a fact that moves carries this:

> 🔄 **VERSION-COUPLED (4.21).** Re-check at your version — see
> [versions.md](versions.md).

It is the same idea as the
[`🚧 DRAFT` marker](../VALIDATION.md#the-third-state-drafts) and exists
for the same reason. A reader with a printed copy cannot tell a fact
that is true forever from one that was true in October 2026. Both are
monospaced. Both look authoritative. The second one quietly stops being
true and nothing anywhere reports it.

Every such marker in `docs/` has a row in the table below, and
[`scripts/check-docs.py`](../scripts/README.md) fails if one does not.

## How to use it when you move versions

1. Set `OCP_VERSION` in `config/install.env` to the z-stream you
   mirrored. `OCP_MINOR` derives from it; nothing else should need
   editing for the *commands* to be right.
2. Walk the table. For each row, confirm the value at your version and
   update the chapter if it moved.
3. Update the **Measured against** line below, and say which rows you
   re-checked rather than implying you checked all of them.

What you must not do is bump the number at the top and leave the table.
A version statement that is wider than the work done behind it is the
same defect as a `DRAFT` marker removed without running the command.

---

## Measured against

| | |
|---|---|
| OpenShift | **4.21** (prep's measured run: 4.21.34) |
| Architecture | `amd64` / `x86_64` only |
| STIG benchmark | **V2R6** |
| Date | 2026-10-13 |

---

## The facts that move

### Install

| Fact | At 4.21 | Chapter | Why it moves |
|---|---|---|---|
| Butane spec version — `variant: openshift`, `version: X.Y.0` | `4.21.0` | [03](03-manifests.md) | Tracks the OpenShift minor exactly. A mismatched spec version is rejected by `butane`, which is the good failure. |
| Ignition spec version in rendered MachineConfigs | whatever `butane` emits | [03](03-manifests.md) | Release-specific. Never hand-pick it. |
| Operator catalog index tag | `redhat-operator-index:v4.21` | [01](01-intake.md#the-mirror-gate) | Tagged by minor. The one tagged thing in an otherwise digest-referenced mirror. |
| `networkType` supported values | `OVNKubernetes` only | [02](02-install-config.md) | OpenShiftSDN was removed. Nothing has been added since, but this is the field that would change. |
| `apiVIPs` / `ingressVIPs` are lists | plural since 4.12 | [02](02-install-config.md) | A floor, not a moving target — safe at any version ≥ 4.12. |
| Agent installer `diskEncryption.enableOn` accepted values | `none`, `all`, `masters`, `workers` | [03](03-manifests.md) | The installer validates against a **narrower** set than the underlying CRD allows. Both sides can move independently. |
| Single-node `platform` value the agent installer accepts | unverified | [sno](topologies/sno.md) | Has moved between releases. |
| oc-mirror major version and output layout | v2 — IDMS/ITMS, not ICSP | [06](06-day1-cluster-config.md) | v2 replaced ICSP with IDMS/ITMS and changed the output file names. Prep owns the mirror; this repo consumes its layout. |
| oc-mirror signature artifact naming | `signature-configmap.{json,yaml}` | [06](06-day1-cluster-config.md) | A file name, which is exactly the kind of thing that changes without ceremony. |

### Compliance

| Fact | At 4.21 | Chapter | Why it moves |
|---|---|---|---|
| STIG benchmark revision | **V2R6** | [09](09-compliance-operator.md) | DISA publishes revisions on its own schedule. Rule IDs are **not** stable across them — see [the rule-ID policy](../README.md#on-stig-rule-ids). |
| What the benchmark content is titled for | **OpenShift 4.12** | [09](09-compliance-operator.md) | The content file still names 4.12 while this repo targets 4.21. Whether DISA has published anything newer is **unestablished** — the gap is real and is recorded rather than glossed. |
| Profile names | `ocp4-stig`, `ocp4-stig-node`, `rhcos4-stig`, plus `-v2r6` pinned aliases | [09](09-compliance-operator.md) | The pinned names carry the revision. The unversioned ones are aliases that advance silently, which is why chapter 9 says to pin. |
| Compliance Operator version | from the CSV; moves independently of the cluster | [09](09-compliance-operator.md) | A layered operator on its own cadence. Content versions move with it, not with OpenShift. |
| Whether the operator can map a check to a `CNTR-OS-*` ID | **no**, on every released version | [appendix](appendix-stig-cluster.md#the-cluster-will-probably-not-tell-you-the-control-id) | The parser exists upstream but is unreleased, and the released annotation is broken by a content URL change. This will become *yes* at some version. |

### Logging and audit

| Fact | At 4.21 | Chapter | Why it moves |
|---|---|---|---|
| `ClusterLogForwarder` API group | `observability.openshift.io/v1` | [11](11-manual-controls.md) | `logging.openshift.io/v1` was removed in Logging 6.0. This changed once and can change again. |
| Compatible Logging operator versions | **6.6** or **6.5** | [11](11-manual-controls.md), [01](01-intake.md#the-mirror-gate) | A support matrix with dated rows. 6.4 reached end of maintenance in July 2026. **This is a mirror-gate item** — the wrong version is a transfer window, not an afternoon. |
| Collector | Vector only | [11](11-manual-controls.md) | Fluentd and Elasticsearch were removed in Logging 6.0. |
| Audit profile the benchmark requires | `WriteRequestBodies` | [11](11-manual-controls.md) | Set by the content as `var_openshift_audit_profile`; moves with the benchmark revision, not the cluster. |
| Object types exempted from body logging | `Secret`, `Route`, `OAuthClient` | [11](11-manual-controls.md) | A documented exception list, and lists grow. |

---

## Things that are *not* version-coupled, and should not be re-checked

Worth stating, because the instinct on a version bump is to re-verify
everything and the budget for that does not exist.

- **`fips: true` is immutable and install-time** at every version. The
  three STIG controls behind it are about FIPS validation, not about a
  release.
- **Boot-disk encryption is irreversible** and is still not a STIG
  control. See
  [chapter 3](03-manifests.md#it-is-not-a-stig-control-and-that-is-the-problem).
- **The mirror registry, Tang servers and the IdP are production
  dependencies.** That is architecture, not version.
- **The ordering in [chapter 7](07-identity.md)** — a real human
  logged in and confirmed as cluster-admin before `kubeadmin` is
  deleted. That gate is about consequences, not releases.
- **Everything in [chapter 12](12-evidence-pack.md).** The evidence
  pack is structure. An ISSO's questions do not change when OpenShift
  does.

---

## When the version moves

The honest expectation, written down so nobody budgets optimistically:

A minor bump means re-reading this page and spot-checking the chapters
it points at — a day, maybe two. It does **not** mean the procedures
are validated at the new version. Every
[`🚧 DRAFT`](../VALIDATION.md) marker is still a draft, and a draft
that was written against 4.21 and is being run at 4.23 is further from
validated than it was, not closer.

If the repository ever does acquire validated procedures, the version
they were validated at is part of what "validated" means, and
[VALIDATION.md](../VALIDATION.md) should say so in every row.
