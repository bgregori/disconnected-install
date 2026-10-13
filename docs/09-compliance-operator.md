# Compliance Operator

Installing the operator from the mirror, running the `ocp4-stig` and
`rhcos4-stig` profiles, and — the point of this chapter — **recording the
baseline before changing anything.**

---

## Why the baseline comes first

The temptation is to install the operator, scan, see failures, fix them,
and present the clean result. That produces a worse outcome than it
looks.

An accreditation conversation is about *risk*, not about a green
dashboard. The assessor's questions are: what was wrong, what did you do
about it, what is still wrong, and why is that acceptable. A single
passing scan answers none of them. The before/after pair plus the delta
answers all four, and it is the artifact that makes the remediation
chapter defensible rather than mysterious.

The operational reason is just as strong: **remediations reboot nodes**,
in waves, and when something breaks you need to know what the cluster
looked like before. Without a baseline you cannot tell a remediation you
applied from a condition that was always there.

So: scan, capture, *then* remediate. Chapter 10 is deliberately a
separate chapter so that the boundary is hard to blur.

> ⚠️ **Do not auto-apply remediations on the first scan.** The operator
> offers a scan setting that applies them automatically. It is a
> reasonable thing to use later, deliberately, and a bad thing to
> discover by accident — it will roll every node in the cluster without
> anyone having read what it is about to change. Prep flags the same risk
> at handoff.

---

## Prerequisites

The operator and its content must be in the mirror.
[Chapter 1's mirror gate](01-intake.md#the-mirror-gate) should have
confirmed it; confirm again, because this is where it bites:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get packagemanifest -A | grep -i compliance
```

Nothing listed means the operator is not installable and the answer is a
prep Day-2 delta — a transfer window, not an afternoon. See
[13-day2.md](13-day2.md).

If this is empty but you believe the content was mirrored, check first
that the `CatalogSource` from
[chapter 6](06-day1-cluster-config.md#disable-the-default-catalog-sources)
is `READY`, and that `disableAllDefaultSources` did not take your
mirrored source with it.

### You also need storage, and nothing tells you so

`rawResultStorage.enabled` defaults to **true**, so every scan creates
a `PersistentVolumeClaim` for its raw results before it runs. **The
operator does not wait for that claim to bind.** It goes straight on to
create the result-server pod, which sits `Pending` forever if nothing
can satisfy the claim.

What you see is a scan stuck in `LAUNCHING` or `RUNNING`. What is
actually wrong is that there is no default `StorageClass`. The scan
eventually times out — default `30m`, retried up to three times, so
roughly **an hour and a half before anything says "failed"**, and the
message when it comes does not mention storage.

This is a disconnected-cluster problem specifically, because the
storage operator is itself mirrored content and chapter 9 can easily
run before anybody has installed it. Check before binding anything:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get storageclass
oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'
```

The second command printing nothing means there is no default class and
every scan you start will hang. Either install the topology's storage
operator — [LVM Storage](topologies/sno.md) or
[ODF](topologies/compact.md), both of which are
[mirror-gate items](01-intake.md#the-mirror-gate) — or set
`storageClassName` explicitly on the ScanSetting.

> **You can turn it off, and mostly you should not.** Setting
> `rawResultStorage.enabled: false` skips the PVC and the result server
> entirely and the scan runs fine. What you lose is the raw ARF — the
> machine-readable report some ISSOs ask for by name, discussed under
> [two kinds of result](12-evidence-pack.md#two-kinds-of-result-and-only-one-of-them-is-durable).
> Decide that deliberately, not by discovering it after the fact.

---

## Installing

Find the catalog source name first. It is the one field a generic
walkthrough always gets wrong in a disconnected cluster — every public
example says `redhat-operators`, which no longer exists here because
[chapter 6](06-day1-cluster-config.md#disable-the-default-catalog-sources)
disabled it.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get catalogsource -n openshift-marketplace
oc get packagemanifest -A \
  -o custom-columns=NAME:.metadata.name,CATALOG:.status.catalogSource \
  | grep -i compliance
```

Whatever the second column says is what goes in `source:` below.
`oc-mirror` v2 typically names it `cs-redhat-operator-index`, but do not
type that from memory — read it off the cluster.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Uncertain: the `channel` name at the operator version prep mirrored
> (`stable` is current, older content used `release-0.1`), and whether
> the `pod-security.kubernetes.io/enforce: privileged` label on the
> namespace is still required at 4.21 — the node scanner runs privileged
> pods, so it is there for a reason, but the enforcement default may
> have moved. Check the channel with
> `oc get packagemanifest compliance-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'`
> before applying.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/day2/compliance/operator.yaml =====
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-compliance
  labels:
    openshift.io/cluster-monitoring: "true"
    pod-security.kubernetes.io/enforce: privileged
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: compliance-operator
  namespace: openshift-compliance
spec:
  targetNamespaces:
    - openshift-compliance
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: compliance-operator
  namespace: openshift-compliance
spec:
  channel: stable
  installPlanApproval: Automatic
  name: compliance-operator
  source: <the CatalogSource name you just read>
  sourceNamespace: openshift-marketplace
```

`day2/` is the directory for resources this repository authors, as
distinct from `handoff/cluster-resources/`, which is prep's and is
applied unmodified. Keep them apart: at evidence time you need to be
able to say which objects came across the airgap and which you wrote.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/day2/compliance
oc apply -f ${OCP_INSTALL_ROOT}/day2/compliance/operator.yaml
oc get installplan -n openshift-compliance
oc get csv -n openshift-compliance -w
```

**The namespace is `openshift-compliance` and the `OperatorGroup` targets
only itself — but the operator is cluster-scoped in effect.** It scans
every node, reads cluster-wide resources, and in
[chapter 10](10-remediation.md) writes `MachineConfig` objects that reboot
machines. A namespace-scoped `OperatorGroup` does not make it a
namespace-scoped blast radius, and anyone reviewing the change request
should be told so plainly.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The realistic failure here is not "the operator is absent" — chapter 1's
> gate catches that. It is a `Subscription` stuck in `InstallPlanPending`
> because the catalog advertises the operator but one of its referenced
> images, usually the **content** image carrying the benchmark, was never
> mirrored. These commands are the diagnosis; what the output actually
> looks like in that state has not been seen.

```sh
# ===== RUN ON: THE CLUSTER =====
oc describe subscription compliance-operator -n openshift-compliance
oc get installplan -n openshift-compliance -o yaml
oc get events -n openshift-compliance --sort-by=.lastTimestamp | tail -20
oc get pods -n openshift-compliance   # look for ImagePullBackOff
```

`InstallPlanPending` that never resolves, or a pod in `ImagePullBackOff`
naming an image your registry does not hold, is a **mirror** answer, not
a cluster answer: back across the airgap for a prep Day-2 delta. Do not
work around it by re-enabling a default catalog source — that is an
outbound pull attempt in an airgapped cluster's logs, and chapter 6's
whole deliverable was proving there are none.

Confirm it is running before going further:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get csv -A | grep -i compliance
oc get pods -n <compliance-namespace>
oc get profile.compliance -A
```

The last command is the real test. The operator ships its benchmark
content as `Profile` objects; if they are not listed, the content image
did not pull, and that is a mirror problem rather than an operator
problem.

---

## Content versions move independently of the cluster

Worth internalising before the scan results confuse someone.

The STIG benchmark content is shipped **with the operator**, not with
OpenShift. Three version numbers are in play — the cluster version, the
Compliance Operator version, and the benchmark revision the content
implements — and they move on different schedules. Two consequences:

- **Rule IDs and rule sets are not stable across benchmark revisions.** A
  rule that exists in your results may not exist in the revision the
  assessor is reading from. Record the revision you scanned against.
- **Updating the operator can change your results without anything
  changing in the cluster.** A previously passing rule can start
  failing because the check got stricter. This is not a regression and
  must not be presented as one, but it does need explaining, which is
  much easier if the baseline recorded the content version.

```sh
# ===== RUN ON: THE CLUSTER =====
# the operator version -- from the CSV, which is the only place it exists
oc get csv -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,VERSION:.spec.version

# the benchmark revision -- on the Profile, as a top-level .version
oc get profile.compliance -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,VERSION:.version | grep -i stig

# the content image that supplied both
oc get profilebundle -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.contentImage,STATUS:.status.dataStreamStatus
```

> 🚧 **DRAFT -- NOT VALIDATED.** The field paths and the operator
> behaviour below are read from the operator's source, not from a
> cluster — **the three commands above have still never been run.**
> Verify before running, replace this block with the commands as run,
> then update VALIDATION.md. Knowing where a field lives is not the
> same as having watched `oc` print it.

Three commands, three different facts, and all three go in the pack.

**The benchmark revision is `Profile.version`** — a top-level field,
printed as the `VERSION` column of `oc get profiles.compliance`, and it
reads `V2R6` on current content. An earlier draft said it was "carried
three ways, none of them a field called revision" and told you to
record all three. That was wrong: there is exactly one place, and this
is it. It is also the *only* place — not on the `ProfileBundle`, not on
the `ComplianceScan`, not on a check result.

> If you scan through a `TailoredProfile` rather than a `Profile`, note
> that a TailoredProfile has **no version field at all**. Resolve
> `.spec.extends` back to the `Profile` it is based on and read the
> version there, or the pack records nothing.

**The operator version is only on the CSV.** The operator does not
stamp it onto any resource it creates — it logs it once at startup and
that is all. There is no annotation on a scan or a result that will
tell you later which operator produced it, so if the CSV is not
captured at the time, that fact is gone.

> ⚠️ **Do not use `compliance.openshift.io/image-digest` as
> provenance.** The operator stamps that annotation on every parsed
> `Profile`, `Rule` and `Variable`, and despite its name — and despite
> its own source comment — **it is not a digest.** It is a randomly
> generated nonce the operator uses to garbage-collect objects left
> over from a previous parse. It changes on every reparse even when the
> content image is byte-identical, and it is not derived from the image
> in any way.
>
> It looks exactly like the thing an evidence pack wants. Citing it as
> a content digest is a claim an assessor can disprove in one command,
> which by this repository's reckoning puts every other claim in the
> pack in question.

For real content provenance, use `spec.contentImage`. Mirrored operator
images are digest-referenced, not tagged, so it should already end in
`@sha256:...`; if it ends in a tag, something resolved outside the
mirror and the result is not reproducible.

**Bind the revision-pinned profile name if the content ships one** —
`ocp4-stig-v2r6` beside `ocp4-stig`. The unversioned name is an alias
that advances when the operator is updated, which is exactly the
"results changed and nothing changed in the cluster" problem above, and
pinning costs nothing. Confirm which names your content ships; the set
is revision-specific and deprecated ones get removed.

> Profile object names are prefixed with the **`ProfileBundle` name**,
> which is why the content's `stig` profile appears as `ocp4-stig`. The
> bundle name is configurable, so do not assume the `ocp4-` prefix on a
> cluster you did not build.

📌 **Handoff** The operator version and the benchmark revision go in the
evidence pack beside every result. A scan result with no version
attached cannot be reproduced or defended.

---

## Three profiles, not two

| Profile | Scans |
|---|---|
| `ocp4-stig` | the OpenShift platform — API server configuration, RBAC, operators, cluster resources |
| `ocp4-stig-node` | OpenShift's **node-level** configuration — kubelet, the container runtime, the parts of the platform that live on a node rather than in the API |
| `rhcos4-stig` | the RHCOS operating system underneath — file permissions, kernel parameters, services |

All three are needed, and the middle row is the one that gets left out.

Earlier drafts of this chapter listed two and flagged the third as
uncertain. It is not uncertain. **`ocp4-stig` excludes every node-level
rule by construction** — the profile carries a `filter_rules` expression
that drops anything whose platform is `ocp4-node`, `ocp4-master-node`,
`ocp4-node-on-sdn` or `ocp4-node-on-ovn`. Those rules are not failing
and they are not `NOT-APPLICABLE`. They are **not evaluated**, and
nothing in the result set says so. Bind two profiles and the scan comes
back clean on a question it never asked.

`ocp4-stig-node` is not a substitute for `rhcos4-stig` either. They
cover different layers: one is OpenShift's configuration of the node,
the other is the operating system. Both run per node.

The profiles behave differently in ways that matter operationally: the
two node profiles' checks run on each node and their remediations are
`MachineConfig` objects, which means **reboots**. The platform
profile's remediations are mostly cluster resources, which mostly are
not. That distinction drives everything in
[chapter 10](10-remediation.md).

### Pin the revision, and know what you pinned

The content ships both unversioned and revision-pinned profile names —
`ocp4-stig` alongside `ocp4-stig-v2r6`, and similarly for the other
two. The unversioned name is an alias: it `extends` whichever revision
the content build considered current, and **it moves when the content
is updated**.

For an ATO that is the wrong default. A result set captured against
`ocp4-stig` records a profile name that will mean something different
in six months, which is exactly the problem
[the rule-ID policy](appendix-stig-cluster.md#why-so-few-rule-ids-appear-in-this-repository)
exists to avoid. Bind the pinned names if your content ships them, so
the benchmark revision is in the evidence rather than in someone's
memory:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get profile.compliance -n openshift-compliance
```

Read the list before writing the binding. Whichever names you use, the
revision goes in the evidence pack beside the results either way — the
pinned name just means the two cannot drift apart.

> 🚧 **DRAFT -- NOT VALIDATED.** The profile set and the `filter_rules`
> exclusion are read from the ComplianceAsCode content, not from a
> cluster. What that content builds into `Profile` objects, and whether
> your mirrored operator version ships the same three, has to come from
> the command above. The mirror gate in
> [chapter 1](01-intake.md#the-mirror-gate) assumed two profiles when
> it was written.

Before writing any binding, read the scan settings and check which of
them applies remediations. This is the step that protects the baseline:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get scansetting -n openshift-compliance
oc get scansetting default -n openshift-compliance -o yaml
oc get scansetting default-auto-apply -n openshift-compliance -o yaml
```

Two are expected on self-managed OpenShift: `default` and
`default-auto-apply`, differing in `autoApplyRemediations` and
`autoUpdateRemediations` and in nothing else. Both carry the same
schedule, `0 1 * * *` — daily at 01:00 — which matters more than it
looks and is dealt with below.

> ⚠️ **On `default`, those booleans are not `false`. They are absent.**
> The operator creates both settings in code at startup rather than
> from a manifest, and the two fields are `omitempty`, so on `default`
> they are omitted from the stored object entirely. `oc get scansetting
> default -o yaml` shows **neither key**.
>
> So "read the booleans, not the names" — which earlier drafts of this
> chapter said, and which is the right instinct — does not work as
> written here. There is no boolean on `default` to read. Absence is
> the answer, and it means `false`. What you are confirming is that
> `autoApplyRemediations` is *either* absent *or* explicitly `false`,
> and that on `default-auto-apply` it is explicitly `true`. A grep that
> returns nothing is the pass on one and the alarm on the other.

Two further properties of these objects are worth knowing before you
rely on them:

- **They are created once and never reconciled.** The operator creates
  them at startup and tolerates "already exists". If somebody edits
  `default`, the edit persists — across operator restarts and
  upgrades — and nothing restores it. `default` is not a known-good
  object you can assume the shape of; it is whatever the last person
  left. Read it on *this* cluster, every time.
- **`default-auto-apply` does not exist on every platform.** It is
  created only where auto-remediation is enabled by platform —
  self-managed OpenShift, Power, Z and HyperShift. On ROSA, EKS and
  the generic platform only `default` exists. Its absence is not
  evidence that somebody removed it.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> `settingsRef.name` is the field to get right: `default` is the
> scan-only setting and `default-auto-apply` reboots nodes, and getting
> this backwards on a first run rolls every node before anyone has read
> a remediation. The names and their semantics are confirmed above;
> what is not confirmed is this file working as written against your
> operator version.
>
> Confirm the profile names exist on your content with
> `oc get profile.compliance -n openshift-compliance` before binding —
> the revision-pinned names differ between content versions.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/day2/compliance/stig-baseline.yaml =====
apiVersion: compliance.openshift.io/v1alpha1
kind: ScanSettingBinding
metadata:
  name: stig-baseline
  namespace: openshift-compliance
profiles:
  - apiGroup: compliance.openshift.io/v1alpha1
    kind: Profile
    name: ocp4-stig
  - apiGroup: compliance.openshift.io/v1alpha1
    kind: Profile
    name: ocp4-stig-node
  - apiGroup: compliance.openshift.io/v1alpha1
    kind: Profile
    name: rhcos4-stig
settingsRef:
  apiGroup: compliance.openshift.io/v1alpha1
  kind: ScanSetting
  name: default
```

Note the shape: `profiles` and `settingsRef` are **top-level siblings
of `metadata`**, not under a `spec`. The type does have a `spec` field,
but it is an empty struct carried for a tooling reason, with no
properties in the CRD schema.

> ⚠️ **A binding written with a `spec:` wrapper may not fail. That is
> the problem.** The CRD schema is structural and does not preserve
> unknown fields, so the API server **prunes** `spec.profiles` and
> `spec.settingsRef` rather than the operator rejecting them. Whether
> you see anything depends on your client's field validation: a modern
> `oc apply` defaults to strict and will say `unknown field
> "spec.profiles"`, but `--validate=false`, an older client, or a
> GitOps controller that disables strict decoding will **accept it
> silently**.
>
> What you then have: no profiles, and `settingsRef` absent — so the
> CRD's own default fills it in as `default`. The controller builds a
> `ComplianceSuite` containing **zero scans**, creates it, and marks
> the binding **`READY`**.
>
> So the failure is not an unclear error. It is a binding that reports
> ready, a suite that exists, and nothing scanned — which in this
> repository's terms is the worst available outcome, because an empty
> result set and a clean result set are the same empty result set.
> Check `oc get compliancescan -n openshift-compliance` returns rows,
> not just that the binding says `READY`.

Two properties of the shipped `default` setting matter more here than
they would on an ordinary cluster:

- **`roles` defaults to `master` and `worker`** on self-managed
  OpenShift. A node scan is generated per role. On
  [single node](topologies/sno.md) the one machine carries both labels;
  on [three-node compact](topologies/compact.md) there are no workers
  at all.

  A role matching zero nodes **does not hang and does not fail** — an
  earlier draft of this chapter guessed it would look stuck, and that
  is wrong. The scan emits a `NoMatchingNodes` warning event, sets its
  result to `NOT-APPLICABLE`, and goes to `DONE` immediately with zero
  check results.

  That sounds harmless and is not, because of how the suite rolls up.
  The suite reports the *lowest* result across its scans, and in that
  ordering `NOT-APPLICABLE` sits **below** `COMPLIANT`. So one empty
  role scan drags an otherwise fully compliant suite down to
  `NOT-APPLICABLE` — a suite-level result that looks like a finding,
  is not one, and will be asked about. Set `roles` to the pools this
  cluster actually has and the problem disappears.
- **The schedule is `0 1 * * *`** — a nightly re-scan, on both settings,
  and a direct threat to the baseline: the check results on the cluster
  are **overwritten in place** by the next run. This is why the capture
  step below writes to a dated directory and why you copy it off the
  cluster.

  > ⚠️ **If you suspend to protect the baseline, suspend *after* the
  > first scan, never before.** `suspend: true` works, but a binding
  > created against an already-suspended setting produces **no suite
  > and no scans at all** — the controller returns early. You get a
  > binding in `SUSPENDED` and no baseline. Run the scan, capture it,
  > then suspend.

---

## Running the baseline scan

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Creating the binding starts the scan immediately — confirmed; there
> is no separate "run" verb, and the cron rerunner is not even created
> until the first results are available. **Duration is what remains
> unmeasured**, and it is the number worth writing down, because the
> node scan runs a pod per node and the first question anyone asks is
> whether it has finished or hung. Time it and replace this paragraph
> with the figure.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc apply -f ${OCP_INSTALL_ROOT}/day2/compliance/stig-baseline.yaml

oc get scansettingbinding -n openshift-compliance
oc get compliancesuite -n openshift-compliance -w
```

The suite is expected to move through `PENDING` → `LAUNCHING` →
`RUNNING` → `AGGREGATING` → `DONE`. If it sits in `LAUNCHING`, look at
the pods rather than the scan — on a disconnected cluster the usual
cause is the scanner or content image not pulling:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get pods -n openshift-compliance
oc describe pod/<a-pod-that-is-not-Running> -n openshift-compliance
```

`ImagePullBackOff` on a scanner or content image is a mirror answer, not
a cluster answer — see the install section above.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancescan -A
oc get compliancesuite -A
oc get compliancecheckresult -A | head
```

A scan reports `PHASE: DONE` and a result of `COMPLIANT` or
`NON-COMPLIANT`. **Expect `NON-COMPLIANT`**, on both profiles, on a
freshly installed cluster. That is the baseline. It is not a failure of
the install and it should not be treated as one.

---

## Capturing the baseline

This is the deliverable. Everything above is setup.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
BASELINE=${OCP_INSTALL_ROOT}/evidence/$(date +%Y-%m-%d)-baseline
mkdir -p ${BASELINE}

oc get compliancecheckresult -A -o yaml  > ${BASELINE}/checkresults.yaml
oc get complianceremediation -A -o yaml  > ${BASELINE}/remediations.yaml
oc get compliancescan -A -o yaml         > ${BASELINE}/scans.yaml
oc get csv -n openshift-compliance -o yaml   > ${BASELINE}/operator-version.yaml
oc get profile.compliance -A -o yaml     > ${BASELINE}/profiles.yaml
oc get profilebundle -A -o yaml          > ${BASELINE}/profilebundles.yaml

oc get compliancecheckresult -A \
  --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status,SEVERITY:.severity \
  | sort > ${BASELINE}/summary.txt

wc -l ${BASELINE}/summary.txt
awk '{print $2}' ${BASELINE}/summary.txt | sort | uniq -c
```

> **`STATUS:.status` and `SEVERITY:.severity` are correct. Do not
> "fix" them to `.status.status`.** `ComplianceCheckResult` is an
> unusual CRD: it has no `spec` and no `status` subresource, and
> carries `id`, `status`, `severity` and the rest as **top-level
> fields** beside `metadata`. Every instinct trained on normal
> Kubernetes objects says this is a typo. It is not, and correcting it
> produces a `summary.txt` of empty columns — which, as the acceptance
> checklist notes, diffs cleanly against another file of empty columns
> and reads as "nothing changed".
>
> `profiles.yaml` is captured alongside because it is the only thing
> that carries the benchmark revision, and `profilebundles.yaml`
> because `spec.contentImage` is the only real content provenance.
> Neither can be reconstructed after the operator is upgraded.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> `status` and `severity` are believed to be **top-level** fields on a
> `ComplianceCheckResult` — not under `.status.something`, which is what
> the name invites you to type. The paths above are written on that
> belief. A wrong path prints an empty column rather than erroring,
> which produces a `summary.txt` full of blanks that `diff`s cleanly
> against another one full of blanks, and the delta in chapter 10 then
> shows a clean run that never happened. The `-o yaml` captures above
> are unaffected and are the authoritative record either way.

Prove the columns are populated before you rely on them. This takes a
second and removes the entire failure mode:

```sh
# ===== RUN ON: THE CLUSTER =====
head -5 ${BASELINE}/summary.txt
awk 'NF < 3 {bad++} END {print bad+0 " rows missing a column"}' ${BASELINE}/summary.txt
```

Anything other than `0 rows missing a column` means the field paths are
wrong. The labels are the fallback, and are independently useful because
they are what the selectors further down match on:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A --show-labels | head -3
```

The last two lines give you the counts — total checks, and how many
`PASS` / `FAIL` / `MANUAL` / `NOT-APPLICABLE` / `ERROR`. Those numbers
are what chapter 10's delta is measured against and what chapter 12
reports.

> **Write the baseline somewhere it cannot be overwritten by the next
> scan.** The date in the directory name is doing real work. A baseline
> that was silently replaced by a post-remediation result is worse than
> no baseline, because it is wrong rather than missing.

Copy it off the cluster-adjacent host as well. The evidence pack must
survive the cluster being rebuilt.

---

## Reading the results

Seven outcomes — and one of them is usually missing from your cluster
entirely, which is the trap in this section:

| Status | Means | Who deals with it |
|---|---|---|
| `PASS` | the check passed | nobody |
| `FAIL` | the check failed | [chapter 10](10-remediation.md) |
| `MANUAL` | the scanner cannot determine this automatically | [chapter 11](11-manual-controls.md) — **these do not go away by scanning harder** |
| `NOT-APPLICABLE` | the rule did not run because it does not apply | **usually not persisted at all** — see below |
| `ERROR` | the check could not run | investigate — an `ERROR` is not a `PASS` and is easy to let slide into one |
| `INFO` | the check found something below the error threshold | read it; it is not a failure and not nothing |
| `INCONSISTENT` | **the check returned different results on different nodes** | investigate — this is a node that drifted, and it is invisible if you only count PASS and FAIL |

Severities are lowercase — `unknown`, `info`, `low`, `medium`, `high`.
There is no `critical`, and a selector written for one matches nothing.

`MANUAL` is the category that gets lost. It is not a failure, so it does
not appear on a remediation list, and it is not a pass, so the control is
unsatisfied. Chapter 11 exists because of this row.

`INCONSISTENT` is the one that matters most on a multi-node cluster and
has no equivalent on single node. It means the same rule passed on one
node and failed on another, which is a drift finding wearing a scan
result's clothes.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A -l compliance.openshift.io/check-status=MANUAL
oc get compliancecheckresult -A -l compliance.openshift.io/check-status=ERROR
```

### The N/A trap, which is not the one this chapter expected

The label value is `NOT-APPLICABLE`, hyphen included, set verbatim from
the operator's own constant. An earlier draft warned it might be an
unhyphenated `NOTAPPLICABLE` and that a selector copied from the table
would match nothing. **That warning was wrong — and the real hazard is
worse, because it survives getting the selector right.**

> ⚠️ **`NOT-APPLICABLE` results are not created at all by default.**
> The scan has a `showNotApplicable` field that defaults to `false`,
> and when it is false the aggregator *skips object creation* for every
> N/A check. They are not hidden, not filtered at display time —
> they do not exist as objects.
>
> So a correctly written selector returns zero, and zero reads as "this
> benchmark had nothing inapplicable to say about my cluster", which is
> almost never true. On a STIG scan a substantial number of rules do
> not apply, and an evidence pack reporting `NOT-APPLICABLE: 0` is
> making a claim the cluster never made.

Two honest ways out, and you have to pick one before the baseline:

- **Set `showNotApplicable: true`** on the scan settings and re-scan,
  so the objects exist and can be counted. More results to store, and
  the number an assessor sees is real.
- **Or state the suppression in the pack** — "N/A results are
  suppressed by operator default and were not enumerated" — rather
  than printing a zero that implies the opposite.

The one thing not to do is report the zero without the sentence.

There is also no empty-status result to worry about. The enum has one,
but the parser returns before creating an object, so it is unreachable
on a cluster. An earlier draft told you to hunt for these; don't.

### Reconciling the counts

> 🚧 **DRAFT -- NOT VALIDATED.** The status values, the four label keys
> and the N/A suppression above are confirmed from the operator's
> source. **The loop below has not been run against a cluster**, and
> the `check-count` reconciliation in particular is reasoning about
> what two numbers should mean, not an observation that they do.
> Verify before running, replace with the commands as run, then update
> VALIDATION.md.

A selector that matches nothing returns an empty list, which looks
exactly like "there are none". So never read a selector's output alone.
The operator gives you an independent total to check against — a
`check-count` annotation it writes on each `ComplianceScan`:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A --no-headers | wc -l

oc get compliancescan -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,\
CHECKS:.metadata.annotations.compliance\.openshift\.io/check-count

for s in PASS FAIL MANUAL INFO INCONSISTENT ERROR NOT-APPLICABLE; do
  printf '%-16s %s\n' "$s" \
    "$(oc get compliancecheckresult -A --no-headers \
         -l compliance.openshift.io/check-status=$s 2>/dev/null | wc -l)"
done
```

The per-status counts must sum to the object total. If they do not, a
value in that list is wrong and some results are invisible to you —
which is the worst outcome available here, because the ones that vanish
are not the ones that were going to pass.

The scans' `check-count` is the separate question: it is what the
operator thinks it evaluated, so a gap between that and the object
count is the N/A suppression above, and you should be able to account
for it exactly rather than approximately.

---

Next: [10-remediation.md](10-remediation.md).
