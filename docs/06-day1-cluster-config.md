# Day-1 cluster config

Applying prep's cluster resources, cutting the cluster off from the
default catalog sources, and proving that what it pulls comes from the
mirror.

This chapter is short and most of it is already written — by prep, in
[prep 08 — after the install completes](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#after-the-install-completes).
It is restated here only to the extent needed to be self-contained.

---

## Apply the cluster resources

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc apply -f ${OCP_INSTALL_ROOT}/handoff/cluster-resources/
```

This directory contains the `ImageDigestMirrorSet` and
`ImageTagMirrorSet` the cluster uses to redirect image references to the
mirror, the `CatalogSource` that makes mirrored operators installable,
and — when prep mirrored with `graph: true`, which is the default — an
`updateService.yaml`.

> **Applying IDMS/ITMS triggers a rolling restart of every node** as the
> machine config operator rewrites the CRI-O configuration. On a
> single-node cluster that is a full API outage of several minutes.
> Expect it; do not interrupt it. See
> [topologies/sno.md](topologies/sno.md).

```sh
# ===== RUN ON: THE CLUSTER =====
oc get machineconfigpool -w
```

Wait for every pool to report `UPDATED=True` and `UPDATING=False` before
doing anything else in this chapter. Stacking a second MachineConfig
change onto a pool that is mid-rollout doubles the outage and makes the
result hard to reason about.

Signature artifacts, if prep generated them, are **files, not a
directory** — oc-mirror 4.21 writes `signature-configmap.{json,yaml}`,
which contradicts some upstream documentation. Check what you actually
received:

```sh
# ===== RUN ON: THE CLUSTER =====
ls -l ${OCP_INSTALL_ROOT}/handoff/cluster-resources/
```

---

## Disable the default catalog sources

```sh
# ===== RUN ON: THE CLUSTER =====
oc patch operatorhub cluster --type merge \
  -p '{"spec":{"disableAllDefaultSources":true}}'
```

The default catalog sources point at `registry.redhat.io` and will fail
indefinitely in a disconnected environment, producing persistent degraded
conditions. Those conditions are not merely cosmetic in an accredited
build: a permanently degraded operator is something an assessor will ask
about, and "that one is always like that" is a bad answer that also
trains the operations team to ignore degraded conditions generally.

Confirm, and confirm that the mirrored catalog survived:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}{"\n"}'
oc get catalogsource -A
oc get packagemanifest -A | head
```

The mirrored `CatalogSource` must still be listed and its pod `READY`. If
`oc get packagemanifest` is empty, nothing is installable and
[chapter 9](09-compliance-operator.md) cannot proceed.

---

## The update service

`cluster-resources/` includes `updateService.yaml` when prep mirrored
with `graph: true`. Applying it creates the OSUS instance; the cluster
then resolves updates against the mirrored graph instead of
`api.openshift.com`, and `oc adm upgrade` lists what is actually
available locally.

The OpenShift Update Service operator must be installed for that resource
to be acted on, so it has to have been in prep's operator list at mirror
time. Without it, upgrades are by digest — see
[13-day2.md](13-day2.md).

> **TODO:** needs validation on real hardware — the end-to-end OSUS path.
> Prep's own validation record notes that its measured run **predates the
> `graph: true` default** and that the OSUS path has not been executed
> there either. Do not describe behaviour neither repository has seen.

---

## Prove pulls come from the mirror

This is the chapter's real deliverable and the first item of evidence
chapter 12 collects. Three questions, and they are genuinely different:

1. **Is the mirror configured?** IDMS/ITMS applied, MCP rolled out. Easy,
   and the one usually mistaken for the whole question.
2. **Do pulls resolve to the mirror?** A reference to `quay.io` in a
   manifest should be served from `registry.airgap.local:8443`.
3. **Is there any outbound attempt at all?** A cluster that pulls
   correctly 99% of the time and reaches for the internet on one image is
   a cluster that will fail at the worst moment.

Question 1:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get imagedigestmirrorset -o yaml
oc get imagetagmirrorset -o yaml
oc get machineconfigpool
```

And on a node, that the MCO actually wrote the CRI-O configuration:

```sh
# ===== RUN ON: A NODE =====
cat /etc/containers/registries.conf.d/*.conf
```

Each mirrored source should appear with its `location` and `mirror`
entries. An empty directory here with an applied IDMS means the MCP
rollout has not reached this node.

> **TODO:** needs validation on real hardware — questions 2 and 3. For
> (2), the check that takes a pod's image reference, resolves it through
> the node's registry configuration and shows which registry actually
> served it. For (3), the evidence that no outbound pull was attempted —
> which in a true airgap is best gathered at the firewall or the node's
> own connection failures rather than inside the cluster.
>
> The honest answer for (3) may be that the cluster cannot prove it
> alone, and the evidence is a firewall log or a packet capture from the
> network team. If so, say that, and make it a 📌 **Handoff** rather than
> a cluster command.

📌 **Handoff** The network team can answer question 3 definitively and
the cluster cannot. Ask them for a record of denied outbound attempts
from the node network during the install window, and keep it. It is
better evidence than anything `oc` will tell you.

---

## What else belongs on day 1

Deliberately *not* here, and why:

| Thing | Where | Why not here |
|---|---|---|
| Identity | [07](07-identity.md) | It has a strict ordering with the `kubeadmin` deletion and deserves its own chapter |
| etcd encryption | [08](08-encryption-at-rest.md) | It is a slow, watchable operation, and doing it alongside an MCP rollout makes both unreadable |
| Compliance Operator | [09](09-compliance-operator.md) | The baseline scan must run against a cluster in its as-installed state, which means after day-1 config and before any remediation |
| Default-deny project template | [03](03-manifests.md) | Should be at the manifest stage. If it could not be, it lands here — see the TODO in chapter 3 |

The ordering of 7, 8 and 9 is not arbitrary. Identity first, because
chapter 9's scans will report on it and because deleting `kubeadmin`
needs doing while someone is still watching. Encryption at rest second,
because it rewrites etcd and you want that finished before anything else
is touched. The baseline scan last of the three, because it should
measure the cluster you intend to have, not a half-configured one.

---

Next: [07-identity.md](07-identity.md).
