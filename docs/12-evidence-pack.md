# Evidence pack

The boundary, the way [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md)
is prep's boundary. This repository produces a bundle; the ISSO consumes
it.

The test of this chapter is simple and worth stating up front: **the
pack has to be readable by someone who was not here, without you in the
room.** If a question about it can only be answered by asking you, it
is not finished.

---

## A draft is never evidence

[VALIDATION.md](../VALIDATION.md#the-third-state-drafts) makes this a
rule for the whole repository. This chapter is where it bites, so it is
restated here in full rather than linked to:

> **No 🚧 `DRAFT -- NOT VALIDATED` block, and no output produced by
> running one, goes into this pack until the block has been replaced by
> the command as actually run.**

A draft states what somebody believed the step required. The pack states
what was done. Those are different claims, and the gap between them is
the entire reason the draft is marked. Validating a draft routinely
changes it — a flag that does not exist on this version, a namespace
that is not where the page said, an argument order that matters — and
if the block is not rewritten afterwards, the pack records the intention
instead of the act.

The failure is specific. A drafted command runs without erroring,
produces plausible output, the output is filed, and the draft block is
never touched again. Nothing in the pack marks it. Six months later the
only record of what was really typed is a terminal transcript nobody
read, and the assessor's question — "show me how you established this" —
has an answer that is subtly, unfalsifiably wrong.

Three obligations, in order:

1. **Run it, then write down what you ran** — not what the page said.
   The difference is the most valuable thing the run produces.
2. **Replace the draft block before its output is packed.** The command
   as executed goes back into the chapter; then the output is evidence.
   Update [VALIDATION.md](../VALIDATION.md#how-to-update-this-file) in
   the same sitting, while you still remember what differed.
3. **If you cannot now reconstruct what was typed, the transcript
   decides.** If the transcript does not cover it, the step is
   unevidenced — re-run it. This is the one case where re-running a
   successful step is the cheap option.

There is an objection worth answering, because someone will raise it at
exactly the wrong moment: a scan triggered by a drafted command is still
a real scan of a real cluster, so surely the result is a fact regardless
of how it was obtained. The result *is* a fact. But a pack is as much
*how* as *what*, and a result you cannot describe the production of is a
number without a method. Keep the output — it cost a scan window — and
pack it once the procedure beside it is the one that ran.

The checklists are not affected by any of this. A gate in
[install-acceptance.md](../checklists/install-acceptance.md) or
[ato-evidence.md](../checklists/ato-evidence.md) stays in front of a
drafted step, unchanged and not provisional. Drafts are provisional;
the things guarding them are not.

---

## What the ISSO is actually asking

Not "is the cluster compliant". Four questions:

1. **What is this thing, exactly?** Version, topology, what it runs on,
   what it depends on.
2. **What was wrong when you built it?** The baseline.
3. **What did you do about it?** The remediation record.
4. **What is still wrong, and why is that acceptable?** The exceptions
   register and the documented deviations.

A single clean scan answers none of these and tends to read as evasive,
because the obvious follow-up — "what did it look like before?" — has no
answer. The before/after pair answers all four and is less work, because
it is produced as you go.

---

## Structure

```
${OCP_INSTALL_ROOT}/evidence/
├── README.md                     what this is, who built it, when
├── cluster-description.md        version, topology, dependencies
├── <date>-baseline/              chapter 9 -- before any remediation
│   ├── checkresults.yaml
│   ├── remediations.yaml
│   ├── scans.yaml
│   ├── operator-version.yaml
│   └── summary.txt
├── <date>-after/                 chapter 10 -- after remediation
│   ├── checkresults.yaml
│   ├── remediations.yaml
│   ├── scans.yaml
│   ├── summary.txt
│   └── delta.txt
├── exceptions-register.md        every remaining FAIL, labelled
├── deviations.md                 controls that cannot be met here
├── manual-controls/              chapter 11, one file per control
│   ├── banner.md
│   ├── audit-forwarding.md
│   ├── rbac-review.md
│   └── mfa-attestation.md
├── install/                      the build record
│   ├── install-config.yaml.redacted
│   ├── manifests-src/            chapter 3 -- what went in before ignition
│   ├── node-encryption.txt       lsblk/cryptsetup per node
│   └── transcript-<host>.log     one per host, redacted
└── handoff/                      what prep gave you, for provenance
    └── (checksums and the imageset-config, not the 29 GB archive)
```

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/evidence/{manual-controls,install,handoff}
```

---

## The pack's README

The first file in the listing and the last one written. One page,
addressed to a reader who has the directory and nothing else.

```markdown
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/evidence/README.md =====
What this is:   evidence pack for <cluster>, built <date>
Built by:       <name>, <role>, <contact>
Covers:         install, hardening baseline, remediation, manual controls
Period:         <install date> to <pack date>
Walked through: with <ISSO name> on <date>

Read in this order:
  1. cluster-description.md   what the system is
  2. <date>-baseline/         what was wrong before remediation
  3. <date>-after/ + delta    what changed
  4. exceptions-register.md   what is still wrong, and the disposition
  5. deviations.md            what cannot be met here at all
  6. manual-controls/         what a scanner cannot determine
  7. install/, handoff/       how it was built, and where it came from

Procedure provenance:
  Every step in this pack was executed as written in the chapter
  cited beside it. Steps that were drafted and then validated were
  rewritten to the command as run before this pack was assembled.
  Exceptions, if any: <none | list them>
```

That last paragraph is not decoration. It is the statement the section
above obliges you to be able to make, and writing it is the moment you
find out whether you can. If you cannot — if some step was run from a
draft and never reconciled — the honest move is to list it under
*Exceptions* rather than to leave the paragraph in and hope. An assessor
who finds one unreconciled step in a pack that claims none will reopen
every other claim in it.

---

## The cluster description

One page. Someone reading the pack in two years needs to know what they
are looking at.

```markdown
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/evidence/cluster-description.md =====
Cluster:           <name>.<base-domain>
Installed:         <date>, by <name>
OpenShift version: <version>
Topology:          single node | three-node compact | multi-node (N workers)
FIPS:              fips: true, installed with openshift-install-fips
                   from a host with fips_enabled=1
Boot disk:         LUKS2, <TPM v2 | Tang | both>, cipher aes-cbc-essiv:sha256
etcd:              encrypted at rest, <type>
Identity:          external Red Hat build of Keycloak at <issuer>
                   kubeadmin deleted <date>
Image source:      mirror registry at <registry>, no internet egress
Dependencies:      mirror registry, NTP <source>, IdP <host>,
                   Tang <servers>, audit destination <host>
Compliance:        compliance-operator <version>,
                   profiles ocp4-stig / rhcos4-stig,
                   benchmark revision <revision>
```

The dependency list is the part people omit and the part that is read
most. A cluster that cannot pull images if one host goes away is a fact
about the system's availability, and the ISSO is entitled to it.

> ⚠️ **STIG** `install-config.yaml` contains the pull secret and the SSH
> public key. Redact the pull secret before the file goes in the pack.
> The redacted copy is still worth including — `fips: true`,
> `imageDigestSources` and `additionalTrustBundlePolicy` are exactly the
> things an assessor will want to see in the original.

---

## The scan results

Copied verbatim from chapters 9 and 10. Do not summarise them in place
of including them; summarise them *as well as* including them.

Each result set needs, alongside it:

- the **date** it was taken
- the **Compliance Operator version** and the **benchmark revision**
- which **profiles** were scanned
- a one-line statement of what had and had not been done to the cluster
  at that point

The last one is what makes the baseline meaningful. "Baseline, taken
after day-1 config and identity, before any remediation" is a sentence
the whole pack rests on.

### Two kinds of result, and only one of them is durable

The `ComplianceCheckResult` objects captured in chapter 9 are the
per-check verdicts, and they are what this pack is built from. The
operator also writes a full machine-readable report per scan — Asset
Reporting Format, the same XML an assessor's own tooling consumes — but
it goes to a persistent volume rather than to the API, and **it
rotates.** The operator keeps a small fixed number of raw result sets
per scan and discards the oldest; on a default configuration that is
three.

Three scans after the baseline, the baseline's raw report is gone. The
YAML captures are not affected, because chapter 9 copies them off the
cluster the moment they are taken, which is the entire reason it does
that. But if the ISSO asks for raw ARF — and some do, by name, because
their tooling ingests it — the one set you most need is the one most
likely to have aged out already.

So decide before chapter 13 enables any recurring scan:

- whether raw ARF is wanted at all, which is question 2 of the handover
  conversation below;
- if it is, that the **baseline** raw results come off the cluster at
  the same time as the YAML, not later;
- and that retention is sized deliberately rather than left at the
  default, because the default was not chosen with a baseline in mind.

Two airgap-specific traps sit behind any extraction procedure, and both
are content problems rather than cluster problems. The convenience
plugin for fetching raw results ships separately from `oc` and is not
on the cluster; if it was not carried across the airgap it is not
installable, like anything else. And the obvious alternative — a pod
that mounts the result volume and copies the files out — needs a
container image, which is subject to exactly the same rule. Neither is
hard. Both are a transfer window if discovered on the day.

---

## The exceptions register

Every `FAIL` remaining after chapter 10, one row each, no blanks.

```markdown
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/evidence/exceptions-register.md =====
| Check | Severity | Status | Reason | Owner | Review by |
|---|---|---|---|---|---|
| <check name> | high | Scheduled | Remediation applies a MachineConfig; batched into the <date> window | <name> | <date> |
| <check name> | medium | Waived | Accepted by ISSO <name> on <date>; compensating control: <what> | <name> | <date> |
| <check name> | low | Deviation | Cannot be met: <why>. Compensated by <what>. | <name> | <date> |
```

Three statuses, and no fourth:

| Status | Means | Needs |
|---|---|---|
| **Scheduled** | will be remediated | a date and an owner |
| **Waived** | accepted risk | an approver — the ISSO, not you — and a review date |
| **Deviation** | cannot be met in this environment | why, and what compensates |

"Unexplained" is not a status. A row with an empty reason is the thing
the assessor will open the document to.

The `MANUAL` results are not in this register. They are controls, not
failures, and they live in `manual-controls/`.

---

## Documented deviations

A deviation is different from a waiver and the distinction is worth
keeping: a waiver accepts a risk that could be fixed; a deviation
records that the control cannot be met here at all.

Each one needs: the control, why it cannot be met in this environment,
what compensates for it, and who accepted that.

Two that are likely in a build like this, offered as examples of the
*shape* rather than as findings you should expect:

- **A control that assumes internet access.** Anything that requires
  reaching an external service — a vulnerability feed, a certificate
  revocation endpoint, a time source outside the enclave — cannot be met
  by design. The compensating control is the airgap itself, and saying
  so plainly is stronger than leaving it as a failure.
- **A time-boxed hardening deviation during the build.** Prep's registry
  install requires temporarily relaxing a umask setting that is itself a
  STIG finding, and documents it as a time-boxed, verified-reverted
  deviation precisely because
  [a surprise documents worse than a deviation does](https://github.com/bgregori/disconnected-prep/blob/main/docs/05-registry.md#permissions-and-the-umask-that-actually-matters).
  If anything similar happened on the install host, it belongs here with
  the same treatment: what, when, why, and the evidence it was reverted.

---

## The build record

The thing that is hardest to reconstruct and easiest to capture.

- **The terminal transcript.** Every script in this repository echoes
  each command before running it, so the transcript is an accurate
  record of what was done on the host. Keep it — see below.
- **The manifests from chapter 3** — the disk encryption MachineConfigs,
  the chrony configuration, the project template. These are the files
  that made the cluster what it is and they do not exist anywhere else
  after the install directory is cleaned up.
- **Per-node disk encryption proof:**

```sh
# ===== RUN ON: A NODE =====
lsblk --fs
cryptsetup status root
```

Run it on every node and keep all of it. One node's output is not
evidence about the others, and a pool that was expanded later is exactly
where an unencrypted node appears.

- **Where the break-glass `kubeconfig` is.** Not the file — the
  *location*, and who can retrieve it. See
  [chapter 5](05-first-access.md#the-credentials-the-installer-produced).
  This is a question that will be asked and that has no good improvised
  answer.

### The transcript

Start it at chapter 1, not when you remember:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/evidence/install
script -a -q ${OCP_INSTALL_ROOT}/evidence/install/transcript-$(hostname -s).log
```

`-a` appends, so resuming after a break does not discard what came
before. `exit` or Ctrl-D closes it cleanly; a transcript that was never
closed is usually still readable but may be missing its last lines,
which are the ones you wanted.

Three things about transcripts, each learned the expensive way:

- **One transcript per host.** The install host's transcript proves
  nothing about what was typed in a node debug shell, and the location
  markers on every block in this repository exist precisely because
  those two look alike. The `$(hostname -s)` in the filename above is
  doing that work; keep it.
- **A transcript captures credentials.** The pull secret, the IdP client
  secret, the `kubeadmin` password, anything pasted into a heredoc. It
  is an accreditation artifact *and* a secret-bearing file, and it
  inherits the handling of the most sensitive thing in it. Read it
  before it goes in the pack, redact a copy, and keep the unredacted
  original wherever the break-glass `kubeconfig` lives rather than
  deleting it.
- **A transcript is not a substitute for replacing a draft.** It records
  what was typed, which is what makes it the tiebreaker in the rule at
  the top of this chapter. It does not update the chapter, and nobody
  reconstructs a procedure from a transcript voluntarily.

---

## Provenance

Where the content came from matters, and prep already produced the
record: checksums over the transferred archive, the
`imageset-config.yaml` that states exactly what was mirrored, and the
handoff contract signed by both sides.

Include the contract and the `imageset-config.yaml`. Do not include the
archive.

The chain the pack should make visible: Red Hat's registries → prep's
verified mirror → this cluster, with nothing entering from anywhere
else. That is a stronger supply-chain story than most connected
clusters can tell, and it is worth telling explicitly rather than
leaving the assessor to infer it.

---

## Handing over

Work through
[checklists/ato-evidence.md](../checklists/ato-evidence.md) before the
conversation, and walk the pack with the ISSO rather than emailing it.
Prep's handoff contract works the same way and for the same reason: a
directory someone was sent is not shared understanding.

The questions worth asking directly:

1. Is the baseline/after/delta structure what they expect, or do they
   have a format?
2. Do they want the raw `ComplianceCheckResult` YAML, a rendered
   report, or machine-readable ARF? The operator can produce all
   three; ask before you generate the wrong one, and ask **early**,
   because
   [the raw results age off the cluster](#two-kinds-of-result-and-only-one-of-them-is-durable)
   and the baseline's cannot be regenerated.
3. Who approves the waivers, and by when?
4. What is the re-scan cadence they expect, and who sees the results?
   That answer goes into [13-day2.md](13-day2.md).
5. What would they want to see that is not in this pack? Ask it last,
   ask it plainly, and write the answer down even if you disagree with
   it. It is the only question whose answer you cannot predict, and the
   cheapest time to hear it is before submission.

Before any of that, make the statement the pack's README commits you to:
every step was executed as the chapter now describes it, and no drafted
block went unreconciled. If that is not true yet, it is a morning's work
and it is work that does not get easier later.

> **TODO:** needs validation on real hardware — whether the Compliance
> Operator's own report rendering is usable as an ISSO-facing artifact,
> or whether the raw results plus this structure is better. Ask an ISSO
> before building anything.

---

Next: [13-day2.md](13-day2.md).
