# Three-node compact

**Deltas only.** The numbered chapters are the procedure; this page lists
what is different on a three-node compact cluster. Read it alongside
them, not instead of them.

The one-sentence version: three control plane nodes that also run
workloads. You keep etcd quorum and rolling changes, which single node
does not have — and you pay for it by having every node be a control
plane node, so every MachineConfig rollout touches the control plane.

---

## Replica counts and topology

A compact cluster is three control plane nodes with workloads scheduled
onto them, rather than three control plane nodes plus workers. How that
is expressed in `install-config.yaml` is not the same as "3 and 0", and
getting it wrong produces a cluster that installs cleanly and refuses to
schedule anything.

> **TODO:** needs validation on real hardware — the `controlPlane` and
> `compute` stanzas for a compact cluster, and whether the schedulability
> of control plane nodes is set in `install-config.yaml`, as a manifest
> in [chapter 3's window](../03-manifests.md), or on day 1. The three
> answers have different consequences for when workloads can first be
> scheduled, and only one of them is right.

---

## VIPs

Unlike [single node](sno.md), the API and ingress VIPs behave normally:
they float between the three nodes. [Chapter 1's
check](../01-intake.md#vips) applies exactly as written — both VIPs must
be unused addresses on the machine network, not DHCP-allocated, and not
already answering.

---

## Outage semantics

Better than single node, and worse than people expect.

| Operation | What happens |
|---|---|
| MachineConfig rollout | nodes cycle **one at a time**; etcd quorum maintained with 2 of 3; brief API disruption as the leader moves |
| Apply IDMS/ITMS ([ch. 6](../06-day1-cluster-config.md)) | one rollout, three sequential reboots |
| etcd encryption ([ch. 8](../08-encryption-at-rest.md)) | API servers roll one at a time; no full outage |
| Compliance remediation batch ([ch. 10](../10-remediation.md)) | one rollout per batch, three reboots per rollout |
| Cluster upgrade ([ch. 13](../13-day2.md)) | rolling |

The thing that surprises people: **workloads have nowhere to go.** With
three nodes and no workers, draining one node for a reboot puts its pods
onto the other two, which are also control plane nodes also under load.
On a cluster sized tightly, a MachineConfig rollout is not just slow —
pods may not reschedule at all, and the drain stalls.

Consequences for [chapter 10](../10-remediation.md):

- **Batching still matters**, for the same reason: the MCO coalesces
  pending MachineConfigs into one rendered config and rolls once. Ten
  remediations applied together is three reboots; applied individually
  it is thirty.
- **Check you have headroom before starting a rollout.** Two nodes must
  be able to carry everything the third was running, plus the control
  plane. If they cannot, the rollout stalls on a drain and you are
  debugging pod disruption budgets during a change window.
- **Watch the pool to completion**, every time, before applying anything
  else:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get machineconfigpool -w
oc get nodes
```

> **TODO:** needs validation on real hardware — measured drain, reboot
> and rejoin time per node on this hardware, and the total for a
> three-node rollout. This is the number a change request needs and the
> number nobody has.

### etcd during a rollout

Three nodes means quorum survives one node being down, and exactly one.
Two practical rules follow:

- **Never start a rollout with a node already unhealthy.** Losing a
  second takes the cluster's API with it. Check `oc get nodes` and etcd
  health first, not after.
- **Do not hurry it.** The MCO waits for a node to rejoin and etcd to be
  healthy before taking the next one. That wait is the thing keeping the
  cluster up.

> **TODO:** needs validation on real hardware — the etcd health check
> worth running before a rollout, and what a degraded-but-quorate etcd
> looks like so it is recognisable.

---

## Storage

Three nodes is the minimum for most replicated storage, which is the
main practical reason to choose compact over single node.

> **TODO:** needs validation on real hardware — which storage provider
> is used, and whether it was mirrored. Like single node, this is a
> [chapter 1 mirror gate](../01-intake.md#the-mirror-gate) item: a
> storage operator absent from prep's `imageset-config.yaml` is a
> transfer window, not an afternoon.
>
> Establish also the interaction with rollouts: replicated storage on
> the same three nodes that are rebooting one at a time has its own
> rebuild behaviour, and a rollout that proceeds faster than storage
> rebuilds is how you lose data with every node individually healthy.

That last point is the one worth validating before anything else on this
page. It is the failure mode unique to compact, and it is not obvious.

---

## Compliance

Both profiles apply unchanged. `rhcos4-stig` scans three nodes rather
than one, so results are per-node and a check can pass on two nodes and
fail on the third.

That is worth stating for the evidence pack: **a profile-level
`COMPLIANT` is not a statement about every node**, and the per-node
results are what [chapter 12](../12-evidence-pack.md) should contain. A
single drifted node is exactly what the File Integrity Operator in
[chapter 13](../13-day2.md) exists to catch.

---

## What does not change

- `fips: true`, disk encryption, etcd encryption, external IdP,
  `kubeadmin` deletion — all identical
- Disk encryption MachineConfigs are still needed for **both** the
  `master` and `worker` pools even though no separate worker nodes
  exist. A worker pool that gains a node later must not gain an
  unencrypted one.
- The mirror registry is still a production dependency
- The evidence pack is the same pack
