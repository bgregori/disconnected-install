# Manifests before ignition

There is a window in the install process — after manifests are generated,
before ignition configs are — in which you can add resources that will be
baked into the node images. Three things in a hardened build have to
happen in that window, and all three are expensive or impossible to add
afterwards.

This is the highest-stakes chapter in the repository and the one with the
fewest commands, because the window is easy to describe and the contents
are not.

---

## The window

```
<the stage that consumes install-config.yaml>
        │
        ├── manifests generated
        │
        │   ◄── YOU ARE HERE. Drop files into:
        │         <install-dir>/manifests/    cluster-scoped config
        │         <install-dir>/openshift/    MachineConfigs
        │
        └── ignition configs generated ─────► ISO
                                              nothing added after this point
                                              reaches a node at first boot
```

> **TODO:** needs validation on real hardware — the exact agent-based
> installer subcommands that open and close this window, and whether the
> agent workflow separates `create manifests` from `create
> image` in the same way `create cluster` separates `create manifests`
> from `create ignition-configs`. Prep's
> [handoff chapter](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#disk-encryption-the-other-decision-made-at-install)
> states only that disk encryption is "a `MachineConfig` placed in
> `<install_dir>/openshift/` before the ignition configs are generated".
> That is the requirement; the command sequence that produces the window
> in the **agent** workflow specifically has not been run here and is not
> guessed at.
>
> Establish and record: the command that stops after manifests, the
> directory layout it leaves, the command that resumes, and what happens
> if a file is dropped into `manifests/` that belongs in `openshift/`.

Two rules that hold regardless:

- **Both directories get wiped by a re-run.** `openshift-install` deletes
  and regenerates the install directory contents. Keep your
  MachineConfigs in a source directory outside it and copy them in, every
  time. Editing them in place and then re-running is how a node boots
  unencrypted.
- **The ISO is the boundary.** After ignition, the only route to node
  configuration is the Machine Config Operator, which means a rolling
  reboot — and for disk encryption, not even that.

Keep the source files somewhere durable:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/manifests-src
```

---

## Disk encryption

The requirement: the root filesystem of every node is LUKS2-encrypted,
unlocked without a human typing a passphrase at boot, and unlockable
**only** under the conditions the accreditation specifies.

The failure mode it prevents is the obvious one and is not about
attackers in the building: it is a disk leaving the enclave — RMA, decom,
theft of a whole chassis — carrying etcd, which carries every secret in
the cluster. Encryption at rest inside the cluster
([chapter 8](08-encryption-at-rest.md)) does not help if the disk itself
is readable.

A cluster installed without it **has to be reprovisioned to get it**. For
an accredited build that usually means reinstalling after the finding,
which is why prep raises it at handoff rather than leaving it here.

Two modes, and they answer different questions:

| Mode | Unlocks when | Enclave precondition |
|---|---|---|
| **TPM v2** | the disk is still in its original machine | a TPM 2.0 device, enabled in firmware — and on virtual nodes, a vTPM attached to the guest |
| **Tang / NBDE** | the node can reach the Tang servers | one or more Tang servers reachable **on the node network**, and their thumbprints |

Both can be combined with a `threshold`, which is what you want when the
requirement is "decrypts only in this rack, on this network". Note that
the two fail in opposite directions: TPM alone means a disk moved to
another chassis is useless, but a node whose motherboard is replaced will
not boot. Tang alone means a node that loses the network will not boot,
but a stolen disk is useless anywhere off that network. Which of those is
the acceptable failure is a site decision, not a technical one.

> **FIPS changes the cipher.** With `fips: true` the LUKS2 volume uses
> `aes-cbc-essiv:sha256`. That is expected, not a misconfiguration, and it
> is worth writing into the evidence pack before an assessor asks why it
> is not the modern default.

> **TODO:** needs validation on real hardware — the `MachineConfig`
> content itself, for `master` and for `worker`, in both TPM v2 and Tang
> modes, and the `threshold` form that combines them. This is the single
> most dangerous thing in this repository to guess at: a MachineConfig
> that is syntactically valid and semantically wrong produces nodes that
> boot fine and are not encrypted the way you believe, and nobody finds
> out until the assessor asks for `cryptsetup status`.
>
> Also establish: whether the boot partition is covered or only root;
> whether anything must be done to `/boot`; and the Tang thumbprint
> rotation story, since a Tang server rebuild with new keys bricks every
> node that depends on it.

### Tang, if you are using it

Tang is infrastructure, not content — nothing here needs mirroring, no
extra images, no change to prep's ImageSetConfiguration. But a Tang
server that does not exist yet is a blocker discovered at install time,
on the wrong side of the airgap.

📌 **Handoff** Tang servers are a cluster dependency with the same
standing as the mirror registry. If they go away, nodes do not boot. They
need the same backup, patching and change control, and whoever owns them
needs to know that.

### Verify afterwards

From a debug shell, once nodes are up:

```sh
# ===== RUN ON: A NODE =====
lsblk --fs                    # root partition shows crypto_LUKS
cryptsetup status root        # type: LUKS2
```

Capture this output per node. Chapter 12 wants it.

---

## Default-deny NetworkPolicy project template

The requirement: a newly created project denies all ingress by default,
so that a workload is reachable only where someone has written a policy
saying so.

The failure mode it prevents: OpenShift's default is that every pod in
every namespace can reach every other pod. In a hardened build that is a
finding on its own, but the operational version of the problem is worse —
it means the security posture of the cluster degrades every time anybody
creates a project, silently, with no event and nothing to review.

This is done by replacing the **project template**, so that the
`NetworkPolicy` objects are created as part of project creation rather
than bolted on afterwards. Doing it at the manifest stage rather than on
day 1 means there is never a window in which a project was created
without them.

> **TODO:** needs validation on real hardware — the project template
> resource, where it belongs in the manifest directory, and the exact
> `NetworkPolicy` set. At minimum the set needs to deny all ingress while
> still permitting the ingress controller to reach routed workloads and
> permitting the monitoring stack to scrape; a template that denies
> everything breaks both, and the breakage looks like an ingress problem
> rather than a policy one.
>
> Establish: whether this can be delivered as a manifest at install time
> at all, or whether it must be a day-1 patch to the
> `project.config.openshift.io/cluster` resource. If the latter, move
> this section to [06-day1-cluster-config.md](06-day1-cluster-config.md)
> and say so here.

> ⚠️ **STIG** Whichever way it lands, the control is about *new* projects.
> Projects created before the template is in place keep the old
> behaviour. If this ends up as a day-1 step, chapter 12 must record which
> namespaces predate it — `openshift-*` namespaces always will.

---

## Chrony

The requirement: every node synchronises time against the enclave's NTP
source, from first boot, without ever attempting to reach a public pool.

The failure mode it prevents is the one chapter 1 flagged: certificate
validation fails on skew, and the symptom is TLS errors that say nothing
about time. At install time it is worse than that, because a node whose
clock is wrong may fail to join at all, and the bootstrap log will tell
you about certificates.

Why it belongs in this window rather than on day 1: the nodes need
working time *during* bootstrap, which is before there is a cluster to
apply a MachineConfig to.

> **TODO:** needs validation on real hardware — the chrony
> `MachineConfig` for `master` and `worker`: the `chrony.conf` content,
> how it is encoded into the MachineConfig, and the path it lands at. The
> encoding is the part that is easy to get subtly wrong and that fails
> quietly, leaving the default configuration in place and the node
> pointing at an unreachable pool.
>
> Establish also whether the agent-based installer offers a supported
> route for this that does not require a hand-written MachineConfig.

Verify afterwards:

```sh
# ===== RUN ON: A NODE =====
chronyc sources
chronyc tracking
```

`chronyc sources` must list your enclave source and nothing else. A `^?`
against a public pool address means the default configuration survived.

---

## Before you close the window

- [ ] Source manifests live outside the install directory, and were
      copied in — not edited in place
- [ ] Disk encryption MachineConfig present for **every** pool that will
      exist, `master` and `worker`, not just `master`
- [ ] If Tang: thumbprints are the ones from the servers that are actually
      deployed, and those servers are reachable from the node network
      *now*
- [ ] Chrony MachineConfig present, pointing at the enclave source
- [ ] Project template handled, or explicitly deferred to chapter 6 with
      a note
- [ ] A copy of everything in this directory is archived for chapter 12 —
      these files are evidence

---

Next: [04-agent-iso.md](04-agent-iso.md).
