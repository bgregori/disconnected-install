# install-config.yaml

The file that decides what the cluster permanently is. Four of its fields
cannot be changed afterwards at any price, and three of those four are the
ones a disconnected, FIPS, hardened build exists for.

Prep hands over a fragment containing the disconnected parts already
built. This chapter is about assembling the whole file around it and
checking it before it is consumed — because `openshift-install` **deletes
`install-config.yaml`** when it generates manifests, and a mistake found
afterwards means starting from your own copy, if you kept one.

Throughout this repository the **install directory** is
`${OCP_INSTALL_ROOT}/cluster`, and `install-config.yaml` is written inside
it. Every `--dir` argument from here on points there.

> **Keep a copy outside the install directory before you run anything.**
> This is not optional housekeeping; it is the difference between editing
> one line and retyping the file. The install directory is the thing the
> installer consumes and rewrites; a copy kept inside it is a copy you
> will lose.
>
> Create the directory now:
>
> ```sh
> # ===== RUN ON: THE INSTALL HOST =====
> : "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
> mkdir -p ${OCP_INSTALL_ROOT}/cluster
> ```
>
> Then, **once you have finished authoring the file** — which is the end
> of this chapter, not the start — take the copy:
>
> ```sh
> # ===== RUN ON: THE INSTALL HOST =====
> : "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
> cp ${OCP_INSTALL_ROOT}/cluster/install-config.yaml \
>    ${OCP_INSTALL_ROOT}/install-config.yaml.bak
> chmod 600 ${OCP_INSTALL_ROOT}/install-config.yaml.bak
> ```
>
> It is `0600` because the file contains the mirror pull secret.
>
> The two halves are separate because the file does not exist yet. Run
> them in one go on a fresh install root and the `cp` fails on a missing
> source — and because `cp`'s failure is not fatal to the shell, the
> `chmod` then fails too and you carry on believing you have a backup.

---

## The three disconnected requirements

A disconnected install needs all three. Missing any one fails closed, and
the errors are not self-explanatory. These come straight from prep's
handoff fragment:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
fips: true

imageDigestSources:
- mirrors:
  - registry.airgap.local:8443/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - registry.airgap.local:8443/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - registry.airgap.local:8443/compliance
  source: registry.redhat.io/compliance

additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  ...
additionalTrustBundlePolicy: Always
```

**`imageDigestSources` is the one that gets forgotten.** Without it the
agent ISO attempts to reach `quay.io` during bootstrap. On an airgapped
network that means the install *hangs* rather than failing cleanly, and
the bootstrap logs do not make the cause obvious.

Take **every** list item from **every** `imageDigestMirrors:` block in
prep's generated IDMS — the file contains more than one YAML document, one
for the release images and one per operator source, and copying only the
first gives you a cluster that can pull the platform but not the
operators. Prep documents the transformation and a paste-ready one-liner
at
[prep 08 — building `imageDigestSources` by hand](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#building-imagedigestsources-by-hand).

Count them, on this host, after pasting:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
grep -c '^\s*- mirrors:' ${OCP_INSTALL_ROOT}/handoff/cluster-resources/idms-oc-mirror.yaml
grep -c '^- mirrors:'    ${OCP_INSTALL_ROOT}/cluster/install-config.yaml
```

The two numbers must match. This check exists because prep's own generator
shipped an empty `imageDigestSources` block once, and nothing downstream
noticed.

`additionalTrustBundlePolicy: Always` matters for `platform: none` —
without it the bundle may only be applied to proxy connections rather than
to registry pulls.

### `fips: true`

Set here, immutable afterwards. Two things follow from it that are easy to
treat as problems:

- **The installer binary must be `openshift-install-fips`,** extracted
  from your own registry. Chapter 1 installed it.
- **The host running it must itself be in FIPS mode.** Chapter 1 checked
  it.
- **LUKS2 uses `aes-cbc-essiv:sha256`** rather than the default. That is
  expected under FIPS, not a misconfiguration — see
  [03-manifests.md](03-manifests.md).

---

## Topology

Replica counts are install-time and define the cluster's shape.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The replica counts below are documented and uncontroversial. The
> `platform:` pairing is the part to check: single node is documented as
> requiring `platform: none`, and a three-node compact cluster that wants
> managed VIPs needs `platform: baremetal`, but *which* of those your
> site's load balancing actually wants is a decision nobody here has
> made against real network equipment. The difference is not cosmetic —
> `platform: none` means you supply the load balancer and the VIPs are
> never mentioned in this file at all.

| Topology | `controlPlane.replicas` | `compute.replicas` | `platform:` |
|---|---|---|---|
| Single node | 1 | 0 | `none: {}` |
| Three-node compact | 3 | 0 | `baremetal` with VIPs, or `none` with an external LB |
| Multi-node | 3 | 2 or more | `baremetal` with VIPs, or `none` with an external LB |

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
controlPlane:
  name: master
  replicas: 3
  architecture: amd64
  hyperthreading: Enabled
compute:
- name: worker
  replicas: 0
  architecture: amd64
  hyperthreading: Enabled
platform:
  baremetal:
    apiVIPs:
    - 10.20.30.5
    ingressVIPs:
    - 10.20.30.6
```

`compute.replicas: 0` is what makes a three-node cluster *compact* —
the control plane nodes become schedulable and carry workloads. It is
not the same cluster as "3 control plane, 3 compute on the same
machines", which is not a thing the installer builds. The `compute`
stanza must still be present with `replicas: 0`; deleting it is not the
same as zeroing it.

`apiVIPs` and `ingressVIPs` are **lists** (plural, since 4.12). The
singular `apiVIP`/`ingressVIP` forms still parse in some versions and
are the kind of thing a copied example carries in silently.

> ⚠️ **STIG** `architecture: amd64` is stated explicitly rather than
> left to default, because the evidence pack has to say what was built
> and "whatever the installer chose" is not an answer. Prep mirrored
> `amd64` only; another value here means content that is not in the
> registry.

Topology-specific notes live in [topologies/sno.md](topologies/sno.md)
and [topologies/compact.md](topologies/compact.md). Both now carry
drafted `install-config.yaml` stanzas of their own, written independently
of this section — so where they disagree with it, that disagreement is
unresolved rather than deliberate. Read the topology page alongside this
one and reconcile the two before you commit to either.

---

## Networking

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The field names and defaults below are documented. The CIDRs are
> **examples and must not be copied** — they are the installer defaults,
> which is exactly why they collide with things. What has not been
> observed here is what the installer reports when the VIPs sit outside
> `machineNetwork`, or when `clusterNetwork` overlaps it; the claim below
> that the first is caught and the second is not is reasoned, not seen.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
networking:
  networkType: OVNKubernetes
  machineNetwork:
  - cidr: 10.20.30.0/24
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
```

Four things, each with a different failure:

- **`networkType: OVNKubernetes`.** The only supported value on 4.21.
  State it rather than defaulting it, because the evidence pack has to
  name the CNI.
- **`machineNetwork` must contain every node address and both VIPs.**
  The VIPs are declared in the `platform:` stanza above, not here, and
  the two have to agree. A VIP outside `machineNetwork` is the one error
  in this section expected to be caught at install.
- **`clusterNetwork` is the pod network, and `hostPrefix` carves it per
  node.** `/23` is 510 usable pod addresses per node. A `/14` with
  `hostPrefix: 23` gives you 512 nodes' worth. Raising `hostPrefix`
  later is not a thing.
- **`serviceNetwork` is the one that bites quietly.** It is never
  routed, never ARPs, and never announces itself, so a collision with
  something already routed in the enclave is invisible at install. It
  presents months later as one specific service unreachable from one
  specific subnet, and by then the cluster cannot be changed.

Check both the pod and service ranges against the enclave's address
plan — including ranges that exist only in a disaster-recovery site —
before anyone types them.

```sh
# ===== RUN ON: A NODE =====
ip route get 172.30.0.1    # must be unreachable / no route
ip route get 10.128.0.1    # must be unreachable / no route
```

A route that resolves to a real next hop means the range is in use.
This check cannot be run from the install host: the question is what a
node's routing table says, and the install host's says nothing about
it.

What is worth deciding before anyone writes YAML, because it needs the
network team:

- **The machine network must contain the node addresses and both VIPs.**
- **The pod and service networks must not collide with anything routed in
  the enclave**, including networks that exist only in a disaster-recovery
  site. These are not changeable after install.
- **Egress.** The cluster needs the mirror registry, the NTP source and —
  new in this repo — the external IdP. Chapter 7's issuer URL is an
  outbound path from the cluster that nobody asked the firewall team
  about, because identity usually arrives before the firewall rules do.

📌 **Handoff** Give the network team the full list in one message: mirror
registry, NTP, IdP issuer, Tang servers if NBDE is in use, and the audit
log destination from [11-manual-controls.md](11-manual-controls.md). Five
separate requests over three weeks is how an install slips.

---

## The pull secret

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
pullSecret: '{"auths":{"registry.airgap.local:8443":{"auth":"..."}}}'
```

This is the **mirror** pull secret from the handoff bundle, not a Red Hat
pull secret. Prep deliberately does not carry a Red Hat pull secret across
the airgap, and the cluster has nothing to use it for.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
echo "pullSecret: '$(cat ${OCP_INSTALL_ROOT}/handoff/pull-secret.json)'"
```

The key in the auth file must match the registry reference in
`imageDigestSources` **exactly, port included**:
`registry.airgap.local` and `registry.airgap.local:8443` are different
keys, and the mismatch fails as a credentials error.

---

## SSH key

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/install-config.yaml =====
sshKey: 'ssh-ed25519 AAAA...'
```

This is how you reach a node that will not join, and the agent-based
installer offers no other route once the ISO is built. Omitting it is a
decision you make once and regret during the one incident where it
matters.

> ⚠️ **STIG** SSH access to nodes is itself auditable. A hardened build
> typically requires that the key belong to a named individual, that
> access be logged, and that the route be documented rather than
> discovered. Decide whose key goes in, and record it — chapter 12 asks
> for this.

---

## Validate before you consume it

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> There is no non-destructive validation subcommand. What there appears
> to be is a *cheaper* destructive one — `agent create
> cluster-manifests` validates and consumes, but consumes a throwaway
> copy if you give it one. Whether its validation covers everything
> `agent create image` checks has not been established, so a clean run
> here is evidence of nothing worse than a schema error.

Validate against a scratch copy of the directory, never the real one.
Both files have to exist first — `agent-config.yaml` is the next
section, so this is the last thing in the chapter you run, not the
next one:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
rm -rf ${OCP_INSTALL_ROOT}/validate
mkdir -p ${OCP_INSTALL_ROOT}/validate
cp ${OCP_INSTALL_ROOT}/cluster/install-config.yaml \
   ${OCP_INSTALL_ROOT}/cluster/agent-config.yaml \
   ${OCP_INSTALL_ROOT}/validate/

openshift-install-fips agent create cluster-manifests \
  --dir ${OCP_INSTALL_ROOT}/validate --log-level=info
```

The scratch directory is now burnt — both input files are gone from it.
That is the point: it absorbed the destruction instead of
`${OCP_INSTALL_ROOT}/cluster`. Read what it produced, then delete it:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
ls -l ${OCP_INSTALL_ROOT}/validate/cluster-manifests/
rm -rf ${OCP_INSTALL_ROOT}/validate
```

`openshift-install-fips explain installconfig.<field>` answers schema
questions without touching anything, and is the right tool for "does
this field still exist in 4.21".

The checklist below is not replaced by any of this. Run it every time.

By eye, every time:

- [ ] `fips: true` present
- [ ] `imageDigestSources` entry count matches the IDMS
- [ ] `additionalTrustBundle` is the registry CA, indented two spaces under
      the literal block, with no trailing blank line inside the block
- [ ] `additionalTrustBundlePolicy: Always`
- [ ] `pullSecret` is the mirror secret, key matches the registry
      reference including port
- [ ] `sshKey` present and attributable to a person
- [ ] cluster name and base domain match the DNS records verified in
      chapter 1
- [ ] replica counts match the topology you intend

---

## `agent-config.yaml`

The agent-based installer takes a second file alongside this one, carrying
per-host facts: addresses, interfaces, roles, and which disk to install
to. It is not covered here because nothing in it is specific to being
disconnected or hardened — but it is required, and it is where static
addressing and the `rootDeviceHints` that stop RHCOS installing to the
wrong disk are declared.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The schema below is documented; the values are not yours. The two
> fields worth real suspicion are `rootDeviceHints` on multi-disk nodes
> — because `deviceName` is the hint most likely to be wrong and the
> only one whose being wrong destroys data — and the NMState block,
> which is accepted or rejected wholesale with error messages that name
> the NMState schema rather than the field you mistyped.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/agent-config.yaml =====
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: <cluster-name>        # must equal install-config metadata.name
rendezvousIP: 10.20.30.11
additionalNTPSources:
- 10.20.30.2                  # the enclave source, never a public pool
hosts:
- hostname: master-0
  role: master
  interfaces:
  - name: eno1
    macAddress: 00:11:22:33:44:55
  rootDeviceHints:
    wwn: "0x60014051..."
  networkConfig:
    interfaces:
    - name: eno1
      type: ethernet
      state: up
      mac-address: 00:11:22:33:44:55
      ipv4:
        enabled: true
        dhcp: false
        address:
        - ip: 10.20.30.11
          prefix-length: 24
      ipv6:
        enabled: false
    dns-resolver:
      config:
        server:
        - 10.20.30.3
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.20.30.1
        next-hop-interface: eno1
        table-id: 254
```

What each of these is actually protecting you from:

- **`metadata.name` must equal the cluster name in
  `install-config.yaml`.** A mismatch is not a naming inconvenience; the
  two files stop describing the same cluster.
- **`rendezvousIP` must be a control plane node's address.** It picks
  which node runs the assisted service and bootstraps. Pointing it at a
  worker is a configuration the installer rejects, and pointing it at
  an address nothing will ever hold is a boot that hangs with every
  node waiting for a host that never appears.
- **`macAddress` is the join key.** Every node boots the *same* ISO and
  identifies itself by MAC. A typo does not fail — that node simply
  gets no configuration and falls back to DHCP, which on a statically
  addressed enclave means no address at all.
- **`rootDeviceHints` on a multi-disk node.** Prefer `wwn` over
  `deviceName`: `/dev/sda` is not stable across boots or across
  identical chassis, and the cost of the installer picking the wrong
  disk is that it wipes it. Get the `wwn` from `udevadm info` on the
  host; if it reports `ID_WWN_WITH_EXTENSION`, that is the value to
  use.
- **`additionalNTPSources`.** Chapter 1 recorded the enclave NTP
  addresses for this. It covers the nodes during discovery and
  bootstrap; chapter 3's chrony MachineConfig covers them afterwards.
  Both are needed and neither substitutes for the other.

```sh
# ===== RUN ON: A NODE =====
udevadm info --query=property --name=/dev/sda | grep -E '^ID_WWN'
lsblk -o NAME,SIZE,WWN,MODEL,SERIAL
```

Run this on the machine that will become the node, not on the install
host. Disk ordering is per-chassis and the install host's is irrelevant.

See [04-agent-iso.md](04-agent-iso.md) for what consumes this file.

---

Next: [03-manifests.md](03-manifests.md) — the window between manifests
and ignition, which is where disk encryption and the default-deny network
policy have to happen.
