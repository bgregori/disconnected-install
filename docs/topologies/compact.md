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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

A compact cluster is **three and zero**, not three and three:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 3
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 0
platform:
  baremetal:
    apiVIPs:
    - <api-vip>
    ingressVIPs:
    - <ingress-vip>
```

`compute.replicas: 0` is the switch. It does not mean "no workloads" —
it is the documented way of saying "the control plane nodes are also
the worker nodes", and the installer reads it that way. "3 and 3"
describes six machines, three of which you do not have, and is the
configuration that installs cleanly and refuses to schedule anything.

**Where schedulability is set is the part to verify.** The installer is
documented to set it for you, by writing `mastersSchedulable: true`
into the generated scheduler manifest — but that is documented for
installer-provisioned infrastructure, and the user-provisioned
procedure tells you to check the manifest by hand. The agent-based
installer sits between the two and this repository has not established
which behaviour it has. So check, during
[chapter 3's window](../03-manifests.md#the-window), while it is still
a file you can edit:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
grep -n 'mastersSchedulable' \
  ${OCP_INSTALL_ROOT}/cluster/manifests/cluster-scheduler-02-config.yml
```

It must read `mastersSchedulable: true`. If it reads `false`, set it
there — in the manifest window, before ignition — rather than planning
to fix it on day 1.

The day-1 check, for the same fact after the cluster exists:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get scheduler cluster -o jsonpath='{.spec.mastersSchedulable}{"\n"}'
oc get nodes -o wide --show-labels
```

Every node should carry both the `master` and `worker` role labels.
Three nodes showing `master` alone, with `mastersSchedulable: false`,
is the failure this section exists to prevent — and it is recoverable
on day 1, unlike the replica counts themselves.

Also confirm, before `agent create image` consumes the file: the VIP
keys are the **plural list forms** `apiVIPs:` and `ingressVIPs:`. The
singular `apiVIP:`/`ingressVIP:` are the deprecated spelling and are
what most older examples on the internet still show.

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

### `maxUnavailable` on the master pool

One knob governs how many nodes the MCO takes at once, and on compact
the default is the only safe value.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get machineconfigpool master \
  -o jsonpath='{.spec.maxUnavailable}{"\n"}'
```

An empty result means unset, which means the default of **1**. Leave it
there. Raising it to 2 on a three-node cluster takes two of three etcd
members down together and loses quorum — the cluster does not degrade,
it stops. There is no three-node setting faster than 1 that is also
safe, so the only reason to touch this field is to confirm nobody else
has.

### Measuring the rollout

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

The numbers below are deliberately absent, because inventing them is
worse than not having them: a change request built on a guessed reboot
time is a change window that overruns. What is drafted here is the
*method* for getting them on the first real rollout, which is the one
chance you have to measure an empty cluster.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get machineconfigpool master -w     # MACHINECOUNT / UPDATEDMACHINECOUNT
oc get nodes -w                        # Ready / NotReady / SchedulingDisabled
```

Run them in two terminals, with timestamps. `oc get mcp` already prints
`UPDATED`, `UPDATING`, `DEGRADED` and the three machine counts, so no
custom columns are needed — the per-node detail you are timing comes
from the second watch.

Record four timestamps per node, from the first rollout you run:

| Mark | Taken when |
|---|---|
| drain start | the node goes `SchedulingDisabled` |
| reboot start | the node goes `NotReady` |
| rejoin | the node returns `Ready` |
| node done | `updatedMachineCount` increments |

Three nodes × (drain + reboot + rejoin), plus the MCO's wait for etcd
between nodes, is the figure to put in the change request. Measure it
on the IDMS/ITMS rollout in
[chapter 6](../06-day1-cluster-config.md) — it is the first real
three-node rollout this cluster will do, it has to happen anyway, and
nothing is running on the cluster yet to confuse the timings.

Then measure it **again** under load before quoting it for a
remediation batch. A drain on an empty cluster and a drain on a loaded
one are not the same operation, which is the point of the paragraph
above.

### etcd during a rollout

Three nodes means quorum survives one node being down, and exactly one.
Two practical rules follow:

- **Never start a rollout with a node already unhealthy.** Losing a
  second takes the cluster's API with it. Check `oc get nodes` and etcd
  health first, not after.
- **Do not hurry it.** The MCO waits for a node to rejoin and etcd to be
  healthy before taking the next one. That wait is the thing keeping the
  cluster up.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

The pre-rollout gate, cheapest check first:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator etcd
oc get pods -n openshift-etcd -l app=etcd -o wide
oc get etcd cluster -o jsonpath=\
'{range .status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}{end}'
```

Then, only if the above is not conclusive, ask etcd itself:

```sh
# ===== RUN ON: THE CLUSTER =====
ETCD_POD=$(oc get pods -n openshift-etcd -l app=etcd \
  -o jsonpath='{.items[0].metadata.name}')

oc exec -n openshift-etcd ${ETCD_POD} -c etcdctl -- \
  etcdctl endpoint health --cluster -w table
oc exec -n openshift-etcd ${ETCD_POD} -c etcdctl -- \
  etcdctl endpoint status --cluster -w table
```

Note the location marker: these run **on the cluster**, through the
API, not in a node debug shell. `etcdctl` exists inside the etcd pod
and the `etcdctl` container already holds the certificates — running
`etcdctl` from a node debug shell is a different command with different
credentials and is not what this check is.

Three things to know when reading the output:

- **`etcdctl member list` is not a health check.** A dead member is
  still a member and still listed. `endpoint health` is the one that
  reports `false`.
- **Degraded-but-quorate looks like two healthy endpoints and one
  missing or erroring**, with the cluster still fully serving. This is
  the state in which a rollout must **not** be started: the next node
  the MCO takes is the second one, and that is quorum.
- **Revision alignment matters as much as health.** If `oc describe
  etcd cluster` shows members at different revisions, a static-pod
  rollout is still in flight. Starting a MachineConfig rollout on top
  of it stacks two reboot cycles.

What to establish on the real cluster, because reading the healthy
output is easy and reading the broken output is the skill: capture the
output of all of the above **while one node is deliberately down**,
during the first rollout, when the cluster is still empty and you can
afford to look. That transcript is worth more than this section.

---

## Storage

Three nodes is the minimum for most replicated storage, which is the
main practical reason to choose compact over single node.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

ODF is supported on a three-node compact cluster — Red Hat documents
it, three nodes is its minimum, and it is the main reason to choose
this topology over [single node](sno.md#storage). The caveats are real
and all of them bite harder at three nodes than at any other size:

- **The published resource figures are for ODF alone.** They exclude
  the control plane, which on compact is on the same three machines.
  Size for ODF *plus* etcd, the API servers, the controllers, ingress
  and your workload, on every node. Nodes sized from the ODF table
  alone are undersized here by the whole control plane.
- **Losing one node costs a third of the storage and an etcd member at
  the same time.** Everywhere else those are two separate incidents.
- **Each node needs its own raw, pristine devices** — no leftover
  partitions, PVs, VGs or LVs — and not the RHCOS installation disk.
- **The minimal/degraded deployment mode is not the one to pick** for
  anything that has to survive an assessment. Converting it later is
  more work than sizing it correctly now.
- **If you only need object storage**, the Multicloud Object Gateway
  alone is a far smaller footprint than a full internal-mode cluster,
  and on three converged nodes that difference is the difference.

Like single node, this is a
[chapter 1 mirror gate](../01-intake.md#the-mirror-gate) item: ODF is
several operators and a large set of images, and one absent from
prep's `imageset-config.yaml` is a transfer window, not an afternoon.
Add it to chapter 1's table — it is not there today, because that
table lists only what this repository itself needs.

### Rollouts and storage rebuild

This is the failure mode unique to compact, and the one to validate
before anything else on this page.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

Replicated storage on the same three nodes that are rebooting one at a
time has its own rebuild behaviour, and **the MCO does not know about
it.** The MCO waits for a node to be `Ready` and for etcd to be
healthy. It does not wait for Ceph to finish backfilling. A rollout
that proceeds faster than storage rebuilds takes the next node while
the data that was on the last one is still only partly replaced — and
every node is individually healthy the whole time.

So the pre-rollout gate on compact is **two** checks, not one: etcd,
from the section above, and storage. Drafted:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get storagecluster -n openshift-storage
oc get cephcluster -n openshift-storage \
  -o jsonpath='{.items[0].status.ceph.health}{"\n"}'
```

`HEALTH_OK` before you start, and `HEALTH_OK` again between nodes. A
rollout held at `HEALTH_WARN` while a rebuild finishes is a slow change
window; one that is not held is a data-loss incident with a clean
`oc get nodes`.

What to establish on the real cluster: whether the MCO can be made to
wait — a pod disruption budget on the storage pods is the obvious
candidate, since the drain respects PDBs and the MCO respects the drain
— or whether the only answer is a human watching `oc get mcp` with a
finger on the pause button:

```sh
# ===== RUN ON: THE CLUSTER =====
oc patch machineconfigpool master --type=merge \
  -p '{"spec":{"paused":true}}'       # and false to resume
```

Pausing the master pool mid-rollout is itself worth rehearsing before
you need it, and worth un-pausing deliberately: a pool left paused
silently stops receiving every later MachineConfig, including the
remediations in [chapter 10](../10-remediation.md), and reports nothing
wrong while doing it.

---

## Compliance

All three profiles apply unchanged. `rhcos4-stig` scans three nodes rather
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
- Disk encryption still wants `enableOn: all`, not `masters`, even
  though every node is a control-plane node today. A worker pool that
  gains a node later must not gain an unencrypted one, and `masters` is
  the plausible-looking answer that lets it.
- The mirror registry is still a production dependency
- The evidence pack is the same pack
