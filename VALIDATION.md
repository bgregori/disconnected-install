# Validation record

What in this repository has actually been executed against real
infrastructure, and what has not. Kept so that anyone handed this repo
can tell proven behaviour from reasoned behaviour.

The short version, stated first because it is the only thing most
readers need:

> **Nothing in this repository has been executed against a cluster.**

The chapter structure, the ordering, the decisions and the failure modes
are real and reasoned. The procedures are now drafted — written from
documentation, never run — and every one of them carries a marker saying
so. **95 drafted blocks, zero validated.**

That ratio is the state of this repository, and it is the number to
watch. It goes down one procedure at a time, and only by someone
standing in front of a cluster.

---

## Why it was empty rather than plausible

A reader with a printed copy cannot tell a verified command from an
invented one. Both are monospaced. Both look authoritative. The second
costs a day, or a reinstall, or — in
[chapter 7](docs/07-identity.md#step-7--delete-kubeadmin) — a cluster
nobody can administer.

So where a procedure has not been run, this repository writes the
section heading, states what the step must achieve and the failure mode
it prevents, and marks it:

```
> **TODO:** needs validation on real hardware -- <what specifically>
```

An empty section is a known gap. A fabricated one is a trap. The whole
repository is built on preferring the first.

---

## The third state: drafts

An empty section is honest, and it is also unusable. Someone standing in
front of a cluster with a change window open needs something to verify,
and "this section is deliberately blank" sends them to a search engine,
where they will find a command written for a connected, non-FIPS,
unhardened cluster and run it anyway.

So there is a third state between *empty* and *validated*:

```
> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not
> executed against a cluster. Verify before running. Replace this
> block with the command as run, then update VALIDATION.md.
```

The rules that keep this from becoming the fabrication the section above
rejects:

1. **A draft is marked at the point of use**, immediately above the block
   it covers — never once at the top of a chapter, never in a footnote.
   The marker has to survive being printed, photocopied and read out of
   order.
2. **A draft is never evidence.** No `DRAFT` block, and no output
   produced by running one, belongs in the evidence pack until the block
   has been replaced by the command as actually run. See
   [12-evidence-pack.md](docs/12-evidence-pack.md).
3. **Where a wrong guess is unrecoverable, the draft says so and keeps
   its gate.** Disk encryption in [03](docs/03-manifests.md), deleting
   `kubeadmin` in [07](docs/07-identity.md), the etcd migration in
   [08](docs/08-encryption-at-rest.md). These are drafted like everything
   else — a blank section sends the reader somewhere worse — but the
   draft marker carries the consequence with it, and any checklist
   already guarding the step stays in front of it. The gate is not part
   of the draft and is not provisional.
4. **A draft is replaced, not ticked.** Validating it means overwriting
   it with what was really run — which is frequently not what was
   drafted — and that difference is the most valuable thing the exercise
   produces. Record it.

Drafts are scaffolding. A chapter is finished when it has none left, and
the count going down is the real measure of this repository's progress.

---

## What *has* been validated, elsewhere

Everything this repository inherits from
[disconnected-prep](https://github.com/bgregori/disconnected-prep),
which was run end to end on 2026-10-02 against a genuinely airgapped,
FIPS-enabled, STIG-hardened RHEL 9.6 environment — a real 29 GB mirror
of OpenShift 4.21.34 plus operators, across a private subnet with no NAT
gateway, no internet gateway route and no VPC endpoints.

Carried into this repository and relied upon:

| Fact | Source |
|---|---|
| `openshift-install-fips` extracted from the local registry reports 4.21.34 with a release reference resolving to the local registry | [prep VALIDATION](https://github.com/bgregori/disconnected-prep/blob/main/VALIDATION.md) |
| A `fips: true` cluster requires both the FIPS binary **and** a host in FIPS mode | [prep 01](https://github.com/bgregori/disconnected-prep/blob/main/docs/01-prerequisites.md#fips-mode-host-versus-cluster) |
| The three install-config requirements, and that `imageDigestSources` is the one forgotten | [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#the-three-install-config-requirements) |
| oc-mirror writes **multiple** YAML documents into one IDMS file; copying the first alone breaks operator pulls | prep VALIDATION, bug 1 |
| Disk encryption is a `MachineConfig` at the manifest stage, TPM v2 or Tang, and FIPS forces `aes-cbc-essiv:sha256` | [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#disk-encryption-the-other-decision-made-at-install) |
| `oc apply -f cluster-resources/` then `disableAllDefaultSources` | [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#after-the-install-completes) |
| Applying IDMS/ITMS triggers a rolling restart of every node; on single node that is a full API outage | prep 08 |
| Mirrored operator images are **digest-referenced, not tagged** — `repo:latest` checks fail against a healthy mirror | prep VALIDATION |
| Quay's `_catalog` endpoint rejects basic auth | prep VALIDATION |
| Signature artifacts are **files**, not a `signatures/` directory | prep VALIDATION, bug 13 |
| On a hardened host, a freshly installed binary needs `restorecon` **then** `fapolicyd-cli --file add`, in that order, per host | prep 01, prep VALIDATION |
| `401` from a registry's `/v2/` is the pass, not a failure | [prep 05](https://github.com/bgregori/disconnected-prep/blob/main/docs/05-registry.md#trust-the-ca) |
| Incremental mirroring depends on `working-dir/.history/`; a delta was measured at 9.1 GB against a 29 GB initial mirror | [prep 09](https://github.com/bgregori/disconnected-prep/blob/main/docs/09-day2-delta.md) |

Every command in this repository that is not inside a `TODO` either
comes from that list, or is a generic Unix or `oc` read-only query whose
behaviour does not depend on anything unverified.

Prep's own record is equally explicit about *its* gaps, and one of them
is this repository's starting point:

> **A real cluster install from this mirror.** Out of scope for this
> repo; the handoff bundle has not been consumed by an installer. In
> particular the generated `imageDigestSources` is correct against the
> IDMS but has not been proven by booting an agent ISO.

So the very first thing this repository will validate is the last thing
prep could not.

---

## STIG rules cited, and why only five

Five rule IDs appear, all in [chapter 7](docs/07-identity.md), all
concerning authentication. They were read and confirmed during the
sibling work:

| Rule | Requirement |
|---|---|
| CNTR-OS-000030 | IdP must be LDAP or OpenID; HTPasswd prohibited |
| CNTR-OS-000460 | As above, different control family |
| CNTR-OS-000040 | `kubeadmin` credential must be removed |
| CNTR-OS-000430 | MFA — satisfied at the IdP |
| CNTR-OS-000760 | `accessTokenMaxAgeSeconds` ≤ 28800 |

No other rule ID is cited anywhere. Rule IDs are not stable across
benchmark revisions, the identifier in the published benchmark differs
from the Compliance Operator's rule object name, and a wrong citation
survives review, reaches the SSP, and is found by the assessor — at
which point every other citation is in question. See
[appendix-stig-cluster.md](docs/appendix-stig-cluster.md#why-so-few-rule-ids-appear-in-this-repository).

---

## Not verified — the honest list

Everything else. Stated by chapter so the gaps are navigable rather than
a single disclaimer. The draft count is the number of blocks in that
chapter carrying a `🚧 DRAFT` marker — each one a procedure somebody has
to stand in front of a cluster and prove.

| Chapter | Drafts | Status |
|---|---|---|
| [01 Intake](docs/01-intake.md) | 3 | **Mostly real.** Checks are generic shell or carried from prep. The mirror content gate, PTR records and the Keycloak `groups` claim are drafted. |
| [02 install-config](docs/02-install-config.md) | 4 | **Partly real.** The three disconnected requirements and the pull secret come from prep. Topology, networking, schema validation and `agent-config.yaml` are drafted. |
| [03 Manifests](docs/03-manifests.md) | 6 | **Rebuilt 2026-10-13 after the premise turned out to be wrong** — see *Resolved from documentation* below. Two staging points, not one window; disk encryption is a field, not a MachineConfig. Still drafted, now against the right installer. |
| [04 Agent ISO](docs/04-agent-iso.md) | 3 | **Drafted.** The FIPS host requirement is from prep. Generation, boot and watch are drafted. No timings are given, deliberately. |
| [05 First access](docs/05-first-access.md) | 3 | **Partly real.** Credential handling and the cluster-operator checks are real; bootstrap watch and the pull-path proof are drafted. |
| [06 Day-1 config](docs/06-day1-cluster-config.md) | 3 | **Mostly real** — it is prep's post-install step, restated. OSUS and the full pull-path proof are drafted; the OSUS draft is the weakest in the repository. |
| [07 Identity](docs/07-identity.md) | 9 | **Structure real, commands drafted.** The ordering, the gate before deleting `kubeadmin` and the five rules are the substance and are unchanged. Every resource and the deletion command are drafted. |
| [08 Encryption at rest](docs/08-encryption-at-rest.md) | 4 | **Drafted.** The distinction from disk encryption and the configured-versus-migrated trap are real. The FIPS cipher choice is deliberately left unasserted. |
| [09 Compliance Operator](docs/09-compliance-operator.md) | 7 | **Partly real.** The baseline-first argument, capture commands and result taxonomy are real. Install manifests, `ScanSettingBinding` and label selectors are drafted. |
| [10 Remediation](docs/10-remediation.md) | 8 | **Partly real.** Reboot economics, review discipline and delta capture are real. Review/apply/decline are drafted. Reboot timings are a drafted *method*, not figures. |
| [11 Manual controls](docs/11-manual-controls.md) | 9 | **Mostly real as a process.** Banner (three distinct things), audit forwarding and RBAC review are drafted. |
| [12 Evidence pack](docs/12-evidence-pack.md) | 0 | **Real.** Structure, not procedure — nothing here needs hardware. Its one `TODO` is a question for a human, not a hardware gap, and stays a `TODO`. |
| [13 Day-2](docs/13-day2.md) | 9 | **Partly real.** The handback to prep and the drift table are real. Upgrade, scheduled scans and File Integrity are drafted. |
| [topologies/sno](docs/topologies/sno.md) | 9 | **Outage semantics real, configuration drafted.** |
| [topologies/compact](docs/topologies/compact.md) | 8 | **Outage semantics real, configuration drafted.** Rollout timings are a drafted method, not figures. |
| [troubleshooting](docs/troubleshooting.md) | 8 | **Partly real.** Failures inherited from prep are written and validated; cluster-side diagnostics are drafted. |
| [appendix STIG](docs/appendix-stig-cluster.md) | 2 | **Conceptual.** Not procedure. The rule-ID policy and the FIPS/benchmark interaction are reasoned, not measured. |

### Known problems in the drafted text

Found while drafting, not yet resolved. Each is a real question about
the existing content rather than a gap in it:

- **`NOT-APPLICABLE` versus `NOTAPPLICABLE`.** Chapter 9's results
  table prints the hyphenated form; upstream CRD documentation gives
  the unhyphenated one as the allowed value. A label selector copied
  from the table would match nothing and report zero, which reads as a
  clean scan. Unresolved, and flagged in chapter 9.
- **The two-profile model may be incomplete.** Some content revisions
  ship `ocp4-stig-node` alongside `ocp4-stig` and `rhcos4-stig`.
  Omitting a third profile also produces a gap that reads as a pass.
- **There may be no cluster-side "declined" state for a remediation.**
  If so, `apply: false` is indistinguishable from "nobody looked", and
  the exceptions register is the *only* record rather than the
  recommended one.
- **Chapter 7's step order has a dependency the skeleton did not
  model.** `Group` objects only materialise after a member's first IdP
  login, so step 4 cannot read the authoritative group name until
  something like step 6 has happened. Handled inside step 4; the
  chapter-level ordering claim may still want revisiting.

### Resolved from documentation, not from hardware

Closed by reading documentation and installer source. **None of this is
validated** — the chapters affected still carry `DRAFT` markers, and the
count above does not move. What changed is that the drafts are now
derived from the right source rather than from the wrong installer.

- **Chapter 3's window did not exist, and the chapter was rebuilt**
  (2026-10-13). There is no `create manifests` / `create
  ignition-configs` pair in the agent workflow. There are two staging
  points: `openshift/`, which you create and fill before anything runs,
  and `cluster-manifests/agent-cluster-install.yaml`, which
  `agent create cluster-manifests` generates and you then edit.

  The consequence was larger than the framing. **Disk encryption on the
  agent-based installer is a `diskEncryption` field, not a
  `MachineConfig`** — so the chapter's Butane-into-`openshift/` route
  was the classic installer's and is withdrawn. Three things fell out
  of that, each of which would have cost a reinstall:

  - `enableOn` **defaults to `none`**. An absent block is a valid
    configuration meaning no encryption, generated without complaint.
  - `mode` takes a single value, `tpmv2` or `tang`. **There is no
    threshold and no way to express "TPM and Tang"** — the combination
    the chapter previously recommended for "decrypts only in this rack,
    on this network". Sites that need it have to leave this install
    method or relax the requirement.
  - `tangServers` is a **JSON string containing an array of
    `{"url","thumbprint"}`**, parsed with `json.Unmarshal`, thumbprint
    mandatory. Red Hat's published example renders it as
    `tangServers: "server1": "http://..."` — wrong shape, no thumbprint.
    Copying the documented example produces a validation failure at
    best and an unencrypted cluster at worst.

  Sources: OCP 4.21 agent-based installer documentation §4.5;
  `openshift/assisted-service` `api/hiveextension/v1beta1/agentclusterinstall_types.go`
  and `pkg/tang/tang_server.go`; `openshift/installer`
  `pkg/asset/agent/manifests/agentclusterinstall.go`. The last of these
  also shows the installer validating `enableOn` against a **shorter**
  list than the CRD allows — no `arbiters`, no comma-joined
  combinations — and validating only when the block is present.

  Still open, and still needing hardware: whether `agent create
  cluster-manifests` preserves `openshift/` across a run; whether a file
  in the wrong staging point is rejected or silently ignored; and
  **which cipher this path selects on a `fips: true` cluster**, since
  there is no Butane config to carry `openshift: fips: true` and no
  cipher field to set.

- **Chapter 2's `.bak` block** is fixed — split in two, with the reason
  the single-block version failed written out.
- **Chapter 1's mirror gate** now lists LVM Storage and ODF against the
  topology that needs each.

Beyond the chapters:

- **Any topology other than what is eventually built.** Expect the first
  validated topology to be the only validated one for a while, and the
  other topology page to stay reasoned.
- **Architectures other than `amd64`**, matching prep's limit.
- **Red Hat build of Keycloak specifically.** The IdP facts are known;
  no RHBK version has been configured against a cluster, and the
  `groups` claim behaviour has changed between Keycloak major versions.
- **Any interaction between FIPS mode and the benchmark content.** Some
  checks are satisfied by FIPS and some made irrelevant by it; which is
  which has not been established.

---

## How to update this file

When a procedure is validated:

1. Replace the `DRAFT` block — marker and all — with the command **as
   run**. Not as drafted, if the two differ.
2. Decrement the chapter's draft count in the table above, and the
   repository total at the top of this file.
3. Add a row to **What has been validated** above, naming the
   environment and the date.
4. If the draft was wrong, write down how. See below.
5. If a rule ID was confirmed, add it to the rules table **with the
   benchmark revision**.

Removing the marker without changing anything else is the one move that
defeats the whole scheme. If the drafted command turned out to be exactly
right, say so explicitly in the validation row — "drafted command
confirmed unchanged" — so that a reader can tell a verified draft from an
unreviewed one. They look identical on the page otherwise, which is the
same failure this repository was built to avoid, arriving by a different
route.

Record what failed as well as what worked. Prep's most useful section is
its list of twenty-one bugs that passed review and failed on real
hardware; this repository will have its own, and they are worth more
than the clean procedures.
