# Single node

**Deltas only.** The numbered chapters are the procedure; this page lists
what is different on a single-node cluster. Read it alongside them, not
instead of them.

The one-sentence version: on single node there is no such thing as a
rolling change. Every operation that cycles a node is a full cluster
outage, and several chapters assume otherwise.

---

## Replica counts and topology

One control plane replica, zero compute replicas. The control plane
count is also the number of etcd members, which is part of why it is
immutable — see
[the immutable list](../appendix-stig-cluster.md#immutable-decisions).
`compute.replicas: 0` is not a statement that there are no workloads; it
is what makes the one node schedulable.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 1
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 0
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: <machine-network>/<prefix>
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
```

And the companion file, which is where single node actually differs —
the rendezvous address is the node's own:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/agent-config.yaml =====
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: <cluster-name>          # must match install-config metadata.name
rendezvousIP: <the node's own address>
hosts:
- hostname: <node>
  rootDeviceHints:
    deviceName: /dev/disk/by-id/<stable-id>
```

Three things to check before trusting any of the above:

- **`platform: none: {}`, not `baremetal`.** With `none` the installer
  requires `networkType: OVNKubernetes`, and there is no VIP stanza at
  all — see [collapsed VIPs](#collapsed-vips) below. Confirm which
  platform the agent-based installer accepts for one host in 4.21 before
  generating the ISO; this is validated at `agent create image` time,
  which is after `install-config.yaml` has been consumed and deleted.
- **`bootstrapInPlace.installationDisk` is from the *other* single-node
  flow** — `openshift-install create single-node-ignition-config`, which
  this repository does not use. Carrying it into an agent-based
  `install-config.yaml` is a plausible-looking copy-paste that has to be
  verified rather than assumed, in either direction.
- **`rootDeviceHints` by `/dev/disk/by-id/`, not `/dev/sda`.** On a
  multi-disk node the kernel's enumeration order is not stable across
  boots, and installing RHCOS to the wrong disk on single node is a
  reinstall of the cluster. See
  [02-install-config.md](../02-install-config.md#agent-configyaml).

Chapter 2 defers topology to this page; this page is drafted from
documentation, so when you install, bring the two back into agreement.

---

## Collapsed VIPs

On a multi-node cluster the API and ingress VIPs float between nodes.
With one node there is nowhere for them to float to, and the
configuration is correspondingly different.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

The expected answer is that **there are no VIPs to declare.** With
`platform: none: {}` there is no `apiVIPs`/`ingressVIPs` stanza, and the
installer is documented to reject one for a single-host cluster —
there is no second node for keepalived to fail a VIP over to, so the
node's own address *is* the API address and the ingress address.
Everything that would be a VIP elsewhere resolves to that one address.

This changes [chapter 1's VIP check](../01-intake.md#vips) rather than
removing it, and getting the direction wrong sends someone chasing a
non-problem. Drafted, the single-node form of that check is:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: A NODE =====
ping -c2 <node-address>          # must NOT answer before install
dig +short api.<cluster>.<base-domain>        # must be <node-address>
dig +short api-int.<cluster>.<base-domain>    # must be <node-address>
dig +short test.apps.<cluster>.<base-domain>  # must be <node-address>
```

So the "must not answer" rule survives, but it applies to the **node
address** rather than to two separate VIPs: before the install nothing
may be holding it, and after the install it answers because it is the
node. An address that answers beforehand is a duplicate-IP incident
waiting for the node to boot.

Verify first whether `api-int.` is genuinely required here — it is on a
multi-node agent-based install, and there is no reason to think single
node is exempt, but "no reason to think" is why this is a draft.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

The sequence as documented, which is what you are trying to match
against the screen in front of you:

1. The node boots the agent ISO into a live RHCOS environment. It is
   also the **rendezvous host**, because `rendezvousIP` is its own
   address, so it runs the assisted service itself.
2. The assisted service validates the host, then writes RHCOS to the
   disk named by `rootDeviceHints`.
3. The node reboots into the installed system. **This is the pivot.**
   Everything that was running in the live environment is gone, and the
   installed system starts forming the control plane.
4. The node reboots again at least once more as the control plane
   settles and MachineConfigs are applied. More than one reboot is
   normal and is not a retry.

Watch it from the install host, not from the console, and let it run:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
openshift-install-fips --dir ${OCP_INSTALL_ROOT}/cluster \
  agent wait-for bootstrap-complete --log-level=debug

openshift-install-fips --dir ${OCP_INSTALL_ROOT}/cluster \
  agent wait-for install-complete --log-level=debug
```

**"Has it hung" is the question, and the honest answer is that you
cannot tell from the install host alone.** `wait-for` losing its
connection across the pivot reboot looks identical to a node that never
came back. The distinguishing evidence is on the node:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE INSTALL HOST =====
ssh core@<node-address> 'sudo podman logs -f assisted-service'
ssh core@<node-address> journalctl -b -f -u bootkube.service
ssh core@<node-address> agent-gather -O > agent-gather.tar.xz
```

Read it as: **before** the pivot, the assisted service logs are the
whole story — discovery, validation, and the release-image pull that is
the usual disconnected failure. **After** the pivot, the assisted
service is gone and `bootkube` is the story. Asking for the wrong one
and getting nothing is not a hang.

`agent-gather` is the support bundle, and the one thing worth running
*before* you start deleting anything. Uncertain and worth confirming:
whether `agent-gather` is present on the installed system or only in
the live environment, because on single node those are the same host at
different times and the answer decides whether a post-pivot failure can
be gathered at all.

Do not intervene at the pivot. On single node the reboot takes the only
API server with it, so every tool you would reach for is unavailable by
design for several minutes, and a node power-cycled impatiently
mid-pivot is a reinstall.

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

### etcd is one member

There is no quorum to lose and nothing to fail over to. Where
[compact](compact.md#etcd-during-a-rollout) checks etcd health *before*
a rollout because losing a second member is fatal, single node has no
equivalent check worth running — the member is either there or the
cluster is down and you are not reading `oc` output.

What replaces it is a backup. A single-member etcd means a corrupted or
lost member is a restore, not a replacement, so take one before every
outage in the table above.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE CLUSTER =====
oc debug node/<node> -- chroot /host \
  /usr/local/bin/cluster-backup.sh /home/core/assets/backup
```

Then get the resulting snapshot and static-pod resources **off the
node** — a backup that only exists on the one machine you are about to
reboot is not a backup. Confirm the script path and the asset layout on
4.21 before relying on this; it has moved between releases, and the
`oc debug` form above is the part most likely to be wrong.

---

## Storage

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

**Replicated storage is not an option here, so do not mirror it.** ODF
wants three nodes in three failure domains; there is one node and one
failure domain. The two providers that make sense on single node are
local:

| Provider | What it gives you |
|---|---|
| **LVM Storage** (`lvms-operator`) | dynamic provisioning from a volume group on the node's own disks. The usual choice for single node. |
| **Local Storage Operator** | static `PersistentVolume`s from whole devices. Simpler, no dynamic provisioning. |

Either one is a [chapter 1 mirror gate](../01-intake.md#the-mirror-gate)
item, decided before the cluster is built: it is an operator, it comes
from the mirror, and an operator that is not in prep's
`imageset-config.yaml` is a transfer window rather than an afternoon.
It is not in chapter 1's table today because the table lists only what
this repository itself needs — add your storage operator to it.

What to establish on the real build, because the draft above cannot:

- Which provider is installed, and whether it was actually mirrored —
  verified in the registry, not read off a config file.
- Whether the operator's shipped version matches this cluster version.
  Storage operators are versioned with the cluster and prep must have
  mirrored a compatible one.
- Which disks it is allowed to consume, and that none of them is the
  RHCOS installation disk from `rootDeviceHints`.

And then write down the sentence that actually matters, which no
topology diagram will say for you:

> **The failure domain is the whole cluster.** There is one copy of the
> data, on one node, and nothing in the platform replicates it. Backup
> and restore is the only availability story single node has, and
> whoever runs this cluster afterwards needs to be told so in writing.

---

## Compliance

All three profiles still apply. `rhcos4-stig` scans one node, which makes it
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
