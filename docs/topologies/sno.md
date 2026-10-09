# Single node

**Deltas only.** The numbered chapters are the procedure; this page lists
what is different on a single-node cluster. Read it alongside them, not
instead of them.

The one-sentence version: on single node there is no such thing as a
rolling change. Every operation that cycles a node is a full cluster
outage, and several chapters assume otherwise.

---

## Replica counts and topology

> **TODO:** needs validation on real hardware — the `install-config.yaml`
> stanza for single node: control plane and compute replica counts, and
> whether anything else in the file changes shape. Chapter 2 defers
> topology to this page and this page has not been written against a real
> install.

---

## Collapsed VIPs

On a multi-node cluster the API and ingress VIPs float between nodes.
With one node there is nowhere for them to float to, and the
configuration is correspondingly different.

> **TODO:** needs validation on real hardware — whether API and ingress
> VIPs are declared at all for single node, and if so what they must be
> relative to the node's own address. Chapter 1 has you verify that the
> VIPs are unused before install; on single node that check may not apply
> in the same form, and saying so wrongly would send someone chasing a
> non-problem.

Whatever the answer, DNS is still required. `api.<cluster>.<base-domain>`
and `*.apps.<cluster>.<base-domain>` must resolve from the node network
on a single-node cluster exactly as on any other — a frequent assumption
is that one node means no DNS, and it does not.

---

## Bootstrap-in-place

A multi-node install uses a temporary bootstrap node that is discarded
once the control plane is up. With one node there is nowhere to put it,
so the installer bootstraps *on the node itself* and then pivots it into
being the cluster.

Operationally this means the node reboots as part of installation, and
that reboot is a normal step rather than a fault. Watching a single-node
install and intervening at the pivot is a classic way to turn a working
install into a broken one.

> **TODO:** needs validation on real hardware — what the bootstrap-in-
> place sequence looks like from the outside: the reboot, its timing, and
> what the installer reports on either side of it. The question actually
> asked at that moment is "has it hung", and answering it requires having
> watched one.

---

## Outage semantics

This is the section that matters most, because three chapters contain
operations that are routine elsewhere and are outages here.

| Operation | Multi-node | Single node |
|---|---|---|
| Apply IDMS/ITMS ([ch. 6](../06-day1-cluster-config.md)) | rolling, no API outage | **full API outage, several minutes** |
| Any MachineConfig change ([ch. 3](../03-manifests.md), [ch. 10](../10-remediation.md)) | one node at a time | **full outage per rollout** |
| Enable etcd encryption ([ch. 8](../08-encryption-at-rest.md)) | API servers roll one at a time | **full API outage** |
| Compliance remediation batch ([ch. 10](../10-remediation.md)) | N × drain+reboot, workloads reschedule | **one outage if batched, one per remediation if not** |
| Cluster upgrade ([ch. 13](../13-day2.md)) | rolling | **full outage** |

Prep already warns about the first row at handoff: *"applying IDMS/ITMS
triggers a rolling restart of every node… on a single-node cluster that
is a full API outage of several minutes."*

Three consequences for how the chapters are run:

- **Batch aggressively.** [Chapter 10's reboot
  economics](../10-remediation.md#reboot-economics) apply with full
  force: the MCO coalesces pending MachineConfigs into one rendered
  config and rolls once, so reviewing fifty remediations and applying
  them together costs one outage. Applying them as you review costs
  fifty.
- **Sequence the chapters into windows, not into an afternoon.** Day-1
  config, etcd encryption and the first remediation batch are three
  outages minimum, and they must not overlap — never start one while a
  pool is mid-rollout.
- **There is no workload continuity story.** Anything running on this
  cluster stops during each of these. If that is unacceptable, the
  topology is wrong, and that is a conversation to have before the
  install rather than during the first patch cycle.

---

## Storage

> **TODO:** needs validation on real hardware — the storage story for
> single node. There is no multi-node replication to rely on, so the
> default assumptions of most storage operators do not hold, and
> whichever local storage provider is used has to be in prep's mirror —
> which makes it a [chapter 1 mirror gate](../01-intake.md#the-mirror-gate)
> item, decided before the cluster is built.
>
> Establish: what is installed, whether it was mirrored, and what the
> failure domain actually is. The honest statement for single node is
> usually that the failure domain is the whole cluster, and writing that
> down is more useful than a storage topology diagram.

---

## Compliance

Both profiles still apply. `rhcos4-stig` scans one node, which makes it
faster and makes the remediation reboots more expensive — the inverse of
the usual trade.

Nothing in [chapter 9](../09-compliance-operator.md) or
[chapter 11](../11-manual-controls.md) changes. [Chapter
10](../10-remediation.md) changes only in that batching stops being good
practice and becomes mandatory.

---

## What does not change

Worth saying, because single node invites the assumption that the rules
are relaxed:

- DNS for `api.` and `*.apps.` is still required
- `fips: true`, disk encryption, etcd encryption, external IdP,
  `kubeadmin` deletion — all identical
- The mirror registry is still a production dependency
- The evidence pack is the same pack
