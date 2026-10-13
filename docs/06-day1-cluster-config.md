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
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> This one is weaker than most of the drafts in this repository and you
> should treat it accordingly. Prep's measured run **predates the
> `graph: true` default**, so neither repository has seen an OSUS
> instance come up against a mirrored graph. What follows is the
> documented shape of the procedure plus the two trust failures that
> every disconnected write-up reports; none of it has been observed
> here. The parts most likely to be wrong are the CA wiring and the
> exact `status` field names.

First confirm the operator is actually installed, because applying an
`UpdateService` to a cluster without its controller succeeds, reports
nothing, and does nothing:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get csv -n openshift-update-service
oc get crd updateservices.updateservice.operator.openshift.io
```

If the CRD is absent, the operator was not in prep's mirror. Stop —
that is a content gap and it goes back across the airgap. Do not
install it from anywhere else.

Read what prep generated before applying it. The `graphDataImage` is
pinned by digest, and that digest changes every time prep re-mirrors:

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc apply -f ${OCP_INSTALL_ROOT}/handoff/cluster-resources/updateService.yaml
oc -n openshift-update-service get updateservice
oc -n openshift-update-service get pods
```

Each `updateservice-*` pod runs two containers — the graph builder and
the policy engine. The graph builder's log is where a working instance
announces itself; a builder that cannot reach the registry sits there
looking healthy from the outside.

```sh
# ===== RUN ON: THE CLUSTER =====
oc -n openshift-update-service logs -l app=updateservice -c graph-builder --tail=50
```

Then point the cluster version operator at the local policy engine
instead of `api.openshift.com`:

```sh
# ===== RUN ON: THE CLUSTER =====
OSUS_NAME=$(oc -n openshift-update-service get updateservice \
  -o jsonpath='{.items[0].metadata.name}')
OSUS_GRAPH="$(oc -n openshift-update-service get updateservice "${OSUS_NAME}" \
  -o jsonpath='{.status.policyEngineURI}')/api/upgrades_info/v1/graph"
echo "${OSUS_GRAPH}"
oc patch clusterversion version --type merge \
  -p "{\"spec\":{\"upstream\":\"${OSUS_GRAPH}\"}}"
```

Echo the URI before patching. An empty `policyEngineURI` produces a
patch that sets `upstream` to a bare path, and the resulting CVO error
blames the graph rather than the variable.

The proof is that `oc adm upgrade` lists something:

```sh
# ===== RUN ON: THE CLUSTER =====
oc adm upgrade
oc get clusterversion version -o jsonpath='{.spec.upstream}{"\n"}'
```

**Two separate CA problems, and they fail at different layers.** Both
are reported by everyone who has done this disconnected, and neither is
obvious from the error:

1. **OSUS to the mirror registry.** The `UpdateService` status reports
   something like `RegistryCACertFound` / `NotConfigured`, complaining
   that `image.config.openshift.io` has no `additionalTrustedCA`. The
   fix is a `ConfigMap` in `openshift-config` referenced from
   `image.config.openshift.io/cluster` under `spec.additionalTrustedCA`
   — and its key is the registry's hostname with the colon before the
   port replaced by **two periods**, because a colon is not usable in a
   `ConfigMap` key. `registry.airgap.local:8443` becomes
   `registry.airgap.local..8443`. Verify that spelling against the 4.21
   documentation before typing it; it is exactly the sort of detail that
   changes.
2. **The CVO to the OSUS route.** Presents as `RemoteFailed` on
   `oc adm upgrade` with `x509: certificate signed by unknown
   authority` naming the policy-engine route. This is the cluster's own
   ingress certificate, not the mirror's, and it is a different
   `ConfigMap` in a different place.

📌 **Handoff** The graph data image is pinned by digest, so it goes
stale the moment prep re-mirrors. Whoever owns the Day-2 delta loop owns
re-applying `updateService.yaml` with the new digest — see
[13-day2.md](13-day2.md). A cluster whose OSUS silently serves last
quarter's graph looks healthy and offers no upgrades.

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

Question 2. The distinction that makes this answerable is between
`.image` and `.imageID` on a container status: `.image` is what the
manifest asked for, `.imageID` is what the kubelet resolved and pulled.
A cluster where every `.image` says `quay.io` and every `.imageID` says
the mirror is a cluster where IDMS is working exactly as intended.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The `.imageID` reasoning is the part to check first. Confirm against a
> running cluster that CRI-O populates `.imageID` with the registry that
> actually served the layer rather than echoing the requested reference
> — if it echoes, this check reports success wrongly, which is worse
> than no check at all. Verify it by deliberately reading a pod you know
> was mirror-served before trusting the aggregate.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get pods -A -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}' \
  | sort -u
```

Every line should begin with the mirror registry. The useful form is
the inverse — list only what does not:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get pods -A -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}' \
  | sort -u | grep -v '^registry.airgap.local:8443/'
```

Empty output is the pass, and it is the line worth capturing for
chapter 12. Substitute your own mirror hostname; the literal above is
prep's example and is not yours.

Cross-check from the node, where the container runtime's own view is
authoritative and the API server's is secondhand:

```sh
# ===== RUN ON: A NODE =====
sudo crictl images --digests
sudo crictl inspecti $(sudo crictl images -q | head -1) | head -40
```

`crictl inspecti` shows `repoDigests`, which is the reference as the
runtime holds it. Also confirm the runtime config the MCO wrote
actually enforces digest-only mirroring rather than merely offering the
mirror as a first preference:

```sh
# ===== RUN ON: A NODE =====
grep -A4 -E '^\[\[registry' /etc/containers/registries.conf.d/*.conf
sudo crio config 2>/dev/null | grep -iE 'default_runtime|registries|insecure'
```

Each mirror entry written from an IDMS should carry
`pull-from-mirror = "digest-only"`. An ITMS entry will not, by
definition — that is what the tag variant is for — which is why
`imageDigestSources` and `imageTagMirrorSet` are worth distinguishing
in the evidence rather than lumping together.

Question 3. The cluster can produce supporting evidence but it cannot
produce proof, and it is worth being clear about which you are holding.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Uncertain: whether CRI-O logs a *failed* outbound attempt in a form
> that greps cleanly, and whether the journal retention on a freshly
> installed node reaches back to the install window at all. Check
> `journalctl --disk-usage` and the oldest entry before concluding that
> an empty result means anything.

```sh
# ===== RUN ON: A NODE =====
sudo journalctl -u crio --no-pager --since "$(date -d '-1 day' '+%Y-%m-%d')" \
  | grep -iE 'quay\.io|registry\.redhat\.io|registry\.access\.redhat\.com|cdn\.redhat\.com|sso\.redhat\.com' \
  | tail -40
sudo journalctl -u kubelet --no-pager | grep -iE 'ErrImagePull|ImagePullBackOff' | tail -20
```

Empty output is consistent with no outbound attempt. It is not the same
as proof of no outbound attempt: a DNS lookup that failed before CRI-O
logged anything leaves nothing here, and so does a journal that has
already rotated. Say that in the evidence pack rather than letting an
empty grep stand as a finding.

The cluster-side result to record is therefore: *no node logged an
attempt to reach an external registry during the observed window*, with
the window stated. That is an honest sentence. "No node attempted an
outbound pull" is not one, and the next section is why.

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
