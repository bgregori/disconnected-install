# STIG on a cluster

Background, not a procedure. Read it when something in the numbered
chapters looks arbitrary, or when someone asks why a step exists.

Prep has the equivalent for the *hosts* —
[FIPS/STIG on RHEL 9](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md)
— covering `umask`, SELinux, fapolicyd and the `/var/tmp` partition. Those
problems are identical on the install host and are not repeated here.
This appendix is about the cluster.

---

## Four different things called "STIG"

Conflated constantly, and the distinction decides who owns what.

| | What it hardens | Where it is applied | Who owns it |
|---|---|---|---|
| **RHEL 9 STIG** | the install host, the registry host, the IdP host | at OS build, by the platform team | not this repo — see [prep](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md) |
| **`rhcos4-stig`** | the RHCOS operating system on the nodes | MachineConfigs, at install and after | [ch. 3](03-manifests.md), [ch. 10](10-remediation.md) |
| **`ocp4-stig-node`** | OpenShift's node-level configuration — kubelet, the runtime | MachineConfigs | [ch. 10](10-remediation.md) |
| **`ocp4-stig`** | the OpenShift platform itself | cluster resources | [ch. 6](06-day1-cluster-config.md) through [ch. 11](11-manual-controls.md) |

The middle two are the pair that gets collapsed into one. They are
different layers on the same machine: `rhcos4-stig` is the operating
system, `ocp4-stig-node` is OpenShift's configuration *of* that
operating system. And `ocp4-stig` is not a superset of either — it
filters node-platform rules out by construction, which is why
[chapter 9](09-compliance-operator.md#three-profiles-not-two) insists
on all three.

The confusion that costs time: **RHCOS is not RHEL from the benchmark's
point of view.** Applying RHEL 9 STIG remediations to a node by hand
breaks it, because RHCOS's filesystem is immutable and its configuration
is owned by the Machine Config Operator. The `rhcos4-stig` profile exists
because the RHEL profile does not apply.

A node fixed by hand is also a node that drifts from its pool, which is
what the File Integrity Operator in [chapter 13](13-day2.md) will report
— correctly, and to everyone's confusion.

---

## Why so few rule IDs appear in this repository

Nine out of eighty-three. Five in [chapter 7](07-identity.md) about
authentication, and four about cryptography — three for FIPS in
[chapter 2](02-install-config.md#fips-true), one for etcd in
[chapter 8](08-encryption-at-rest.md). That is deliberate and it is the
main thing this appendix is here to explain.

The nine are not the important ones because they are the important
controls. They are the ones somebody read.

Rule IDs look like stable identifiers and are not:

- **They change between benchmark revisions.** A rule renumbered between
  revisions makes a citation wrong without anybody editing anything.
  Nothing in your document changed; it simply stopped being true. There
  is no mechanism that will tell you — not a build failure, not a scan
  result, not a review. A citation written in March against one revision
  and scanned in September against another is already wrong and still
  looks fine.
- **They are not the same across profiles.** The identifier in the
  published benchmark, the Compliance Operator's rule object name, and
  the check result name are three different strings for the same
  control. The benchmark identifier is what the ISSO and the assessor
  read; the operator's rule object name is what your cluster will
  actually show you. Copying the string the cluster gives you into a
  document that says "STIG rule" is the single most common way a wrong
  citation is created, because the string is real, it is correct, and
  it is not the identifier being claimed.
- **A wrong one survives review.** It looks right, gets copied into the
  SSP, and is found by the assessor — at which point every other
  citation in the document is in question too. That is the asymmetry
  worth internalising: the assessor does not find one bad citation and
  correct it. They find one and then re-check the rest, and the pack
  stops being something they read and becomes something they audit.

So: cite a rule only after reading it against the revision you are
scanning with, and record the revision alongside. The cost of citing
nothing is a slightly vaguer document. The cost of citing wrongly is the
credibility of the whole pack.

**Describe the control instead.** "The scan checks that the token
lifetime does not exceed eight hours" is accurate, verifiable, revision-
independent, and sufficient for every reader except one — and the one
reader who needs the identifier needs the *current* one, which you can
only give them by reading it.

When you do cite one, cite three things together, never the identifier
alone:

1. the benchmark identifier, read from the benchmark;
2. the benchmark revision it was read from;
3. the operator's rule object name and content version, if the claim is
   that a scan verifies it.

[Chapter 9](09-compliance-operator.md#content-versions-move-independently-of-the-cluster)
has the practical version of this: capture the operator version and the
benchmark revision with every result. That capture is what makes a
citation re-checkable a year later, and a citation that cannot be
re-checked is a liability regardless of whether it happens to be right.

---

## Immutable decisions

The install-time choices that cannot be revisited, collected because
they are scattered through the chapters and the list is what people
want:

| Decision | Set at | Changing it later means | Caught by a scan? |
|---|---|---|---|
| `fips: true` | [ch. 2](02-install-config.md) | reinstall | **yes** — three controls |
| Boot-disk encryption and mode | [ch. 3](03-manifests.md) | reprovision every node | **no** — see below |
| Topology / replica counts | [ch. 2](02-install-config.md) | reinstall | no |
| Cluster name, base domain | [ch. 2](02-install-config.md) | reinstall | no |
| Pod and service network CIDRs | [ch. 2](02-install-config.md) | unsupported | no |

Everything else in this repository is recoverable. These five are the
conversation to have before the build, which is why
[chapter 1](01-intake.md#decide-before-you-install) ends with them.

The first two are the pair worth separating, because they are the two
with a compliance consequence and they behave in opposite ways.

**`fips: true` is required and checked.** CNTR-OS-000340,
CNTR-OS-000510 (high) and CNTR-OS-001080 all reduce to
`fips_mode_enabled_on_all_nodes`, and that check reads one thing: the
line in `install-config.yaml`. Omit it and three controls fail on the
first scan. Loud, early, unambiguous — the good kind of failure.

**Boot-disk encryption is required by the accreditation and checked by
nothing.** No control in the benchmark asks about it. An unencrypted
cluster returns a clean `ocp4-stig`, a clean `ocp4-stig-node` and a
clean `rhcos4-stig`, and produces an evidence pack with nothing wrong
in it. The requirement comes from protection of information at rest and
from the site's own policy on media leaving the facility, neither of
which the Compliance Operator implements.

That asymmetry is the argument for prep raising disk encryption at
handoff rather than leaving it here: FIPS has a safety net and disk
encryption has none. The only thing standing between a deferred
decision and an unencrypted accredited cluster is somebody writing it
down at intake.

---

## What hardening costs operationally

Worth knowing before committing, and worth telling whoever will run the
cluster afterwards.

**Reboots become the unit of change.** Most node-level hardening is a
MachineConfig, and a MachineConfig is a rolling reboot. Routine changes
that are instant on an unhardened cluster become scheduled, announced
work once this cluster is in service — which is a fact to hand to
whoever operates it, not a constraint on the build. See
[chapter 10's reboot economics](10-remediation.md#reboot-economics) and,
for the extreme case, [single node](topologies/sno.md#outage-semantics).

**Default-deny networking means every new workload needs a policy.**
Teams deploying to this cluster will hit it and will report it as a
platform fault. That is the control working. Tell them in advance.

**Short token lifetimes mean re-authenticating.** Eight hours
(CNTR-OS-000760) means a daily login, and automation holding a long-lived
token stops working. Service accounts, not user tokens, for anything
automated.

**No kubeadmin means the IdP is on the critical path.** If RHBK is down,
nobody logs in. The break-glass `kubeconfig` is the answer and it has to
be retrievable by someone other than the person who built the cluster.
See [chapter 5](05-first-access.md#the-credentials-the-installer-produced).

**Everything is a transfer window.** Not strictly hardening — that is
the airgap — but it compounds: a remediation requiring an operator that
was not mirrored is a multi-day item, not an afternoon. This is why
[chapter 1's mirror gate](01-intake.md#the-mirror-gate) is a gate.

---

## The controls a scanner cannot see

The ones that fail an assessment despite a clean scan, because they are
not technical:

- The banner's **wording** — a banner is present; is it the mandated
  text?
- Audit **retention** — records forwarded; held for how long, by whom?
- **Who holds cluster-admin** — a group is bound; who is in it, and
  should they be?
- **MFA** — enforced at the IdP, invisible to the cluster.
- **Where the break-glass credential lives** — nothing in the cluster
  can answer this.

[Chapter 11](11-manual-controls.md) covers the first four.
[Chapter 12](12-evidence-pack.md) collects the answers. There is no
command for any of them, which is exactly why they are missed.

---

## Where the benchmark assumes a connected cluster

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Written as **categories to expect**, not as a list of controls. No
> specific check is named, because naming one this repository has not
> run against a profile revision it has not read is exactly the error
> the section above is about. Replace each row with the checks you
> actually see, from your own baseline.

Some benchmark content was written for a cluster with a route to the
internet. On an airgapped build those checks do not fail because the
cluster is insecure; they fail because the thing they are reaching for
is deliberately absent. Each one is a **documented deviation** in
[chapter 12](12-evidence-pack.md), not a failure to fix, and the
difference matters: fixing them means punching a hole in the airgap.

| Category | Why it fails here | What goes in the pack |
|---|---|---|
| **Update source** | the cluster has no upstream channel. [Chapter 6](06-day1-cluster-config.md#the-update-service) covers OSUS, and a cluster with no update service at all has nothing to point at. | the mirror plus the patching process that [chapter 13](13-day2.md) hands back to prep. The control is met by a procedure, not by a field. |
| **Time source** | content that expects a reachable or public NTP source finds the enclave's internal one, or none. [Chapter 3](03-manifests.md#chrony) configures it. | the internal NTP servers, who runs them, and that the nodes are synchronised to them |
| **Telemetry and remote health reporting** | it cannot reach anything. Whether that reads as a pass or a failure depends on which way the check is written, and both exist. | the configuration as installed, and the fact that no outbound path exists regardless |
| **Certificate revocation** | CRL and OCSP responders are external by nature. | how certificates are issued and revoked in the enclave, by whom |
| **Operator catalogue sources** | [chapter 6](06-day1-cluster-config.md#disable-the-default-catalog-sources) disables the default sources by design. A check expecting a Red Hat catalogue finds prep's mirrored one. | `disableAllDefaultSources`, and the mirrored `CatalogSource` that replaces it |
| **Audit log forwarding** | the destination is reachable or it is not, and the check cannot see retention at the far end. | reachability plus the retention answer from [chapter 11](11-manual-controls.md) — see [the controls a scanner cannot see](#the-controls-a-scanner-cannot-see) |
| **Anything that resolves an external name** | the general case of all of the above. | the enclave's DNS policy |

The list you actually need is a by-product of the baseline scan, and
the cheapest moment to produce it is while reading the baseline in
[chapter 9](09-compliance-operator.md) — not later, when the same
results have to be re-read from a file. For each `FAIL` or `ERROR`, one
question: **does this check reach outside the enclave?** If yes, it is
a deviation and it needs a compensating control written while the
result is in front of you.

Expect the answer to be "no" far more often than it feels like it will
be. Most of a hardened baseline is about the cluster's own
configuration and is entirely unaffected by the airgap. The point of
this section is to stop a day being lost to the handful that are not.

---

## FIPS and the benchmark

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The *mechanism* below is reasoned from how `fips: true` works and from
> prep's measured LUKS behaviour. Which specific checks land in which
> category has not been established against any profile revision, and
> that is the part to fill in from your own baseline.

`fips: true` is set once, in [chapter 2](02-install-config.md), and
cannot be changed. The benchmark does not know that. Three things
follow, and the third is the dangerous one.

**Checks FIPS already satisfies.** Much of a cryptographic control
family is decided by the system-wide crypto policy that FIPS mode
imposes — approved modules, approved algorithms, approved cipher
suites, across the platform rather than per-component. These should
pass without any remediation. If one of them fails, that is a real
finding and worth reading carefully rather than remediating, because it
means something is not actually running in the mode you think it is.

**Checks FIPS makes unanswerable.** A check written against a specific
non-approved algorithm has nothing to assert here. It may report an
`ERROR` rather than a `PASS` or a `FAIL` — see
[troubleshooting](troubleshooting.md#a-scan-reports-error-rather-than-pass-or-fail)
— and that `ERROR` is correct.

**Checks FIPS makes *fail*, where the remediation is the wrong move.**
This is the one to be careful about. The worked example this repository
already knows: under FIPS, LUKS2 uses `aes-cbc-essiv:sha256` rather
than the modern default. That is prep's measured behaviour, documented
at [handoff](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#disk-encryption-the-other-decision-made-at-install)
and restated in [chapter 3](03-manifests.md#disk-encryption). Content
written against the default cipher will flag it. The remediation —
change the cipher — is correct against the benchmark, breaks FIPS
compliance, and in this case cannot be applied to an installed node
anyway, because the boot disk's cipher is fixed at provisioning time.

Generalise it into a rule for
[chapter 10's review](10-remediation.md#the-default-review-then-apply):

> **Before applying any remediation that touches cryptography, ask
> whether `fips: true` already decided it.** FIPS is immutable and the
> remediation is not. A remediation that moves the cluster off an
> approved algorithm turns a scan `FAIL` into a `PASS` and the cluster
> out of compliance with the control that mattered more — and nothing
> in the scan output will say so.

That rule costs nothing to apply and is worth stating in the exceptions
register for every crypto-related failure you decline, because "FIPS
already handles this" is an answer an assessor will accept and a blank
is not.

---

## Still missing from this appendix

Honestly, so that the drafts above are not mistaken for a complete
picture:

- **Which checks fall into which category.** Both sections above give
  the shape and not the contents, and the contents are a day's reading
  against a real baseline.
- **Whether the two interact.** A check that is both disconnected-
  hostile and FIPS-affected is the worst case for a reviewer, and
  whether any exist is unknown.
- **What the `rhcos4-stig` and `ocp4-stig` profiles disagree about.**
  They overlap, and a control satisfied at the platform level may still
  be reported against the nodes.
