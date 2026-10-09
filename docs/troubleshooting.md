# Troubleshooting

Organised by the symptom you are seeing.

For failures on the **install host itself** — a binary that will not
execute, SELinux labels, fapolicyd, `umask` — the answers are in prep's
[FIPS/STIG appendix](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md).
They are host problems, they are identical on this host, and they are not
duplicated here.

> This file is a skeleton. The sections below are the failures worth
> expecting; most of their contents have not been written because they
> have not been seen. A troubleshooting guide assembled from guesses is
> worse than an empty one — it sends people down paths that do not exist.

---

## First moves

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperators
oc get clusterversion
oc get nodes
oc get events -A --sort-by=.lastTimestamp | tail -50
oc get machineconfigpool
```

`oc get clusteroperators` first, every time. The degraded operator's
message is usually specific and usually ignored in favour of guessing.

```sh
# ===== RUN ON: THE CLUSTER =====
oc describe clusteroperator <name>
oc logs -n <namespace> deploy/<operator> --tail=100
```

---

## The install

### The agent install hangs with no error

The signature disconnected failure. A pull is reaching for an address
that does not exist on this network, and the timeout is long enough to
look like progress.

First question: **does anything in the logs name `quay.io` or
`registry.redhat.io`?** If so, `imageDigestSources` was incomplete. The
specific and common cause is copying only the **first** YAML document
out of prep's generated IDMS — it contains one `ImageDigestMirrorSet`
for the release images and one per operator source, and the first alone
gives you a cluster that can pull the platform and not the operators.

See [prep 08 — building `imageDigestSources` by
hand](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#building-imagedigestsources-by-hand).
Count the entries:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
grep -c '^\s*- mirrors:' ${OCP_INSTALL_ROOT}/handoff/cluster-resources/idms-oc-mirror.yaml
grep -c '^- mirrors:'    ${OCP_INSTALL_ROOT}/install-config.yaml.bak
```

Second question: **does the registry resolve and answer from the node
network?** Not from the install host — from the node network. This is
[chapter 1's check](01-intake.md#registry-reachable-from-the-node-network)
and the reason it is in chapter 1.

> **TODO:** needs validation on real hardware — where the agent-based
> installer leaves its logs before the cluster API exists, and the
> specific log lines that distinguish "reaching for the internet" from
> "reaching the mirror and failing".

### x509 errors naming the registry

The CA did not reach the nodes. Three causes, in order of frequency:

1. `additionalTrustBundlePolicy: Always` was omitted. Without it the
   bundle may only be applied to proxy connections rather than to
   registry pulls.
2. The pasted certificate lost its two-space indentation under the
   literal block.
3. The certificate is for a different name than the one in
   `imageDigestSources` — a short hostname, or the wrong domain. Check
   the `subjectAltName`:

```sh
# ===== RUN ON: A NODE =====
openssl s_client -connect registry.airgap.local:8443 \
  -servername registry.airgap.local </dev/null 2>/dev/null |
  openssl x509 -noout -subject -ext subjectAltName
```

### Authentication errors pulling from the mirror

The key in the pull secret must match the registry reference **exactly,
port included**. `registry.airgap.local` and
`registry.airgap.local:8443` are different keys.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
jq -r '.auths | keys[]' ${OCP_INSTALL_ROOT}/handoff/pull-secret.json
```

### The installer binary will not run

fapolicyd or SELinux, on the install host. Relabel first, then trust:

```sh
# ===== RUN ON: THE INSTALL HOST =====
sudo restorecon -v /usr/local/bin/openshift-install-fips /usr/local/bin/oc
sudo fapolicyd-cli --file add /usr/local/bin/openshift-install-fips
sudo fapolicyd-cli --file add /usr/local/bin/oc
sudo fapolicyd-cli --update
```

The trust database is per-host. Prep doing this on the registry host did
nothing for this one. Background in prep's
[FIPS/STIG appendix](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md#fapolicyd-blocks-binaries-you-just-installed).

### Nodes do not boot at all after installation

If NBDE is in use, the first suspect is Tang. A node that cannot reach
its Tang servers cannot unlock its root filesystem and does not come up
— there is no degraded mode. Check the Tang servers are reachable **from
the node network** and that their keys have not been rotated.

> **TODO:** needs validation on real hardware — what a Tang unlock
> failure looks like on the console, and the recovery path. This is the
> worst failure in the repository and the one most worth having
> rehearsed.

---

## Cluster operators

### An operator is permanently degraded after `disableAllDefaultSources`

Expected for the default catalog sources; not expected for prep's
mirrored `CatalogSource`. Check the mirrored source survived:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get catalogsource -A
oc get packagemanifest -A | head
```

An empty `packagemanifest` list means nothing is installable and
[chapter 9](09-compliance-operator.md) cannot proceed.

### A node shows no mirror configuration

```sh
# ===== RUN ON: A NODE =====
cat /etc/containers/registries.conf.d/*.conf
```

Empty, with an IDMS applied, means the MachineConfig rollout has not
reached this node. Watch the pool rather than re-applying:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get machineconfigpool -w
```

---

## Identity

### Nobody can log in after configuring the IdP

Check the operator before the login page, which tells you nothing:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator authentication
oc describe clusteroperator authentication
```

> **TODO:** needs validation on real hardware — the authentication
> operator's messages for the common misconfigurations: wrong secret
> key, missing CA, unreachable issuer, wrong client ID. These are
> distinguishable and the messages are the fastest route to the cause.

### Login works but nobody has any permissions

The `groups` claim. Keycloak does not emit group membership by default,
so the cluster authenticates the user and learns nothing about them.
This presents as an RBAC problem and is not one. See
[chapter 7, step 3](07-identity.md#step-3--the-oauth-cr).

Check what the cluster thinks the user is:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get users
oc get groups
oc auth can-i '*' '*' --all-namespaces --as=<user>
```

An empty `oc get groups` after a successful login is the signature.

### Nobody can log in and kubeadmin is gone

The situation [chapter 7's gate](07-identity.md#the-gate) exists to
prevent. The break-glass `kubeconfig` from
[chapter 5](05-first-access.md#the-credentials-the-installer-produced)
is the only route back, which is why its storage location is recorded
before `kubeadmin` is deleted.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
export KUBECONFIG=${OCP_INSTALL_ROOT}/cluster/auth/kubeconfig
oc whoami      # system:admin
```

If that file is also gone, the recovery involves physical access to a
control plane node. Do not get here.

---

## Compliance

### A `Subscription` sits in `InstallPlanPending`

The content is not in the mirror, or only partly. This is
[chapter 1's mirror gate](01-intake.md#the-mirror-gate) failing late.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get subscription -A
oc describe subscription <name> -n <namespace>
oc get installplan -A
```

The fix is a prep Day-2 delta — a transfer window. See
[13-day2.md](13-day2.md).

### A scan reports `ERROR` rather than `PASS` or `FAIL`

The check could not run. An `ERROR` is not a `PASS` and quietly becomes
one in a summary count if nobody looks.

> **TODO:** needs validation on real hardware — the common causes of
> `ERROR` results on `ocp4-stig` and `rhcos4-stig`, and how to read the
> scanner pod logs for one.

### A scan never finishes

> **TODO:** needs validation on real hardware — normal scan duration on
> this hardware, per profile and per node count. Without a measured
> normal, "it has been twenty minutes" is unanswerable, and the usual
> response — deleting the scan and starting again — hides the cause.

### Results changed with no cluster change

The Compliance Operator was updated, and the benchmark content came with
it. See [chapter 9 on content
versions](09-compliance-operator.md#content-versions-move-independently-of-the-cluster).
This is not a regression and must not be reported as one — but it does
need the before and after content versions, which is why chapter 9
captures them alongside every result.

---

## Diagnostics

`must-gather` is the first thing asked for by support and the first
thing that does not work in a disconnected cluster, because its default
image reference points at `registry.redhat.io`.

> **TODO:** needs validation on real hardware — the working
> `oc adm must-gather --image=...` form against prep's mirror. Prep
> established that mirrored operator images are digest-referenced rather
> than tagged, so the obvious tagged reference fails against a healthy
> mirror. Work out the correct form **before** you need it.
