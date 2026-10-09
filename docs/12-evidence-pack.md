# Evidence pack

The boundary, the way [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md)
is prep's boundary. This repository produces a bundle; the ISSO consumes
it.

The test of this chapter is simple and worth stating up front: **the
pack has to be readable by someone who was not here, without you in the
room.** If a question about it can only be answered by asking you, it
is not finished.

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
│   └── transcript.log
└── handoff/                      what prep gave you, for provenance
    └── (checksums and the imageset-config, not the 29 GB archive)
```

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/evidence/{manual-controls,install,handoff}
```

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
  record of what was done on the host. Keep it. `script(1)` or a tmux
  logging plugin, from the start of chapter 1.
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
2. Do they want the raw `ComplianceCheckResult` YAML, or a rendered
   report? The operator can produce both; ask before you generate the
   wrong one.
3. Who approves the waivers, and by when?
4. What is the re-scan cadence they expect, and who sees the results?
   That answer goes into [13-day2.md](13-day2.md).

> **TODO:** needs validation on real hardware — whether the Compliance
> Operator's own report rendering is usable as an ISSO-facing artifact,
> or whether the raw results plus this structure is better. Ask an ISSO
> before building anything.

---

Next: [13-day2.md](13-day2.md).
