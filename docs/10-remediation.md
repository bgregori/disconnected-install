# Remediation

Turning the baseline's failures into a smaller set of failures, a set of
documented exceptions, and a record of what changed.

**Review-then-apply is the default in this repository.** Auto-apply is
documented as a variant, below, for the cases where it is the right call.

---

## Why review-then-apply is the default

Three reasons, in the order they will matter to you:

1. **Remediations change the cluster, and some of them will break your
   workload.** A STIG benchmark does not know what runs here. A
   remediation that tightens a kernel parameter or removes a permission
   is correct against the benchmark and may be wrong for this
   environment. You want to find that out by reading, not by watching.
2. **Node remediations reboot nodes.** See the economics below. Applying
   forty of them without reading them is a long outage you did not plan.
3. **The review is itself evidence.** "We applied the remediations" is
   weak. "We reviewed 68 remediations, applied 61, declined 7 with these
   reasons" is the artifact the ISSO actually wants, and it is free if
   you produce it as you go and expensive to reconstruct afterwards.

The cost is time. Budget it honestly: a first pass over a STIG baseline
is a day of reading, not an hour.

---

## The default: review, then apply

> **TODO:** needs validation on real hardware — the procedure for
> inspecting an individual `ComplianceRemediation` object to see exactly
> what it will change before applying it, and the mechanism by which a
> reviewed remediation is marked for application. Both have to be exact;
> this is the chapter where a half-remembered command does real damage.
>
> Establish: how a remediation's payload is read, how one is applied
> individually, how one is declined in a way that is visible later, and
> whether declining is a cluster-side state or something you track
> yourself in the exceptions register.

The review itself, whatever the mechanism:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get complianceremediation -A
oc get complianceremediation -A -o custom-columns=\
NAME:.metadata.name,STATE:.status.applicationState
```

For each one, three questions and a written answer:

- **What does it change?** Read the payload, not the rule title.
- **Does it reboot nodes?** A `MachineConfig` payload does. See below.
- **Does anything here depend on the current behaviour?** This is the
  question only your team can answer, and the one the benchmark cannot.

Anything you decline goes in the **exceptions register** immediately,
with a reason, while you still remember it. See
[12-evidence-pack.md](12-evidence-pack.md). A remediation declined in
March and explained in June is explained badly.

---

## Reboot economics

This is the section to read before planning the work, because it
determines whether remediation is one maintenance window or five.

Node remediations are delivered as `MachineConfig` objects. The Machine
Config Operator coalesces pending changes into a single rendered config
per pool and rolls the pool once — so **ten remediations applied
together cost one rollout; ten applied one at a time cost ten.**

The rollout itself drains and reboots nodes one at a time, respecting
`maxUnavailable`. For a pool of N nodes the wall clock is roughly N ×
(drain + reboot + rejoin), which on real hardware with real firmware is
minutes per node, not seconds.

| Topology | Cost of one MCP rollout |
|---|---|
| Multi-node | nodes cycle one at a time; workloads reschedule; no API outage |
| Three-node compact | control plane nodes cycle one at a time; quorum maintained; brief disruption, see [topologies/compact.md](topologies/compact.md) |
| Single node | **full cluster outage per reboot** — see [topologies/sno.md](topologies/sno.md) |

What this means in practice:

- **Batch them.** Review a whole set, apply the set, take one rollout.
- **Do not apply a remediation during a rollout.** Wait for the pool to
  report `UPDATED=True` before touching it again. Stacking changes onto a
  mid-rollout pool makes the outage longer and the result harder to
  reason about.
- **Count the rollouts in advance** and tell whoever owns the change
  window. "A few reboots" is how a two-hour window becomes a six-hour
  one.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get machineconfigpool
oc get machineconfigpool -w        # watch a rollout to completion
oc get nodes
```

> **TODO:** needs validation on real hardware — measured per-node drain
> and reboot time on this hardware, and the total for a representative
> remediation batch. Replace the hand-waving above with numbers once you
> have them; a measured figure is what makes a change request credible.

---

## The variant: auto-apply

The operator can apply remediations automatically as it finds them, via
a scan setting that does so. It is a legitimate choice in two
situations:

- **A rebuild of a cluster you have already remediated by hand**, where
  the review has been done once and the result is known.
- **A pre-production cluster** where the outage cost is low and the
  point is to find out what the benchmark does.

It is the wrong choice on a first run against a cluster anyone depends
on, for the reason at the top of this chapter: it reboots nodes in waves
before anybody has read what it is about to change.

> **TODO:** needs validation on real hardware — the auto-applying scan
> setting's exact name and the binding that selects it, and what the
> rollout pattern looks like in practice. Getting the scan setting names
> the wrong way round is the specific accident this repository is trying
> to prevent, so these must be confirmed rather than recalled.

> ⚠️ Prep warns the install side about this at handoff — "compliance
> auto-remediation reboots nodes; recommend scan-only before
> auto-apply". If you are reading this repository, you are the install
> side, and this is the step that warning was about.

### Remediations that need a second pass

Some remediations cannot take effect until something else has, and the
scanner will report them as still failing after the first apply. That is
expected rather than a sign the remediation did not work.

> **TODO:** needs validation on real hardware — which remediations in
> `ocp4-stig` and `rhcos4-stig` have dependencies of this kind, and
> whether the operator surfaces that explicitly. Until this is known,
> treat a persistent failure after a successful apply as "investigate"
> rather than "broken".

---

## Re-scan and delta

The point of the baseline.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
AFTER=${OCP_INSTALL_ROOT}/evidence/$(date +%Y-%m-%d)-after
mkdir -p ${AFTER}

oc get compliancecheckresult -A -o yaml  > ${AFTER}/checkresults.yaml
oc get complianceremediation -A -o yaml  > ${AFTER}/remediations.yaml
oc get compliancescan -A -o yaml         > ${AFTER}/scans.yaml

oc get compliancecheckresult -A \
  --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status,SEVERITY:.severity \
  | sort > ${AFTER}/summary.txt
```

Then the delta, which is the single most useful page in the evidence
pack:

```sh
# ===== RUN ON: THE CLUSTER =====
BASELINE=${OCP_INSTALL_ROOT}/evidence/<date>-baseline

diff ${BASELINE}/summary.txt ${AFTER}/summary.txt > ${AFTER}/delta.txt
awk '{print $2}' ${BASELINE}/summary.txt | sort | uniq -c
awk '{print $2}' ${AFTER}/summary.txt    | sort | uniq -c
```

Two counts and a diff. Read the diff in both directions:

- **`FAIL` → `PASS`** is what you intended.
- **`PASS` → `FAIL`** is the one to look at hardest. A remediation can
  break a check that was previously passing, and nobody looks for that.
- **A check that disappeared entirely** usually means the content
  version changed under you. See
  [chapter 9 on content versions](09-compliance-operator.md#content-versions-move-independently-of-the-cluster).

> **TODO:** needs validation on real hardware — how to trigger a re-scan
> without recreating the binding, and whether a re-scan reuses the same
> result object names (which would make the `diff` above compare the
> wrong things). Confirm before trusting the delta.

---

## What is left

After the re-scan, every remaining `FAIL` is in exactly one of three
states, and the evidence pack needs it labelled:

1. **Will be remediated** — scheduled, with a date and an owner.
2. **Waived** — accepted risk, with a reason and an approver. This is a
   decision for the ISSO, not for you.
3. **Documented deviation** — the control cannot be met in this
   environment, with an explanation of why and what compensates for it.

Plus the `MANUAL` results, which were never going to be resolved here —
[chapter 11](11-manual-controls.md).

"Unexplained" is not one of the three states. Every remaining failure
gets a line.

---

Next: [11-manual-controls.md](11-manual-controls.md).
