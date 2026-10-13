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
oc get csv -n <compliance-namespace> -o custom-columns=NAME:.metadata.name,VERSION:.spec.version
oc get profile.compliance -A -o yaml | grep -iE 'name:|version'
```

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The operator version is on the CSV and is easy; the `grep` above is a
> way of staring at the content, not a procedure. The **benchmark
> revision** — the number an assessor cares about — is believed to be
> carried three ways, none of them a field called "revision", and which
> of the three to quote has not been confirmed. Check all three and
> record all three; they are cheap and an assessor will accept a digest
> where they will not accept a guess.

```sh
# ===== RUN ON: THE CLUSTER =====
# 1. the content image, by digest -- the authoritative identity
oc get profilebundle -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.contentImage,STATUS:.status.dataStreamStatus

# 2. the revision-pinned profile names the content ships alongside the
#    unversioned aliases
oc get profile.compliance -n openshift-compliance | grep -i stig

# 3. the digest annotation the operator stamps on every parsed object
oc get profile.compliance ocp4-stig -n openshift-compliance -o yaml
```

The first is the one to trust. Mirrored operator images are
digest-referenced, not tagged, so `spec.contentImage` should already end
in `@sha256:...`; if it ends in a tag, something resolved outside the
mirror and the result is not reproducible.

The second is the most readable. The content tends to ship both
`ocp4-stig` and a revision-pinned name such as `ocp4-stig-v2r1`, where
the unversioned name is an alias for the newest revision in that content
image. **If both exist, bind the pinned one.** An alias that silently
advances when the operator is updated is exactly the "results changed
and nothing changed in the cluster" problem described above, and pinning
costs nothing. Confirm which names your content actually ships — the set
is revision-specific and the deprecated ones get removed.

📌 **Handoff** The operator version and the benchmark revision go in the
evidence pack beside every result. A scan result with no version
attached cannot be reproduced or defended.

---

## The two profiles

| Profile | Scans |
|---|---|
| `ocp4-stig` | the OpenShift platform — API server configuration, RBAC, operators, cluster resources |
| `rhcos4-stig` | the RHCOS nodes themselves — file permissions, kernel parameters, services, the operating system underneath |

Both are needed. They check different things and a clean `ocp4-stig` says
nothing about the nodes.

They also behave differently in ways that matter operationally: the node
profile's checks run on each node and its remediations are
`MachineConfig` objects, which means **reboots**. The platform profile's
remediations are mostly cluster resources, which mostly are not. That
distinction drives everything in [chapter 10](10-remediation.md).

Before writing any binding, read the scan settings the operator shipped
and check which of them applies remediations. This is the step that
protects the baseline:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get scansetting -n openshift-compliance
oc get scansetting default -n openshift-compliance -o yaml
```

Two are expected: `default` and `default-auto-apply`, differing only in
`autoApplyRemediations` and `autoUpdateRemediations`. **Read the
booleans, not the names.** A name is a convention; the boolean is the
thing that reboots your cluster. If `default` comes back with
`autoApplyRemediations: true` on your content, stop and work out why
before binding anything to it.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Three things to check before applying this. **(a)** The profile names:
> substitute the revision-pinned names if your content ships them, and
> confirm from `oc get profile.compliance` whether the content also
> ships a separate `ocp4-stig-node` profile — some revisions split the
> platform product's node checks out, and omitting it leaves a gap that
> looks like a clean scan. **(b)** `settingsRef.name` — `default` is
> believed to be the scan-only one, and getting this backwards on a
> first run rolls every node before anyone has read a remediation.
> **(c)** `roles`, discussed below.

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
    name: rhcos4-stig
settingsRef:
  apiGroup: compliance.openshift.io/v1alpha1
  kind: ScanSetting
  name: default
```

Note the shape: `profiles` and `settingsRef` are **top-level**, not under
a `spec`. A binding written with a `spec:` wrapper is rejected, and the
error does not say so clearly.

Two properties of the shipped `default` setting matter more here than
they would on an ordinary cluster:

- **`roles` lists `worker` and `master`.** A node scan is generated per
  role. On [single node](topologies/sno.md) the one machine carries both
  labels, and on [three-node compact](topologies/compact.md) there are no
  workers at all — a role matching zero nodes is the kind of thing that
  leaves a scan looking stuck rather than failing. Set `roles` to match
  the pools this cluster actually has.
- **`default` carries a cron schedule** — a nightly re-scan. That is
  reasonable steady-state behaviour and a direct threat to the baseline:
  the scan results on the cluster are **overwritten** by the next run,
  and `rawResultStorage.rotation` ages the raw results out after a few.
  This is why the capture step below writes to a dated directory and why
  you copy it off the cluster. Consider setting `suspend: true` on a
  copy of the setting until the baseline is captured and archived.

---

## Running the baseline scan

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Creating the binding is believed to start the scan immediately — there
> is no separate "run" verb. **Duration is unmeasured**, and it is the
> number worth writing down, because the node scan runs a pod per node
> and the first question anyone asks is whether it has finished or hung.
> Time it and replace this paragraph with the figure.

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
oc get csv -n <compliance-namespace> -o yaml > ${BASELINE}/operator-version.yaml

oc get compliancecheckresult -A \
  --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status,SEVERITY:.severity \
  | sort > ${BASELINE}/summary.txt

wc -l ${BASELINE}/summary.txt
awk '{print $2}' ${BASELINE}/summary.txt | sort | uniq -c
```

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

Four outcomes, and three of them need a human:

| Status | Means | Who deals with it |
|---|---|---|
| `PASS` | the check passed | nobody |
| `FAIL` | the check failed | [chapter 10](10-remediation.md) |
| `MANUAL` | the scanner cannot determine this automatically | [chapter 11](11-manual-controls.md) — **these do not go away by scanning harder** |
| `NOT-APPLICABLE` | the rule does not apply to this configuration | note it; an assessor may ask why |
| `ERROR` | the check could not run | investigate — an `ERROR` is not a `PASS` and is easy to let slide into one |

`MANUAL` is the category that gets lost. It is not a failure, so it does
not appear on a remediation list, and it is not a pass, so the control is
unsatisfied. Chapter 11 exists because of this row.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A -l compliance.openshift.io/check-status=MANUAL
oc get compliancecheckresult -A -l compliance.openshift.io/check-status=ERROR
```

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The key `compliance.openshift.io/check-status` is believed correct, and
> the documented values are `PASS`, `FAIL`, `INFO`, `MANUAL`,
> `INCONSISTENT`, `ERROR` and `NOTAPPLICABLE`. **Note the last one has no
> hyphen in the label**, even though the printed status column in the
> table above is written `NOT-APPLICABLE` — if those really differ, a
> selector copied from the table matches nothing. Companion labels
> believed to exist: `compliance.openshift.io/check-severity`,
> `compliance.openshift.io/scan-name`, `compliance.openshift.io/suite`.
> Confirm all of them from `--show-labels` on a real result rather than
> from this list.

A selector that matches nothing returns an empty list, which looks
exactly like "there are none". So never read a selector's output alone —
reconcile it against the total:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A --no-headers | wc -l
for s in PASS FAIL MANUAL INFO INCONSISTENT ERROR NOTAPPLICABLE; do
  printf '%-14s %s\n' "$s" \
    "$(oc get compliancecheckresult -A --no-headers \
         -l compliance.openshift.io/check-status=$s 2>/dev/null | wc -l)"
done
```

The per-status counts must sum to the total. If they do not, a value in
that list is wrong and some results are invisible to you — which is the
worst outcome available here, because the ones that vanish are not the
ones that were going to pass.

---

Next: [10-remediation.md](10-remediation.md).
