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
> ```sh
> # ===== RUN ON: THE INSTALL HOST =====
> : "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
> mkdir -p ${OCP_INSTALL_ROOT}/cluster
> cp ${OCP_INSTALL_ROOT}/cluster/install-config.yaml \
>    ${OCP_INSTALL_ROOT}/install-config.yaml.bak
> chmod 600 ${OCP_INSTALL_ROOT}/install-config.yaml.bak
> ```
>
> It is `0600` because the file contains the mirror pull secret.

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

> **TODO:** needs validation on real hardware — the `controlPlane` and
> `compute` stanzas for each supported topology, and which `platform:`
> stanza the agent-based installer requires alongside them. The values
> differ between single node, three-node compact and multi-node in more
> than just the replica count, and a three-node compact cluster that is
> configured as "3 control plane, 0 compute" behaves differently from one
> configured as "3 control plane, 3 compute on the same machines". Write
> this only once each has been installed.
>
> Topology-specific notes live in [topologies/sno.md](topologies/sno.md)
> and [topologies/compact.md](topologies/compact.md); both are currently
> deltas-to-be-written against this section.

---

## Networking

> **TODO:** needs validation on real hardware — the `networking` stanza:
> `machineNetwork`, `clusterNetwork`, `serviceNetwork`, `networkType`, and
> where the API and ingress VIPs are declared for an agent-based install
> on bare metal. Chapter 1 verified that the VIPs are unused; this section
> must say where they go and what the installer does when they overlap the
> machine network badly.
>
> State the failure mode for each: a `serviceNetwork` that collides with
> something already routed on the enclave is not detected at install and
> presents months later as one specific service being unreachable from one
> specific subnet.

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

> **TODO:** needs validation on real hardware — whether
> `openshift-install-fips agent create ...` performs a schema validation
> pass that can be run non-destructively, and if so how. The question that
> matters is whether there is any way to check this file *without*
> consuming it, since the consuming command deletes it.
>
> Until that is answered, the procedure is: keep the `.bak` copy made at
> the top of this chapter, and check by eye against the list below.

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

> **TODO:** needs validation on real hardware — the `agent-config.yaml`
> fields this build actually needs, in particular `rootDeviceHints` on
> multi-disk nodes and the NMState `networkConfig` form for static
> addressing. See [04-agent-iso.md](04-agent-iso.md).

---

Next: [03-manifests.md](03-manifests.md) — the window between manifests
and ignition, which is where disk encryption and the default-deny network
policy have to happen.
