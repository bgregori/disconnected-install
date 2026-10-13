# Troubleshooting

Organised by the symptom you are seeing.

For failures on the **install host itself** — a binary that will not
execute, SELinux labels, fapolicyd, `umask` — the answers are in prep's
[FIPS/STIG appendix](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md).
They are host problems, they are identical on this host, and they are not
duplicated here.

> Most of this file is drafted, not validated. The sections below are
> the failures worth expecting; the ones carried from prep have been
> seen, and the cluster-side ones are marked
> 🚧 **DRAFT -- NOT VALIDATED** at the point of use. A troubleshooting
> guide read as fact when it was assembled from documentation is worse
> than an empty one — it sends people down paths that do not exist, at
> the moment they are least able to tell. Check the marker before you
> trust a command here, and replace the block once you have run it.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

**Before the cluster API exists there is no `oc`, and the logs are not
on the install host.** They are on the rendezvous host — the node whose
address is `rendezvousIP` in `agent-config.yaml`. Everything below runs
over `ssh` as `core`, using the key from
[`sshKey`](02-install-config.md#ssh-key), which is the reason that
field is not optional.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
openshift-install-fips --dir ${OCP_INSTALL_ROOT}/cluster \
  agent wait-for bootstrap-complete --log-level=debug
```

```sh
# ===== RUN ON: THE INSTALL HOST =====
ssh core@<rendezvous-ip> 'sudo podman logs assisted-service'
ssh core@<rendezvous-ip> journalctl -b -u bootkube.service
ssh core@<rendezvous-ip> agent-gather -O > agent-gather.tar.xz
```

Which one to read depends on how far it got, and asking for the wrong
one returns nothing in a way that looks like a second fault:

| Phase | Where the story is |
|---|---|
| Hosts never appear / validation fails | `assisted-service`, a **podman container**, not a systemd unit |
| Hosts appear, install never triggers | `assisted-service` — a failed validation, usually the release-image pull |
| Install triggered, control plane never forms | `bootkube.service`, via `journalctl` |

**Distinguishing "reaching for the internet" from "reaching the mirror
and failing"** is the question this section exists for, and the two
look alike at a glance because both end in a pull that did not happen:

| In the log | Means |
|---|---|
| `quay.io` or `registry.redhat.io` named in a pull error | `imageDigestSources` is incomplete — the cluster does not know to redirect. Go back to the IDMS document count above. |
| a long stall with no error at all | an outbound connection with nowhere to go, timing out. Same cause as the row above. |
| `no such host` for the mirror's name | DNS, from the node network. [Chapter 1](01-intake.md#dns). |
| connection refused / timeout to the mirror's address | routing or firewall, not the registry. |
| `x509` naming the mirror | the CA. See the next section. |
| `401` on an **image pull** | the pull secret key does not match the registry reference, port included. Note this is the opposite of a `401` from `/v2/`, which is the pass. |
| `404` or `manifest unknown` on a digest | the image was never mirrored. This is the mirror gate failing late, and the answer is a [prep Day-2 delta](13-day2.md), never "pull it". |

Run `agent-gather` **before** you start deleting things. It is the
support bundle and it cannot be collected retrospectively.

Still to establish on a real install: whether `agent-gather` survives
onto the installed system or exists only in the live environment, and
the exact wording the 4.21 assisted service uses for a release-image
pull failure — the table above describes the *class* of each message
and not its text.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **This is the worst failure in the repository.** A wrong guess here
> ends in a reprovisioned node or a lost cluster, so treat every line
> below as a hypothesis to rehearse in a lab, not a recovery procedure
> to follow live.

On the console, expect the boot to stop in the initramfs, before any
cluster component exists — Clevis is unlocking the root filesystem, so
there is nothing else running yet. The shape to look for is a
`clevis-luks-askpass` unit waiting, or a passphrase prompt for the LUKS
device, repeating or hanging rather than failing outright. There is no
degraded mode and no timeout into one: an unlocked node boots, a locked
node waits.

**The node is almost never the problem.** Three causes, in order:

1. **Tang is unreachable from the node network.** The commonest, the
   least alarming, and the one that looks exactly like the other two.
   Check from a host on the node network, not from the install host.
2. **Tang's keys were rotated** and the node still carries a binding to
   the old advertisement. The node was fine yesterday and nothing on it
   changed.
3. **Tang's key material is gone** — the server was rebuilt, or
   restored without `/var/db/tang`. This is the unrecoverable one.

```sh
# ===== RUN ON: A NODE =====
curl -sS http://<tang-server>:<port>/adv | head -c 200; echo
```

A JSON advertisement is the pass. No answer is cause 1; an
advertisement whose keys do not match what the node was bound to is
cause 2.

The recovery path, drafted and unproven:

- **Cause 1: fix the network or the Tang service.** Do not touch the
  node. It will unlock on the next boot once Tang answers. Resist
  reinstalling the node, which is the instinct and which destroys the
  evidence.
- **Cause 2: rebind.** The binding lives on the node's LUKS header and
  has to be updated against the new advertisement, which needs the disk
  open — so it is done *before* the rotation, from a running node, not
  after a failed boot. Rotating Tang keys without rebinding every node
  first is a scheduled outage that nobody scheduled.
- **Cause 3: there is no recovery.** Restore the Tang server from
  backup, or reprovision the node. This is why Tang's key material is a
  tier-0 backup and the single-node case is a whole-cluster loss.

📌 **Handoff** Tang is a production dependency of every node in this
cluster, owned by whoever runs that host and probably unaware of it.
They need to know three things: that rotating keys requires the cluster
to rebind first, that `/var/db/tang` must be backed up, and that taking
the server down takes every node that reboots during the window with
it. Record this with the rest of the handoff facts in
[chapter 12](12-evidence-pack.md).

Rehearse this one. Power-cycle a node with Tang deliberately blocked,
on a cluster nobody needs, and capture the console. That transcript is
the only version of this section worth having.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

Three places to look, in this order. Each tells you something the
previous one cannot:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator authentication
oc describe clusteroperator authentication

oc logs -n openshift-authentication-operator \
  deploy/authentication-operator --tail=100

oc get pods -n openshift-authentication
oc logs -n openshift-authentication deploy/oauth-openshift --tail=100
```

The operator's `Degraded` message tells you whether it could *build* a
valid configuration. The `oauth-openshift` pod's log tells you what
happened when a real login was attempted. A misconfiguration that the
operator accepts and the IdP rejects only appears in the second.

What the four common causes are expected to look like — stated as
behaviour rather than as message text, because the text is exactly what
has not been verified:

| Cause | Where it shows | Shape of it |
|---|---|---|
| Wrong key name in the client-secret `Secret` | operator `Degraded` | the operator cannot find the key it was told to read; it names the secret and the key. Fails before any login is attempted. |
| CA `ConfigMap` missing or wrong | operator `Degraded`, and `oauth-openshift` | a TLS verification failure against the issuer URL. On a hardened, disconnected build this is the likeliest of the four. |
| Issuer URL unreachable | operator `Degraded` | a connection failure, not a TLS one — and usually the firewall, because the cluster's outbound path to the IdP is the rule nobody requested. See [chapter 2 on egress](02-install-config.md#networking). |
| Wrong client ID | **not** the operator — the login attempt | the operator is content; the IdP returns an error to the browser. You will not find this in `oc get co`. |

Two operational facts that save time regardless of cause:

- **Every change to the `OAuth` CR redeploys the `oauth-openshift`
  pods.** The operator goes `Progressing` and logins fail during the
  rollout. Wait for `Available=True, Progressing=False` before
  concluding the change did not work.
- **A `Degraded` authentication operator is not the same as a broken
  login**, and vice versa. Check both ends before changing anything —
  fixing a problem you do not have on top of one you do is how an hour
  becomes a day.

> ⚠️ Do not debug this after `kubeadmin` is deleted if you can avoid
> it. [Chapter 7's gate](07-identity.md#the-gate) exists so that this
> section is a nuisance rather than an incident.

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
[13-day2.md](13-day2.md). **Never "pull it".** There is nothing to pull
from, and an attempt to work around this is an attempt to work around
the airgap.

Before you conclude that, check what the cluster can see, because
"partly mirrored" and "not mirrored" look the same from the
`Subscription`:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get packagemanifest -A | grep -i <operator>
oc get catalogsource -A
```

Two traps when confirming the content against the registry directly,
both carried from prep and both already known to waste an afternoon:

- **Quay's `_catalog` endpoint rejects basic auth.** An empty or
  failing `_catalog` listing is not evidence that the mirror is empty.
  Query a specific repository instead.
- **Mirrored images are digest-referenced, not tagged.** `oc image info
  <repo>:latest` failing against this registry is the healthy result.
  Resolve the digest and ask for that.

### A scan reports `ERROR` rather than `PASS` or `FAIL`

The check could not run. An `ERROR` is not a `PASS` and quietly becomes
one in a summary count if nobody looks.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

Find them first. They are labelled, so you do not have to grep YAML:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -n openshift-compliance \
  -l compliance.openshift.io/check-status=ERROR

oc get compliancecheckresult -n openshift-compliance \
  -l compliance.openshift.io/check-status=INCONSISTENT
```

`INCONSISTENT` is the second status worth knowing about and is not an
`ERROR`: it means the check ran everywhere and **disagreed between
nodes**. On [compact](topologies/compact.md#compliance) that is a real
finding about one node, not a scanner fault, and it is annotated with
the per-node results. On [single node](topologies/sno.md) it cannot
occur.

Then read the scanner pod for the scan the check belongs to. The pods
are labelled by scan name and by the job they were doing:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get pods -n openshift-compliance \
  -l compliance.openshift.io/scan-name=<scan>

oc logs -n openshift-compliance <scanner-pod> -c scanner
```

The `workload` label separates the scanner pods from the aggregator
(which turns raw results into `ComplianceCheckResult` objects) and the
profileparser (which turns the datastream into profiles and rules). An
`ERROR` on one check is a scanner problem; no results at all is an
aggregator or profileparser problem, and they are different logs.

Causes to work through, in order of how often they are expected:

1. **A leftover helper pod holding the results volume.** The scan PVC
   is `ReadWriteOnce` and can be mounted by one pod at a time, so a pod
   from a previous scan that was never cleaned up blocks the next one.
   Delete the stale pods by scan-name label and re-scan.
2. **The check could not read what it needed on the node** — a file or
   a kernel parameter that does not exist in this configuration. On a
   hardened, FIPS, disconnected build this is a genuine result and
   usually belongs in the exceptions register as a documented
   deviation, not in a bug report.
3. **Timeout.** The scanner pod timeout is set in the `ScanSetting`,
   and the scan retries until it runs out of retries. Slow nodes and
   large filesystems make this likelier than it sounds.
4. **SCC or capability restrictions** on the scanner's service
   account. Worth suspecting on a cluster whose hardening you wrote
   yourself.

For the stubborn one, raise verbosity rather than guessing: the
`ScanSetting` and `ComplianceSuite` carry a `debug` option that makes
the scanner container log the raw OpenSCAP output. Set it, re-scan the
one scan, read the scanner container, then turn it off — the volume is
substantial and the results volume keeps only the last three scans.

**An `ERROR` is not a `PASS`.** Whatever the cause, it ends up in the
evidence pack as an `ERROR` with an explanation, or it ends up fixed.
It does not end up in a summary count of failures that does not mention
it — see [chapter 12](12-evidence-pack.md).

### A scan never finishes

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **No duration is stated here on purpose.** "It has been twenty
> minutes" is unanswerable without a measured normal, and a figure
> invented for this page would be worse than none — it would make a
> healthy slow scan look broken and a stuck one look fine.

First establish *where* it is stuck, which is usually enough:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancescan -n openshift-compliance
oc get compliancesuite -n openshift-compliance
oc get pods -n openshift-compliance -o wide
oc get pvc -n openshift-compliance
```

A scan moves through phases and reports the one it is in. Read it as:

| Stuck at | Look at |
|---|---|
| nothing scheduled, no pods | the operator itself, and whether the profile content parsed at all |
| pods `Pending` | scheduling — on [compact](topologies/compact.md) a loaded three-node cluster has nowhere to put them; on any topology, a `ReadWriteOnce` PVC already mounted elsewhere |
| pods `Running` forever | the scanner. See the `ERROR` section above, and the scan timeout in the `ScanSetting`. |
| scanning finished, no results | the aggregator pod |

**Do not delete the scan and start again.** That is the instinct, it
clears the evidence, and it recreates the same stuck state a few
minutes later. If pods must be removed to free the results volume,
remove the helper pods by scan-name label and re-scan by annotating
the existing scan rather than recreating the binding:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

```sh
# ===== RUN ON: THE CLUSTER =====
oc annotate -n openshift-compliance compliancescan/<scan> \
  compliance.openshift.io/rescan= --overwrite
```

Recreating the binding instead is what makes the delta in
[chapter 10](10-remediation.md#re-scan-and-delta) compare the wrong
things.

What to measure on the real cluster, once, and write into
[chapter 9](09-compliance-operator.md): wall-clock duration of the
baseline `ocp4-stig` scan and of the `rhcos4-stig` scan, per node.
Those two numbers turn this whole section into one glance.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.

Ask the release payload which image provides `must-gather`, rather
than typing a reference. The trap is in the first half: `oc adm
release info` reads the payload **from a registry, over the network,
from wherever `oc` is running** — so it must be pointed at the mirror
and given the mirror pull secret. Pointing it at the `quay.io`
reference the cluster reports is an outbound call on an airgapped
host, and it hangs exactly like everything else in this chapter.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
MG=$(oc adm release info --image-for=must-gather \
  -a ${OCP_INSTALL_ROOT}/handoff/pull-secret.json \
  registry.airgap.local:8443/openshift/release-images@sha256:<digest>)
echo ${MG}
```

Then run the gather against the cluster, with that reference:

```sh
# ===== RUN ON: THE CLUSTER =====
oc adm must-gather --image=${MG} --dest-dir=./must-gather
```

The digest for the release image is in prep's handoff bundle; the
cluster will also tell you what it is running, which is worth checking
against it:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterversion version -o jsonpath='{.status.desired.image}{"\n"}'
```

Two things make the gather itself work, and both are facts prep
established:

- **`--image-for` returns the canonical `quay.io/...@sha256:...`
  reference, not your mirror path.** That is correct and you should
  not rewrite it. The must-gather pod runs on a node, the node has the
  IDMS from [chapter 6](06-day1-cluster-config.md), and the digest pull
  is redirected to the mirror transparently. Hand-editing the registry
  into the reference is the common mistake and defeats the mechanism
  that is already working.
- **It is a digest, not a tag.** Mirrored images are
  digest-referenced, so `oc image info <repo>:latest` failing against
  this mirror means the mirror is healthy, not broken. Anything built
  on a `:latest` reference will fail here and the failure will look
  like an outage.

If the pull does fail, the fallback is to rewrite the reference by
digest against the mirror path — but treat needing it as evidence that
the IDMS is incomplete, which is a bigger problem than `must-gather`:

```sh
# ===== RUN ON: THE CLUSTER =====
oc adm must-gather \
  --image=registry.airgap.local:8443/openshift/release@${MG##*@}
```

Two more things to settle **before** you need this, which is the whole
point of the section:

1. **Was `must-gather` mirrored at all?** It is in
   [chapter 1's mirror gate table](01-intake.md#the-mirror-gate) for
   exactly this reason. Resolve and pull the reference once, on a
   healthy cluster, as a rehearsal. Finding out during an incident
   that it is a transfer window away is the failure this repository
   keeps describing.
2. **Layered operators ship their own must-gather images** — the
   Compliance Operator and the File Integrity Operator among them —
   and those are *not* in the release payload. They are separate
   mirror entries, and `oc adm must-gather` takes repeated `--image`
   arguments to combine them.

> 📌 **Handoff** Record the resolved `must-gather` digest in the
> evidence pack alongside the cluster version. It is the one
> diagnostic command support will ask for, and in a year nobody will
> remember how it was made to work. See
> [12-evidence-pack.md](12-evidence-pack.md).
