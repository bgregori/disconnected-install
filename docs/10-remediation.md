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

### Reading the payload

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The payload is at **`spec.current.object`** — confirmed; the
> `spec.object.current` form that some sources give does not exist.
> What is still drafted is everything below about reading it in bulk.
>
> **But `spec.current.object` is not unconditionally what gets
> applied.** If `spec.outdated.object` is present, the operator applies
> *that* instead. An outdated payload appears when the content changed
> under a remediation, it requires an administrator to clear it, and a
> `jsonpath` loop reading only `current` will show you one object while
> the cluster applies another. Check for `outdated` first. A `jsonpath`
> that misses
> prints nothing and errors nothing, which in this chapter means
> reviewing a remediation by looking at a blank line.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get complianceremediation/<name> -n openshift-compliance -o yaml

# once the path is confirmed, the payload alone:
oc get complianceremediation/<name> -n openshift-compliance \
  -o jsonpath='{.spec.current.object}'
```

What you are looking for, in this order:

- **`kind`.** `MachineConfig` or `KubeletConfig` means a node change and
  therefore a reboot. Anything else is usually a cluster resource and
  usually is not.
- **The actual content.** For a `MachineConfig` this is Ignition, and
  the interesting part is frequently a base64 or URL-encoded file body
  that you have to decode to read. Decode it. "It sets a sysctl" is not
  a review.
- **`spec.outdated`**, if present. It holds the payload parsed from an
  earlier content version, retained so you can see what changed when the
  operator was updated. If it is populated, the remediation is not what
  it was at baseline and you are reviewing a moving target — resolve
  that first.

### Applying one

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Applying is a single required boolean, `spec.apply` — confirmed, and
> it is top-level on the spec, not nested. The operator watches it and
> creates the payload. This is still the chapter where a
> half-remembered command does real damage, so watch what happens on
> one low-risk remediation before you batch anything.
>
> ⚠️ **Setting `apply` on one remediation can set it on others.** A
> single XCCDF fix that produces several Kubernetes objects becomes
> several remediation CRs, named identically except for a trailing
> `-1`, `-2` and so on. The controller treats that family as a unit:
> set `apply` on any one of them and it flips `apply` on all its
> siblings. You cannot apply half a fix, and a count of "remediations I
> applied" taken from your own commands will understate what actually
> changed. Count the objects afterwards, not the patches you issued.

```sh
# ===== RUN ON: THE CLUSTER =====
oc patch complianceremediation/<name> -n openshift-compliance \
  --type=merge -p '{"spec":{"apply":true}}'

oc get complianceremediation/<name> -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,STATE:.status.applicationState
```

`status.applicationState` takes exactly seven values — `NotApplied`
(the default), `Pending`, `Applied`, `Outdated`, `Error`,
`MissingDependencies` and `NeedsReview`. Read from the operator's
types, so the list is complete; what each one means in practice is
still drafted below. Only the first three are normal.

> ⚠️ **Set `apply: true` on a batch, not one at a time** — see the reboot
> economics below. The per-remediation command above is for the first
> one, where you are confirming the mechanism, not for the other sixty.

### Declining one

**There is no cluster-side "declined" state.** This was drafted as a
suspicion and is now confirmed from the operator's own types:
`spec.apply` is a plain boolean with no third value, and
`status.applicationState` is one of `Pending`, `NotApplied`, `Applied`,
`Outdated`, `Error`, `MissingDependencies`, `NeedsReview` — defaulting
to `NotApplied`. Nothing in that set means "a human looked at this and
said no".

So a remediation you reviewed and rejected is byte-for-byte identical
to one nobody has opened. That is not a gap to work around; it is the
fact the rest of this section is built on.

**The decline record lives outside the cluster, or it does not exist.**
Anything you decline goes in the **exceptions register** immediately,
with a reason, while you still remember it. See
[12-evidence-pack.md](12-evidence-pack.md). A remediation declined in
March and explained in June is explained badly — and with no cluster-side
state to jog anyone's memory, "declined" and "missed" are the same object
six months later.

A cheap local convention, if you want a marker on the cluster as well as
in the register:

```sh
# ===== RUN ON: THE CLUSTER =====
oc annotate complianceremediation/<name> -n openshift-compliance \
  review.local/decision='declined 2026-10-12 <name> -- see exceptions register'
```

That annotation is yours, not the operator's. It will not survive the
object being recreated by a re-scan, so it supplements the register and
never replaces it.

---

## Reboot economics

Read this before planning the work. On an initial build there is no
change window to overrun and nothing in service to disrupt — the cost is
elapsed time, and the risk is breaking the cluster you are standing in
front of. Both are real. A three-node compact cluster rolled carelessly
loses etcd quorum whether or not anything is running on it, and on single
node every rollout is a serial reboot you wait out.

The reason to get the discipline right now, when it is cheap, is that it
stops being cheap at handover. Everything below is also the method
[chapter 13](13-day2.md) depends on, when there *is* a change window and
the numbers have to be credible in advance.

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

### Batching: pause the pool

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **There are two batching mechanisms and you only get one of them.**
> That question is now settled, and the answer decides whether the
> commands below are necessary or redundant.
>
> Under **auto-apply**, the operator does it for you: once the suite
> reaches `Done` it pauses every affected pool, sets `apply` across the
> suite's remediations, waits for them all, and unpauses once. That is
> a real "apply a set, take one rollout" guarantee.
>
> Under **manual apply** — which is what this chapter recommends and
> what the commands below do — **the operator pauses nothing.** The
> suite controller returns immediately because auto-apply is off. Each
> remediation just creates its `75-` MachineConfig as it reconciles,
> and any batching you get is the Machine Config Operator happening to
> coalesce changes that arrived close enough together. That is
> timing-dependent, not a guarantee.
>
> So pausing the pool yourself is **not** redundant on the manual path.
> It is the only thing that makes the rollout count predictable. What
> remains drafted is the command sequence, not the reasoning.

```sh
# ===== RUN ON: THE CLUSTER =====
oc patch machineconfigpool/master --type=merge -p '{"spec":{"paused":true}}'
oc patch machineconfigpool/worker --type=merge -p '{"spec":{"paused":true}}'

# ... set apply: true on the reviewed set ...

oc get machineconfig | grep -i compliance     # the rendered remediations
oc patch machineconfigpool/worker --type=merge -p '{"spec":{"paused":false}}'
oc get machineconfigpool -w
```

> ⚠️ **A paused pool is a pool that is not getting security updates
> either.** Unpause it before you walk away from it — the same sitting,
> not the next one. A pool left paused is invisible: nothing is degraded,
> nothing alerts, and the next three months of `MachineConfig` changes
> quietly do not apply. A build-time pause that nobody unpaused is a
> finding that surfaces long after anyone remembers pausing it. Unpause
> one pool at a time and let it finish before the next.

Each applied node remediation becomes **its own `MachineConfig`**,
named `75-<scan-name>-<rule-name>`, with a `-1`, `-2` suffix for the
second and subsequent objects of a multi-object fix. Twenty applied
node remediations means twenty `75-` objects.

> ⚠️ **Red Hat's documentation says otherwise, and it is wrong.** The
> Compliance Operator chapter states that remediations are rendered
> into a MachineConfig named `75-$scan-name-$suite-name` — a single
> object, with the suite name in it. The suite name appears nowhere in
> the real name, and there is no aggregation step in the operator at
> all. The same documentation page contradicts itself a few paragraphs
> later by listing four separate `75-<scan>-<rule>` objects from one
> re-scan.
>
> This matters because a reviewer checking your work against
> docs.redhat.com will think the corrected text is the error. The
> operator's `GetMcName()` is the authority.
>
> The thing that *is* rendered into one object per pool is the Machine
> Config Operator's `rendered-<pool>-<hash>`, which is a different
> mechanism, a different name, and the reason batching works at all.

If the `75-` objects exist and the pool has rolled, the change is on
the nodes; if the pool reports `UPDATED=True` but no `75-` object was
created, nothing was applied and the scan will say so.

### Measuring the cost

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **There are no measured numbers in this repository yet**, and the
> hand-waving above stays hand-waving until there are. This is the
> procedure for getting them, not the answer.
>
> Measure it here because here is the only place you can: an empty
> cluster, nothing to drain, no one waiting. The figure is not for this
> rollout — it is what makes [chapter 13's](13-day2.md) first real change
> request credible, and "a few reboots" is what turns a two-hour window
> into a six-hour one once there *is* a window.

```sh
# ===== RUN ON: THE CLUSTER =====
date -u +%FT%TZ                               # start of the rollout
oc get machineconfigpool -w | tee /tmp/mcp-rollout.log
date -u +%FT%TZ                               # pool reports UPDATED=True

# per-node detail, after the fact
oc get nodes -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[-1].type,\
CONFIG:.metadata.annotations.machineconfiguration\.openshift\.io/currentConfig
```

Record three numbers and put them in the evidence pack: per-node drain +
reboot + rejoin, nodes per pool, and the total for the batch. Nothing in
this chapter needs them. They are the input to every change request made
*after* handover, including [chapter 13's](13-day2.md) upgrades, and this
is the last time the cluster is quiet enough to measure them cleanly.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The auto-applying setting is `default-auto-apply`, identical to
> `default` except that `autoApplyRemediations` and
> `autoUpdateRemediations` are both `true` — confirmed. What is drafted
> is the loop below, not the names.
>
> **Getting the two the wrong way round is the specific accident this
> repository exists to prevent**, and reading it off the cluster is
> still the right habit — but read it knowing what
> [chapter 9](09-compliance-operator.md#three-profiles-not-two)
> establishes: on `default` those booleans are **absent, not `false`**,
> and neither key appears in the output. Absence is the pass. Nobody
> reconciles these objects either, so `default` on this cluster is
> whatever the last person left it as.

```sh
# ===== RUN ON: THE CLUSTER =====
for s in $(oc get scansetting -n openshift-compliance -o name); do
  echo "== $s"
  oc get $s -n openshift-compliance \
    -o jsonpath='{.autoApplyRemediations}{" / "}{.autoUpdateRemediations}{"\n"}'
done
```

Switching an existing binding over, rather than creating a second one —
two bindings against the same profiles is a way to get two suites
fighting over the same remediations:

```sh
# ===== RUN ON: THE CLUSTER =====
oc patch scansettingbinding/stig-baseline -n openshift-compliance \
  --type=merge -p '{"settingsRef":{"name":"default-auto-apply"}}'
```

The rollout pattern, as documented and not as seen: when the scan
reaches `DONE`, the suite controller pauses the machine config pool the
scan maps to, sets `apply: true` on every remediation at once, then
unpauses — one rollout, not one per remediation. `autoUpdateRemediations`
then does the same thing again, unprompted, whenever the content image
changes. **That second boolean is the one to think hardest about:** it
means a Compliance Operator update can reboot your nodes with no change
request, which is exactly the behaviour chapter 9 warns about under
content versions.

> ⚠️ Prep warns the install side about this at handoff — "compliance
> auto-remediation reboots nodes; recommend scan-only before
> auto-apply". If you are reading this repository, you are the install
> side, and this is the step that warning was about.

### Remediations that need a second pass

Some remediations cannot take effect until something else has, and the
scanner will report them as still failing after the first apply. That is
expected rather than a sign the remediation did not work.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The operator does surface this explicitly, through the
> `applicationState` values below rather than through silence —
> confirmed. **Which** remediations in the three STIG profiles land in
> those states is unknown and is revision-specific; enumerate it from
> your own first pass rather than from a list. Treat a persistent
> failure after a successful apply as "investigate" rather than
> "broken".

```sh
# ===== RUN ON: THE CLUSTER =====
oc get complianceremediation -n openshift-compliance \
  -o custom-columns=NAME:.metadata.name,STATE:.status.applicationState \
  | grep -E 'MissingDependencies|NeedsReview|Error|Outdated'
```

| State | Means | What you do |
|---|---|---|
| `MissingDependencies` | a rule it depends on has not passed, or an object it depends on does not exist | apply the prerequisite, re-scan, then apply this one |
| `NeedsReview` | the remediation needs a tailoring variable you have not set — **only ever this**, never dependencies | set the variable in a `TailoredProfile` |
| `Outdated` | the content changed and the payload with it | read `spec.outdated` against `spec.current` before applying — and note the operator applies **`outdated`** if it is present |
| `Error` | the operator could not create the payload | read the object's conditions; this is not a dependency problem |

### Dependencies are evaluated once, and then never again

`MissingDependencies` comes from one of two annotations the content
puts on a remediation: a list of XCCDF rules that must evaluate `PASS`,
or a list of Kubernetes objects that must exist. While either is unmet
the operator labels the remediation
`compliance.openshift.io/has-unmet-dependencies` and re-checks every
twenty seconds.

**What is missing is reported in events, not in status.** The
remediation tells you *that* a dependency is unmet; a
`RemediationDependencyCannotBeMet` event on the object names *which*.
Events age out, so read them while they exist:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get events -n openshift-compliance \
  --field-selector reason=RemediationDependencyCannotBeMet \
  --sort-by=.lastTimestamp
```

> ⚠️ **Once satisfied, a dependency is never re-checked.** When the
> last one is met the operator writes a
> `compliance.openshift.io/dependencies-met` annotation — and nothing
> in the operator ever removes it. If the rule that dependency rested
> on later regresses to `FAIL`, this remediation goes on believing its
> prerequisite holds, and will apply against a cluster where it does
> not.
>
> The practical consequence is for re-runs, which is to say
> [chapter 13](13-day2.md): a cluster that has drifted does not
> re-raise dependency failures it cleared months ago. The scan will
> still fail the underlying rule, so the information is not lost — but
> it arrives as an unexplained `FAIL` rather than as a dependency
> problem, and nothing connects the two.
>
> The `has-unmet-dependencies` label is a derived marker, not the
> source of truth. Deleting it by hand changes nothing.

### What actually holds a pool paused

Earlier drafts of this chapter said that a remediation in `NeedsReview`
holds the MachineConfigPool paused by design. **That is wrong, and so
is Red Hat's documentation, which says the same thing.**

The operator explicitly *skips* `NeedsReview` remediations when
deciding whether to unpause — it emits a `CannotRemediate` warning
event and moves on. The pool unpauses. This was a deliberate bug fix
upstream, in a commit titled "fix needs-review unpause pool"; the stuck
pool was the bug, and the documentation still describes it as the
feature.

The half of Red Hat's sentence that *is* true: a `NeedsReview`
remediation is not applied until you set the variable. It just does not
hold anything else up while you do.

What does hold a pool paused, on the auto-apply path, is any
remediation that is `Pending`, `NotApplied` or `Error` with `apply`
set. Note what is missing from that list: `MissingDependencies` also
does not block, because the operator counts a blocked-but-requested
remediation as applied — the same quirk that makes it overcount
elsewhere.

> ⚠️ **An auto-apply suite will unpause a pool you paused by hand.**
> The operator tracks every pool its remediations touch, and on
> reaching `Done` it unpauses all of them — it does not check whether
> it was the one that paused them. If you pause a pool to defer a
> rollout and an auto-apply binding exists on the same cluster, your
> pause will be lifted and the rollout will happen. This is the
> strongest practical argument for not having an auto-apply binding
> present at all while you are doing manual work.

Check `spec.paused` and `applicationState` together before concluding
anything about a pool that will not roll — but expect the cause to be
`Pending` or `Error`, not `NeedsReview`.

> **Do not count "applied" by asking the operator.** Its own
> `IsApplied()` helper returns true for three different situations: the
> state is genuinely `Applied`; or `apply: true` and the state is
> `Outdated`; or **`apply: true` and the state is
> `MissingDependencies`** — a remediation that is explicitly blocked
> from applying. Anything built on that helper, including whatever the
> operator renders in a report, will count a blocked remediation as a
> done one.
>
> For the evidence pack, count `applicationState == Applied` yourself
> and reconcile the rest by state. The number that goes to an ISSO
> should be one you can derive from the object list, not one the
> operator summarised for you.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get complianceremediation -n openshift-compliance \
  -o jsonpath='{range .items[*]}{.spec.apply}{"\t"}{.status.applicationState}{"\n"}{end}' \
  | sort | uniq -c | sort -rn
```

Read that table as a grid. `true` against anything other than `Applied`
is work that is not finished; `false` against anything is a decision
nobody can see from the cluster, which is what the exceptions register
is for.

So the second pass is a loop, not a step: **apply → re-scan → look again
at what is still failing → apply.** Expect at least two rounds. Budget
the reboots for both.

---

## Re-scan and delta

The point of the baseline.

### Before you re-scan

**A re-scan reuses the same result object names.** `ComplianceCheckResult`
names are derived from the scan name and the rule, so the second run
overwrites the first in place — there is no second generation of objects
to diff against. That is fine for the procedure below, because the
`diff` compares two **files you already wrote**, not two sets of live
objects. It is fatal if you skipped chapter 9's capture step, or captured
the baseline and left it on the cluster: in that case the baseline no
longer exists anywhere and cannot be reconstructed.

> ⚠️ **Confirm the baseline capture exists and is non-empty before
> triggering the re-scan.** This is the one irreversible step in the
> chapter. Everything else can be re-run.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
ls -l ${OCP_INSTALL_ROOT}/evidence/*-baseline/checkresults.yaml
```

Empty, missing, or zero bytes means stop and go back to
[chapter 9](09-compliance-operator.md#capturing-the-baseline). And the
copy off the cluster-adjacent host that chapter 9 asked for is doing its
real work here — the on-cluster objects are about to be destroyed.

### Triggering the re-scan

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> A re-scan is believed to be triggered by annotating each
> `ComplianceScan` — not the binding, and not by deleting and recreating
> anything. Deleting the binding would also delete the results, which is
> the expensive way to learn this.

```sh
# ===== RUN ON: THE CLUSTER =====
for s in $(oc get compliancescan -n openshift-compliance -o name); do
  oc annotate --overwrite $s -n openshift-compliance \
    compliance.openshift.io/rescan=
done
oc get compliancesuite -n openshift-compliance -w
```

The trailing `=` with nothing after it is deliberate: the annotation's
presence is the signal and its value is ignored. The operator is
believed to remove it once the re-scan starts, which is why `--overwrite`
is harmless on a second run.

### Capturing the after

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
pack.

> **Script:** `./scripts/72-delta.sh` does this and reads it back for
> you. It takes the two directories, refuses to run if either
> `summary.txt` has an empty status column, and writes a per-check
> **transition** table alongside the raw diff — so a single
> `PASS` → `FAIL` cannot hide among sixty `FAIL` → `PASS` lines. It
> touches only files already on disk and makes no call to the cluster,
> which is why it exists while the rest of this chapter does not.

### By hand

```sh
# ===== RUN ON: THE CLUSTER =====
BASELINE=${OCP_INSTALL_ROOT}/evidence/<date>-baseline

diff ${BASELINE}/summary.txt ${AFTER}/summary.txt > ${AFTER}/delta.txt
awk '{print $2}' ${BASELINE}/summary.txt | sort | uniq -c
awk '{print $2}' ${AFTER}/summary.txt    | sort | uniq -c
```

The transitions, which the raw diff does not give you directly:

```sh
# ===== RUN ON: THE CLUSTER =====
join -j1 \
  <(awk '{print $1, $2}' ${BASELINE}/summary.txt | sort) \
  <(awk '{print $1, $2}' ${AFTER}/summary.txt    | sort) \
  | awk '$2 != $3 {print $2 " -> " $3 "\t" $1}' | sort
```

Two counts and a diff. Read the diff in both directions:

- **`FAIL` → `PASS`** is what you intended.
- **`PASS` → `FAIL`** is the one to look at hardest. A remediation can
  break a check that was previously passing, and nobody looks for that.
- **A check that disappeared entirely** usually means the content
  version changed under you. See
  [chapter 9 on content versions](09-compliance-operator.md#content-versions-move-independently-of-the-cluster).

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
