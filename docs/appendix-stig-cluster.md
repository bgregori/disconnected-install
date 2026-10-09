# STIG on a cluster

Background, not a procedure. Read it when something in the numbered
chapters looks arbitrary, or when someone asks why a step exists.

Prep has the equivalent for the *hosts* —
[FIPS/STIG on RHEL 9](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md)
— covering `umask`, SELinux, fapolicyd and the `/var/tmp` partition. Those
problems are identical on the install host and are not repeated here.
This appendix is about the cluster.

---

## Three different things called "STIG"

Conflated constantly, and the distinction decides who owns what.

| | What it hardens | Where it is applied | Who owns it |
|---|---|---|---|
| **RHEL 9 STIG** | the install host, the registry host, the IdP host | at OS build, by the platform team | not this repo — see [prep](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md) |
| **`rhcos4-stig`** | the RHCOS nodes | MachineConfigs, at install and after | [ch. 3](03-manifests.md), [ch. 10](10-remediation.md) |
| **`ocp4-stig`** | the OpenShift platform itself | cluster resources | [ch. 6](06-day1-cluster-config.md) through [ch. 11](11-manual-controls.md) |

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

Five, all in [chapter 7](07-identity.md), all about authentication. That
is deliberate and it is the main thing this appendix is here to explain.

Rule IDs look like stable identifiers and are not:

- **They change between benchmark revisions.** A rule renumbered between
  revisions makes a citation wrong without anybody editing anything.
- **They are not the same across profiles.** The identifier in the
  published benchmark, the Compliance Operator's rule object name, and
  the check result name are three different strings for the same
  control.
- **A wrong one survives review.** It looks right, gets copied into the
  SSP, and is found by the assessor — at which point every other
  citation in the document is in question too.

So: cite a rule only after reading it against the revision you are
scanning with, and record the revision alongside. The cost of citing
nothing is a slightly vaguer document. The cost of citing wrongly is the
credibility of the whole pack.

[Chapter 9](09-compliance-operator.md#content-versions-move-independently-of-the-cluster)
has the practical version of this: capture the operator version and the
benchmark revision with every result.

---

## Immutable decisions

The install-time choices that cannot be revisited, collected because
they are scattered through the chapters and the list is what people
want:

| Decision | Set at | Changing it later means |
|---|---|---|
| `fips: true` | [ch. 2](02-install-config.md) | reinstall |
| Boot-disk encryption and mode | [ch. 3](03-manifests.md) | reprovision every node |
| Topology / replica counts | [ch. 2](02-install-config.md) | reinstall |
| Cluster name, base domain | [ch. 2](02-install-config.md) | reinstall |
| Pod and service network CIDRs | [ch. 2](02-install-config.md) | unsupported |

Everything else in this repository is recoverable. These five are the
conversation to have before the build, which is why
[chapter 1](01-intake.md#decide-before-you-install) ends with them and
why prep raises disk encryption at handoff rather than leaving it here.

---

## What hardening costs operationally

Worth knowing before committing, and worth telling whoever will run the
cluster afterwards.

**Reboots become the unit of change.** Most node-level hardening is a
MachineConfig, and a MachineConfig is a rolling reboot. Routine changes
that are instant on an unhardened cluster are change windows here. See
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

## Further TODOs for this appendix

> **TODO:** needs validation on real hardware — a worked list of the
> `ocp4-stig` and `rhcos4-stig` controls that interact badly with a
> *disconnected* cluster specifically: checks that assume an external
> service is reachable, checks that assume an update source, checks that
> assume a public time source. Each of those is a documented deviation
> in [chapter 12](12-evidence-pack.md) rather than a failure to fix, and
> having the list in advance turns a day of confusion into a paragraph.

> **TODO:** needs validation on real hardware — the interaction between
> `fips: true` and the benchmark. Some checks are satisfied by FIPS mode
> and some are made irrelevant by it; knowing which in advance stops
> someone remediating a control that FIPS already handles.
