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

> **TODO:** needs validation on real hardware — the `Namespace`,
> `OperatorGroup` and `Subscription` for the Compliance Operator against
> the **mirrored** catalog. The `source` and `sourceNamespace` fields
> must name prep's `CatalogSource`, not the default one, and that is the
> part a generic walkthrough gets wrong in a disconnected cluster.
>
> Establish also: the install namespace the operator expects, whether it
> is namespace-scoped or cluster-scoped in effect, and what a
> `Subscription` stuck in `InstallPlanPending` looks like when the
> content is only partially mirrored — which is the realistic failure
> here, as distinct from the content being absent entirely.

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

> **TODO:** needs validation on real hardware — where the **benchmark
> revision** is actually recorded. The operator version is on the CSV and
> is easy; the revision of the STIG benchmark the content implements is
> the number an assessor cares about, and which field carries it has not
> been confirmed. The `grep` above is a placeholder for finding it, not a
> procedure.

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

> **TODO:** needs validation on real hardware — the `ScanSettingBinding`
> that binds both profiles to a scan-only `ScanSetting`, and the names
> of the default scan settings as shipped. The scan-only one is the
> default and the auto-applying one is not; getting these the wrong way
> round on a first run rolls the cluster. Confirm the exact names before
> writing them down.

---

## Running the baseline scan

> **TODO:** needs validation on real hardware — applying the binding,
> watching the scan to completion, and how long it takes. The duration
> is worth measuring because the node scan runs a pod per node and the
> first question anyone asks is whether it has finished or hung.

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

> **TODO:** needs validation on real hardware — the `custom-columns`
> field paths above (`.status`, `.severity` on a
> `ComplianceCheckResult`). A wrong path prints an empty column rather
> than erroring, which produces a `summary.txt` full of blanks that
> `diff`s cleanly against another one full of blanks. Confirm the paths
> produce real values before trusting any delta built from them. The
> `-o yaml` captures above are unaffected and are the authoritative
> record either way.

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

> **TODO:** needs validation on real hardware — the label selectors
> above. The shape is right but the label keys and values have not been
> confirmed against a running operator. Verify before relying on them;
> a selector that matches nothing returns an empty list, which looks
> exactly like "there are none".

---

Next: [10-remediation.md](10-remediation.md).
