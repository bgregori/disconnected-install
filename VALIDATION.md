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

It is also checked rather than remembered.
[`scripts/check-docs.py`](scripts/README.md) counts the markers and
fails if this number, the per-chapter table below, or the README
disagree. That is not belt and braces: the count was stated as 96 in
the first drafting pass and is 94, and **both** errors were in the
direction that flattered the repository. One was a chapter credited
with a draft it did not have; the other was a near-miss marker —
`NOT VALIDATED` without the closing period — that matched nothing and
was invisible to a count done by eye. Neither is detectable by a
reader, which is the whole problem.

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
front of a cluster, inside an enclave, with no way to look anything up,
needs something to verify — and "this section is deliberately blank"
sends them to a search engine on the other side of the airgap,
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

## STIG rules cited, and why only nine

Five concern authentication, in [chapter 7](docs/07-identity.md). They
were read and confirmed during the sibling work, and no revision was
recorded against them at the time — which, by this file's own rule, is
a gap:

| Rule | Requirement | Revision |
|---|---|---|
| CNTR-OS-000030 | IdP must be LDAP or OpenID; HTPasswd prohibited | **not recorded** |
| CNTR-OS-000460 | As above, different control family | **not recorded** |
| CNTR-OS-000040 | `kubeadmin` credential must be removed | **not recorded** |
| CNTR-OS-000430 | MFA — satisfied at the IdP | **not recorded** |
| CNTR-OS-000760 | `accessTokenMaxAgeSeconds` ≤ 28800 | **not recorded** |

Four concern cryptography, added 2026-10-13:

| Rule | Requirement | Severity | Revision |
|---|---|---|---|
| CNTR-OS-000340 | FIPS-validated cryptography protecting log integrity | medium | V2R6 |
| CNTR-OS-000510 | FIPS-validated 140-2/140-3 cryptography protecting session authenticity | **high** | V2R6 |
| CNTR-OS-001080 | FIPS-validated SHA-2+ for digital signatures | medium | V2R6 |
| CNTR-OS-000780 | Keystore encrypts information at rest — **etcd**, not the disk | medium | V2R6 |

Read from ComplianceAsCode's `controls/stig_ocp4.yml`, the control file
both `ocp4-stig` and `rhcos4-stig` are built from, which cites
`U_RH_OpenShift_Container_Platform_4-x_V2R6_STIG.zip` as its reference.
**That is the content's rendering of the benchmark, not the published
DISA document.** It is good enough to cite with the revision attached
and not good enough to stop anyone checking against their own.

The first three all reduce to one check,
`fips_mode_enabled_on_all_nodes`, whose only input is `fips: true` at
install. The fourth is `api_server_encryption_provider_cipher`, which
is [chapter 8](docs/08-encryption-at-rest.md) and is a day-1 operation
rather than an install-time one.

Corroboration worth recording: the same control file sets
`var_oauth_token_maxage=8h` on `ocp4-stig`, which is the 28800 seconds
CNTR-OS-000760 above requires — an independent confirmation of one of
the five unrevisioned citations.

### A negative finding, and it is load-bearing

**No control in the benchmark requires boot-disk encryption.** All 83
were checked for LUKS, boot-disk and data-at-rest rules; the only
at-rest control is CNTR-OS-000780, which is etcd. An unencrypted
cluster therefore passes `ocp4-stig`, `ocp4-stig-node` and
`rhcos4-stig` cleanly.

This is recorded here rather than left implicit because it inverts the
usual safety argument. Everywhere else in this repository, a scan is
the backstop for a mistake. For the one decision that cannot be undone
without reprovisioning every node, there is no backstop at all. See
[chapter 3](docs/03-manifests.md#it-is-not-a-stig-control-and-that-is-the-problem).

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
| [09 Compliance Operator](docs/09-compliance-operator.md) | 8 | **Partly real, and substantially corrected 2026-10-13.** The baseline-first argument is real. Taxonomy, label keys, profile set, revision location and the storage dependency are now read from the operator; the commands that use them are still drafted. |
| [10 Remediation](docs/10-remediation.md) | 7 | **Partly real, and corrected against the operator 2026-10-13** — two things Red Hat's docs state are wrong, see below. Reboot economics, review discipline and delta capture are real. Review and apply are drafted. Reboot timings are a drafted *method*, not figures. |
| [11 Manual controls](docs/11-manual-controls.md) | 9 | **Rewritten 2026-10-13 against the benchmark's control file.** The chapter now knows its own scope — 83 controls, 5 manual, ~10 needing a human. Node SSH was the wrong question entirely; the banner is four surfaces and the scan reads none of the text. Still drafted. |
| [12 Evidence pack](docs/12-evidence-pack.md) | 0 | **Real.** Structure, not procedure — nothing here needs hardware. Its one `TODO` is a question for a human, not a hardware gap, and stays a `TODO`. |
| [13 Day-2](docs/13-day2.md) | 9 | **Partly real.** The handback to prep and the drift table are real. Upgrade, scheduled scans and File Integrity are drafted. |
| [topologies/sno](docs/topologies/sno.md) | 9 | **Outage semantics real, configuration drafted.** |
| [topologies/compact](docs/topologies/compact.md) | 8 | **Outage semantics real, configuration drafted.** Rollout timings are a drafted method, not figures. |
| [troubleshooting](docs/troubleshooting.md) | 7 | **Partly real.** Failures inherited from prep are written and validated; cluster-side diagnostics are drafted. |
| [appendix STIG](docs/appendix-stig-cluster.md) | 3 | **Conceptual.** Not procedure. The rule-ID policy and the FIPS/benchmark interaction are reasoned, not measured. |

### Known problems in the drafted text

Found while drafting, not yet resolved. Each is a real question about
the existing content rather than a gap in it:

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

> One rule, learned the hard way while doing this: **source research
> does not retire a draft marker.** A block whose field paths are now
> confirmed is still a block nobody has run. Twice during this work a
> marker was dropped along with the paragraph it sat in, and both times
> `scripts/check-docs.py` caught it before it was committed. That is
> what the check is for.

#### Wave 2 — the Compliance Operator, 2026-10-13

Read from `ComplianceAsCode/compliance-operator` (`master`, cross-checked
against release tags through v1.8.2) and `ComplianceAsCode/content`.
Chapters 9 and 10 were drafted almost entirely from Red Hat's published
documentation; **two of the things that documentation says are wrong**,
and several more are true but incomplete in ways that produce a clean
scan over a real gap.

**Where Red Hat's documentation is wrong:**

- **The rendered MachineConfig name.** The docs say applied
  remediations are rendered into one MachineConfig named
  `75-$scan-name-$suite-name`. The real name is
  `75-<scan-name>-<rule-name>`, the suite name appears nowhere, and
  **there is no aggregation at all** — it is one MachineConfig per
  applied remediation. The same documentation page contradicts itself
  a few paragraphs later by listing four `75-<scan>-<rule>` objects
  from a single re-scan. Source: `GetMcName()` in
  `complianceremediation_types.go`.
- **`NeedsReview` and the paused pool.** The docs say a remediation in
  `NeedsReview` keeps the MachineConfigPool paused. The operator
  explicitly *skips* those remediations when deciding to unpause —
  there is an upstream commit titled "fix needs-review unpause pool"
  that added exactly that skip. The stuck pool was a bug; the docs
  still describe it as the design. Source:
  `compliancesuite_controller.go`, the unpause loop.

Both are cited inline in [chapter 10](docs/10-remediation.md) with the
source, because a reviewer checking against docs.redhat.com will
otherwise think the corrected text is the error.

**New "reads as a clean scan" traps, which is the class this repository
exists to collect:**

- **`NOT-APPLICABLE` results are not created at all by default.**
  `showNotApplicable` defaults to `false` and the aggregator skips
  object creation entirely for N/A checks. The label value is verbatim
  `NOT-APPLICABLE` — the hyphen worry from wave 1 was unfounded — but a
  correctly written selector still returns zero, and a pack reporting
  `NOT-APPLICABLE: 0` on a STIG scan is making a claim the cluster
  never made.
- **A `ScanSettingBinding` written with a `spec:` wrapper may not
  fail.** The CRD is structural and prunes the unknown fields; whether
  you see an error depends on your client's validation mode. If it is
  accepted, `settingsRef` defaults to `default`, a suite is created
  with **zero scans**, and the binding reports **`READY`**. Not the
  "unclear error" the chapter previously warned about — a silent no-op
  that looks successful.
- **A `roles` entry matching zero nodes completes cleanly.** It emits
  a warning event, reports `NOT-APPLICABLE`, and goes to `DONE` — the
  chapter guessed it would look stuck. Worse, the suite rolls up to
  the *lowest* result and `NOT-APPLICABLE` sits below `COMPLIANT`, so
  one empty role scan drags a fully compliant suite down to
  `NOT-APPLICABLE`.
- **`compliance.openshift.io/image-digest` is not a digest.** Despite
  the name and its own source comment, it is a random nonce used to
  garbage-collect stale parsed objects, and it changes on every
  reparse of a byte-identical image. It looks exactly like the content
  provenance an evidence pack wants. Citing it is a claim an assessor
  disproves in one command.

**Settled, where the chapter was hedging:**

- The remediation payload is `spec.current.object`; `spec.object.current`
  does not exist. **But `spec.outdated.object` is applied in preference
  when present**, which the chapter had not anticipated.
- `spec.apply` is a plain required boolean. Setting it on one
  remediation **also sets it on every sibling** whose name differs only
  by a trailing `-1`, `-2` — one multi-object fix applies as a unit, so
  a count of patches issued understates what changed.
- Creating a binding starts the scan immediately; the cron rerunner is
  not created until the first results exist.
- The benchmark revision is **`Profile.version`**, and nowhere else —
  not on the `ProfileBundle`, the scan, or a check result. A
  `TailoredProfile` has no version field at all.
- The operator version is **only** on the CSV. It is logged once at
  startup and stamped on nothing.
- `status` and `severity` really are top-level fields on a
  `ComplianceCheckResult` — the chapter's `custom-columns` expression
  is right, and "correcting" it to `.status.status` is the bug. Noted
  in the chapter so nobody fixes it later.
- All four label keys were correct.
- The empty-string check status is unreachable on a cluster; the parser
  returns before creating an object. Remove it from any arithmetic.
- Batching is **two different mechanisms**: a real operator-level
  pause/apply/unpause under auto-apply, and nothing at all under manual
  apply, where any coalescing is the MCO's and is timing-dependent.
- **An auto-apply suite unpauses pools it did not pause**, including
  one an administrator paused deliberately.
- Dependency satisfaction is **write-once**: the operator sets a
  `dependencies-met` annotation and nothing ever removes it, so a
  dependency that later regresses is never re-evaluated.
- Scan storage: `rawResultStorage.enabled` defaults true, the operator
  creates a PVC and **does not wait for it to bind**, so on a cluster
  with no default StorageClass the scan sits in `LAUNCHING` for roughly
  **90 minutes** before timing out with a message that does not mention
  storage. Directly relevant here, because the storage operator is
  itself mirrored content.
- `rotation` (default 3) ages out **raw ARF directories only**.
  `ComplianceCheckResult` objects are overwritten in place — there is
  only ever one generation, which is why chapter 9 copies them off the
  cluster.
- `suspend: true` works, but **binding against an already-suspended
  setting creates no suite and no scans**. The chapter's advice to
  suspend in order to protect a baseline only works after the baseline
  has run.

#### Wave 2, chapter 11 — the manual controls, 2026-10-13

Read from `ComplianceAsCode/content` `controls/stig_ocp4.yml` at V2R6
and OpenShift 4.21 documentation. Chapter 11 had been written without
knowing how large it was.

**The benchmark is 83 controls: 75 automated, 5 manual, 2 not
applicable, 1 partial.** But the chapter's real scope is nine or ten,
because two controls marked `automated` cannot be settled by a scan —
see below. There are no `planned`, `documentation` or `inherently met`
statuses in this file; those exist in the schema and are not used here.

**Where the chapter was wrong:**

- **Node SSH.** The chapter had a `MachineConfig` writing `/etc/issue`
  and costing a rolling reboot. **CNTR-OS-001010 (high) requires sshd
  to be *disabled* on RHCOS**, and there is no `/etc/issue`, no
  `issue.net` and no sshd-banner rule anywhere in the benchmark — the
  RHEL STIG's banner rules do not carry over to `rhcos4-stig`, which
  is the natural assumption and is wrong. The whole section was
  hardening an interface that should not be listening. It now covers
  disabling sshd, and notes the consequence for every `RUN ON: A NODE`
  block in this repository: `oc debug node/` is the access path.
- **The CLI banner.** The chapter said there was no documented way to
  put a banner in front of `oc login`. There is: a `motd` ConfigMap in
  namespace `openshift`, key `data.message`, which is what
  `openshift_motd_exists` checks. Two caveats it gained: it prints
  **after** authentication, so do not claim consent-before-access for
  that path; and **a permissions failure is silently swallowed**, so a
  correctly configured banner can be invisible to every ordinary user
  while the rule passes.
- **Three surfaces, not four.** CNTR-OS-000130 lists four rules. The
  missed one is the IdP provider-selection page, shown when more than
  one identity provider is configured.

**New "reads as a clean scan" traps:**

- **All four banner rules are existence checks.** `classification_banner`
  matches `.spec.text` against `".*"`, which an empty string satisfies.
  A cluster with four blank banners passes the banner control.
- **CNTR-OS-000090 (RBAC, high) is marked `automated` and is not.** Its
  rule ships no OVAL, no CEL, no template; the check is prose and the
  failure clause is the literal string "RBAC needs review". It produces
  a verdict that means the scanner looked at nothing.
- **Adding `audit` to a `ClusterLogForwarder`'s `inputRefs` without
  first binding `collect-audit-logs` deletes the entire collector
  DaemonSet.** Not a rejected manifest — all log collection stops,
  including the application and infrastructure logs that were working.

**Version facts that are mirror-gate items:**

- OCP 4.21 supports Logging **6.6 or 6.5**; 6.4 reached end of
  maintenance in July 2026 and 5.x will not work. `logging.openshift.io/v1`
  was removed in 6.0 — the API group is now
  `observability.openshift.io/v1`, Vector is the only collector, and
  there is no automated 5.x → 6.x upgrade. `cluster-logging` is added
  to [chapter 1's mirror gate](docs/01-intake.md#the-mirror-gate);
  `loki-operator` is **not** required when forwarding off-cluster,
  which is worth not mirroring.
- **The STIG's own fix text for audit forwarding is broken on 4.21.**
  V2R6 ships a remediation using the removed `logging.openshift.io/v1`
  group. The *rule* checks both groups; the fix an assessor reads has
  not caught up.

**Precision gained:**

- The audit profile the benchmark wants is settled, not a judgement
  call: `ocp4-stig` sets `var_openshift_audit_profile=WriteRequestBodies`.
  **But even under that profile, `Secret`, `Route` and `OAuthClient`
  are logged at metadata level only** — so "all write request bodies
  are captured" is an overstatement, and an easily checked one.
- CNTR-OS-000430 (MFA) and **CNTR-OS-000460 (high)** are both marked
  *not applicable* in the content, with a justification pushing them
  onto the identity provider — and CNTR-OS-000460 carries **27 SRG
  requirements**. The MFA attestation is therefore the
  highest-leverage paragraph in chapter 11: one conversation with the
  IdP owner discharges two controls and twenty-seven mappings.
- `oc adm policy who-can` and `oc describe clusterrolebinding.rbac` are
  documented by Red Hat and citable. **`oc auth can-i --list --as=` is
  not** — it is inherited kubectl behaviour and appears nowhere in the
  OpenShift authentication documentation. Use it to investigate; cite
  the documented ones.

**Still open, and stated rather than glossed:** the content's control
file is titled for **OpenShift 4.12** and pinned to V2R6, while this
repository targets 4.21. Whether DISA has published a later revision,
or one specific to 4.21, was not established. Also unresolved: whether
4.21 ships a default RoleBinding letting ordinary users read the `motd`
ConfigMap — which decides whether the CLI banner works at all, and is
a one-command check on a real cluster.

**A negative finding that strengthens the rule-ID policy:** mapping a
check result back to a `CNTR-OS-*` control **is not possible on any
released operator**. The annotation that would carry it is unreleased;
the older annotation that exists is silently absent because the
content's reference URL moved from `public.cyber.mil` to
`www.cyber.mil` in September 2025 and the operator's regex was never
updated. And the mapping is many-to-many regardless. So the content's
own control file, at the revision matching `Profile.version`, is the
system of record — which is exactly where this repository's nine rule
IDs came from. See
[the appendix](docs/appendix-stig-cluster.md#the-cluster-will-probably-not-tell-you-the-control-id).

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

- **`NOT-APPLICABLE` carries the hyphen, and the warning was
  backwards** (2026-10-13). The operator defines
  `CheckResultNotApplicable = "NOT-APPLICABLE"`. Chapter 9's results
  table was right; its warning — that the CRD gave an unhyphenated
  `NOTAPPLICABLE` — was wrong, and the enumeration loop that followed
  the warning used the unhyphenated form and would have counted zero
  every time, in a chapter whose whole point is that a zero reads as a
  clean scan.

  Two more values were missing from the table and are now in it: `INFO`,
  and `INCONSISTENT` — the latter meaning *the same rule returned
  different results on different nodes*, which is a drift finding that
  a PASS/FAIL count discards. There is also an **empty-string status**
  for a check that yielded no usable result, which no label selector in
  the loop can match; the chapter now says to chase the difference
  between the per-status sum and the total to zero rather than assuming
  it is rounding.

  Source: `ComplianceAsCode/compliance-operator`
  `pkg/apis/compliance/v1alpha1/compliancecheckresult_types.go`. The
  label **key** is still unconfirmed; only the values are settled.

- **There are three STIG profiles, and `ocp4-stig` excludes the node
  rules by construction** (2026-10-13). Not "some revisions ship a
  third" — `ocp4-stig` carries a `filter_rules` expression dropping
  every rule whose platform is `ocp4-node`, `ocp4-master-node`,
  `ocp4-node-on-sdn` or `ocp4-node-on-ovn`. Those rules live in
  `ocp4-stig-node`. Bind two profiles and they are never evaluated —
  not `FAIL`, not `NOT-APPLICABLE`, absent — and the scan reports
  clean on a question it did not ask.

  `ocp4-stig-node` is also not a substitute for `rhcos4-stig`: one is
  OpenShift's configuration of the node, the other the operating
  system under it.

  Related, and now acted on: the content ships **revision-pinned
  profile names** (`ocp4-stig-v2r6` beside `ocp4-stig`). The
  unversioned name is an alias that moves when content is updated,
  which is the wrong default for a result set that has to mean the
  same thing at assessment time. Chapter 9 now says to pin.

  Source: `ComplianceAsCode/content` `products/ocp4/profiles/` and
  `products/rhcos4/profiles/`, current content V2R6. Corroborating
  detail worth noting: `ocp4-stig` sets
  `var_oauth_token_maxage=8h`, which is the 28800 seconds
  CNTR-OS-000760 requires and chapter 7 already configures.

- **There is no cluster-side "declined" state. Confirmed**
  (2026-10-13). `spec.apply` is a plain boolean and
  `status.applicationState` is one of `Pending`, `NotApplied`,
  `Applied`, `Outdated`, `Error`, `MissingDependencies`,
  `NeedsReview`, defaulting to `NotApplied`. Nothing means "reviewed
  and rejected". Chapter 10 drafted this as a suspicion and built the
  exceptions register on it; the suspicion was right.

  One thing found that the chapter had not anticipated: the operator's
  `IsApplied()` helper **returns true for a remediation that is
  blocked** — `apply: true` with state `MissingDependencies` counts as
  applied, as does `apply: true` with `Outdated`. Anything derived
  from that helper, including the operator's own rendering, will
  overcount what was actually applied. Chapter 10 now counts
  `applicationState == Applied` directly and reconciles the rest.

  Source: `ComplianceAsCode/compliance-operator`
  `pkg/apis/compliance/v1alpha1/complianceremediation_types.go`.

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
