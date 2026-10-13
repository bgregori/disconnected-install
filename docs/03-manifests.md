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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The agent workflow does **not** have the window the diagram above
> describes, and that is the single most important thing to verify in
> this chapter. There is no `create manifests` / `create
> ignition-configs` pair. Instead `openshift/` is a directory you create
> yourself, populate *before* generating anything, and the installer
> picks up. The window is not a pause you step into — it is a directory
> you have to have filled in advance. What is unverified is whether
> `agent create cluster-manifests` preserves `openshift/` across a run
> and whether a file dropped in the wrong directory is rejected or
> silently ignored. Assume silently ignored until you have seen
> otherwise, because that is the failure that produces an unencrypted
> cluster.

The layout the installer expects, built by hand before any
`openshift-install-fips` subcommand runs:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/cluster/openshift

cp ${OCP_INSTALL_ROOT}/manifests-src/*.yaml \
   ${OCP_INSTALL_ROOT}/cluster/openshift/

ls -l ${OCP_INSTALL_ROOT}/cluster/
ls -l ${OCP_INSTALL_ROOT}/cluster/openshift/
```

```
${OCP_INSTALL_ROOT}/cluster/
  install-config.yaml       consumed and deleted by the next stage
  agent-config.yaml         consumed and deleted by the next stage
  openshift/                ◄── YOU PUT THINGS HERE, BEFORE
    98-master-chrony.yaml       anything is generated
    98-worker-chrony.yaml
    99-master-storage.yaml
    99-worker-storage.yaml
```

Optionally inspect what the installer makes of it — on a scratch copy,
because this consumes the input files:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
rm -rf ${OCP_INSTALL_ROOT}/validate
cp -a ${OCP_INSTALL_ROOT}/cluster ${OCP_INSTALL_ROOT}/validate
openshift-install-fips agent create cluster-manifests \
  --dir ${OCP_INSTALL_ROOT}/validate --log-level=info
ls -l ${OCP_INSTALL_ROOT}/validate/cluster-manifests/
ls -l ${OCP_INSTALL_ROOT}/validate/openshift/
rm -rf ${OCP_INSTALL_ROOT}/validate
```

That second `ls` is the one worth doing. If `openshift/` is empty after
a `cluster-manifests` run, your MachineConfigs were consumed rather than
carried, and the order of operations in this chapter is wrong — record
that and fix it here before anyone generates an ISO.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **This is the single most dangerous thing in this repository to guess
> at, and what follows is a guess.** A `MachineConfig` that is
> syntactically valid and semantically wrong produces nodes that boot
> fine, pass every cluster health check, and are not encrypted the way
> you believe. Nothing surfaces it. Nobody finds out until the assessor
> asks for `cryptsetup status` — by which point the cluster is in
> production and the fix is a reinstall.
>
> So: do not treat the YAML below as a template to fill in. Treat it as
> a description of what the right answer looks like, verify every field
> against the installation documentation for the release you are
> actually installing, and then prove it from a node with the commands
> at the end of this section **before** the cluster carries anything.
> The verification is not optional and it is not part of the draft.

### Write Butane, not MachineConfig

Hand-writing the `MachineConfig` for LUKS is how the semantically-wrong
version gets produced. The supported route is a Butane config, which is
short enough to read and check, compiled by `butane` into the
MachineConfig. The device paths, the partition labels, the filesystem
stanza and — under FIPS — the cipher arguments are all things `butane`
derives correctly and a human derives nearly correctly.

`butane` is **not in the handoff bundle.** Prep ships
`openshift-install-fips` and `oc` and nothing else. Getting it is a prep
Day-2 delta and a transfer window — see [13-day2.md](13-day2.md). That
is the correct answer; building the MachineConfig by hand because the
binary is on the wrong side of the airgap is the incorrect one, and it
is the decision that ends in unencrypted disks.

> ⚠️ **STIG** `butane`, once it arrives, is a new binary on a hardened
> host and will not execute until it is relabelled and trusted, in that
> order: `restorecon` then `fapolicyd-cli --file add`. Per host.
> Chapter 1 does the same dance for the installer.

### TPM v2

Four files — this one and its `worker` twin, plus chrony's pair later.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/99-master-storage.bu =====
variant: openshift
version: 4.21.0
metadata:
  name: 99-master-storage
  labels:
    machineconfiguration.openshift.io/role: master
boot_device:
  layout: x86_64
  luks:
    tpm2: true
openshift:
  fips: true
```

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/99-worker-storage.bu =====
variant: openshift
version: 4.21.0
metadata:
  name: 99-worker-storage
  labels:
    machineconfiguration.openshift.io/role: worker
boot_device:
  layout: x86_64
  luks:
    tpm2: true
openshift:
  fips: true
```

`openshift: fips: true` sits at the top level, outside `boot_device`,
and it is not decoration. It is what makes `butane` emit the
FIPS-permitted cipher and set `spec.fips` on the resulting
MachineConfig. Omitting it on a `fips: true` cluster produces a
MachineConfig that looks right and selects the wrong cipher.

**The `worker` file is required even on a cluster with no workers
today.** A pool with no machines costs nothing; a worker added in six
months to a cluster that only ever had a `master` storage config comes
up unencrypted, and nobody is watching for it then.

### Tang / NBDE

Same files, different `luks` block:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/99-master-storage.bu =====
variant: openshift
version: 4.21.0
metadata:
  name: 99-master-storage
  labels:
    machineconfiguration.openshift.io/role: master
boot_device:
  layout: x86_64
  luks:
    tang:
    - url: http://tang1.enclave.local:7500
      thumbprint: <thumbprint-from-tang1>
    - url: http://tang2.enclave.local:7500
      thumbprint: <thumbprint-from-tang2>
    threshold: 1
openshift:
  fips: true
```

`http` is not an error: the binding is authenticated by the thumbprint,
not by TLS. A wrong thumbprint fails at *provision* time, which is the
good kind of failure. A thumbprint copied from the wrong server fails
the same way. Get them from the servers themselves:

```sh
# ===== RUN ON: A NODE =====
curl -s http://tang1.enclave.local:7500/adv | head -c 200; echo
```

> 🚧 **DRAFT -- NOT VALIDATED.** The command that turns that
> advertisement into the thumbprint string Butane wants has not been run
> here. `clevis` ships a helper for it; confirm the exact invocation and
> the digest algorithm against the Tang version deployed, and record
> both — a thumbprint computed with the wrong digest is a boot failure
> on every node at once.

### Both, with a threshold

This is the form that answers "decrypts only in this rack, on this
network", and it contains the one arithmetic trap in the chapter:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/99-master-storage.bu =====
variant: openshift
version: 4.21.0
metadata:
  name: 99-master-storage
  labels:
    machineconfiguration.openshift.io/role: master
boot_device:
  layout: x86_64
  luks:
    tpm2: true
    tang:
    - url: http://tang1.enclave.local:7500
      thumbprint: <thumbprint-from-tang1>
    - url: http://tang2.enclave.local:7500
      thumbprint: <thumbprint-from-tang2>
    threshold: 3
openshift:
  fips: true
```

**`threshold` is "how many of the declared conditions must be met", and
any combination counts.** With a TPM and two Tang servers, `threshold:
2` does *not* mean "TPM and Tang". It means any two — and the two Tang
servers alone satisfy it, so a disk pulled from the chassis and booted
elsewhere on the same network decrypts. If the requirement is genuinely
"TPM **and** network", the threshold must be the number of Tang servers
plus one. Here: three.

That is also why the TPM-only and Tang-only forms above use no
`threshold` at all. Adding one to a single-condition config is a way to
write `1` where you meant `and`.

### Compile and stage

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
cd ${OCP_INSTALL_ROOT}/manifests-src

butane 99-master-storage.bu -o 99-master-storage.yaml
butane 99-worker-storage.bu -o 99-worker-storage.yaml

grep -A2 'cipher' 99-master-storage.yaml
grep -c 'fips: true' 99-master-storage.yaml
```

Read the output before copying it in. On a `fips: true` cluster the
rendered MachineConfig should carry `spec.fips: true` and the LUKS
options should name **`aes-cbc-essiv:sha256`** rather than the
`aes-xts-plain64` the non-FIPS default would give you. Roughly:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/99-master-storage.yaml =====
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 99-master-storage
spec:
  config:
    ignition:
      version: 3.4.0          # whatever butane emits -- do not hand-pick
    storage:
      luks:
      - clevis:
          tpm2: true
        device: /dev/disk/by-partlabel/root
        label: luks-root
        name: root
        options:
        - --cipher
        - aes-cbc-essiv:sha256
        wipeVolume: true
      filesystems:
      - device: /dev/mapper/root
        format: xfs
        label: root
        wipeFilesystem: true
  fips: true
```

That block is shown so you can recognise a correct render, **not so you
can type one.** The Ignition spec version, the partition label and the
filesystem stanza are all release-specific, and the two `wipe` fields
mean what they say.

### What is not settled

- **`/boot` is not covered by `boot_device.luks`.** It holds the kernel,
  the initramfs and the Clevis binding, and something has to be readable
  before anything can be decrypted. Root is encrypted; `/boot` is not.
  Say so in the evidence pack rather than letting an assessor discover
  it, and confirm the current behaviour for the release you install —
  this has moved.
- **Tang key rotation bricks nodes.** A Tang server rebuilt with new
  keys no longer satisfies a binding made against the old thumbprint,
  and every node that depended on it fails to boot — not at rotation
  time, at the next reboot, which may be months later and during an
  unrelated change. The rebinding procedure has not been established
  here. Establish it, and write it down somewhere the Tang owner will
  find it, before the servers go into normal patching.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> `cryptsetup status` proves the volume is LUKS2. It does not prove
> *what unlocks it*, which is the part the drafted MachineConfig could
> have got wrong, and the part the accreditation is actually about. The
> binding is what to look at:

```sh
# ===== RUN ON: A NODE =====
sudo clevis luks list -d /dev/disk/by-partlabel/root
sudo cryptsetup luksDump /dev/disk/by-partlabel/root | grep -i cipher
```

Read the `clevis luks list` output against what you intended. A `tpm2`
pin where you configured `sss` with a threshold means the threshold form
did not take, and the node is unlocking on the TPM alone — booting
normally, passing every health check, and not meeting the control. This
is the check that catches a semantically wrong MachineConfig, and it is
the reason the section above insists on it.

The cipher line should read `aes-cbc-essiv:sha256` on a `fips: true`
cluster. `aes-xts-plain64` means `openshift: fips: true` was missing
from the Butane config.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Two separate uncertainties here, and the second is the one that
> decides where this section lives. First: whether the installer will
> accept a `Template` and a `Project` config CR dropped into
> `openshift/` at all — the `Project` resource named `cluster` is one the
> installer generates itself, so supplying a second may conflict rather
> than merge. Second: the **namespace selector labels differ between the
> ingress policy and the monitoring policy**, for historical reasons,
> and getting one of them wrong produces exactly the symptom the
> paragraph above warns about. Verify both label strings against the
> release you install before trusting this.
>
> If the install-time route turns out not to work, this moves to
> [06-day1-cluster-config.md](06-day1-cluster-config.md) as a day-1
> patch. **Say so here when you find out**, and tick the "explicitly
> deferred" line in the checklist below rather than leaving it
> ambiguous.

Start from the default template rather than writing one, because it
carries the project-creation machinery you do not want to reinvent:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc adm create-bootstrap-project-template -o yaml \
  > ${OCP_INSTALL_ROOT}/manifests-src/project-template.yaml
```

Then add the policies to its `objects:` list. Four of them, and each
one exists because of a specific thing that breaks without it:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/project-template.yaml =====
objects:
# ... the existing Project / RoleBinding objects stay as generated ...
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: deny-by-default
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    policyTypes:
    - Ingress
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-same-namespace
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    ingress:
    - from:
      - podSelector: {}
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-openshift-ingress
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    policyTypes:
    - Ingress
    ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            policy-group.network.openshift.io/ingress: ""
- apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: allow-from-openshift-monitoring
    namespace: ${PROJECT_NAME}
  spec:
    podSelector: {}
    policyTypes:
    - Ingress
    ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            network.openshift.io/policy-group: monitoring
```

- **`deny-by-default`** is a policy with an empty `podSelector` and no
  `ingress` rules. That is what "deny" is spelled as — there is no
  `deny` keyword. Its presence is what flips the namespace from
  allow-all to deny-all; everything below it is an exception to it.
- **`allow-from-same-namespace`** keeps a multi-pod application working.
  Without it a web pod cannot reach its own database and the
  application looks broken on deploy.
- **`allow-from-openshift-ingress`** is the one whose absence is
  misdiagnosed. Routes stay `Admitted`, the ingress controller stays
  healthy, and every request returns `503`. It reads as an ingress
  problem for as long as you let it.
- **`allow-from-openshift-monitoring`** is the one whose absence is
  never diagnosed at all. Prometheus simply does not scrape, the
  `ServiceMonitor` reports no error, and the dashboards are empty — a
  compliance problem as much as an operational one, since chapter 12
  wants monitoring coverage.

**Note the two different label keys.** Ingress uses
`policy-group.network.openshift.io/ingress` with an empty-string value;
monitoring uses `network.openshift.io/policy-group: monitoring`. The
key order is reversed between them. That is not a typo in this
document, and the two are not interchangeable. Both labels are applied
to those namespaces by the platform — never set them yourself.

Point the cluster at the template:

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/project-config.yaml =====
apiVersion: config.openshift.io/v1
kind: Project
metadata:
  name: cluster
spec:
  projectRequestTemplate:
    name: project-request
```

The `Template` must land in the `openshift-config` namespace and the
`Project` CR is cluster-scoped and named `cluster`. Verify after the
cluster is up, with a throwaway project — this is the only check that
means anything:

```sh
# ===== RUN ON: THE CLUSTER =====
oc new-project policy-smoke-test
oc get networkpolicy -n policy-smoke-test
oc delete project policy-smoke-test
```

Four policies listed is the pass. Zero means the template is not wired
up, and every project created in the meantime is a project you now have
to audit.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The shape is documented and low-risk compared to disk encryption, but
> **the encoding is the part that fails quietly.** A base64 blob that is
> truncated, line-wrapped, or built from the wrong file produces a
> MachineConfig that applies cleanly and leaves a node pointing at a
> pool it cannot reach. Nothing reports it. Use Butane's `inline:` form
> rather than encoding by hand, and if you must encode by hand, read the
> warning below.
>
> There is also a second, partly-overlapping route: `additionalNTPSources`
> in `agent-config.yaml` ([02](02-install-config.md)). It covers
> discovery and bootstrap. Whether it also persists into the installed
> node's `chrony.conf` has not been established here — assume it does
> not, and set both.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/manifests-src/98-master-chrony.bu =====
variant: openshift
version: 4.21.0
metadata:
  name: 98-master-chrony
  labels:
    machineconfiguration.openshift.io/role: master
storage:
  files:
  - path: /etc/chrony.conf
    mode: 0644
    overwrite: true
    contents:
      inline: |
        server 10.20.30.2 iburst
        server 10.20.30.3 iburst
        driftfile /var/lib/chrony/drift
        makestep 1.0 3
        rtcsync
        logdir /var/log/chrony
```

The `worker` twin is the same file with `worker` in both the name and
the role label. Both are required, for the same reason the storage
configs both are.

Three details carry the whole thing:

- **`overwrite: true`.** Without it, Ignition refuses to replace the
  `/etc/chrony.conf` that RHCOS already ships, and the node keeps the
  default — which points at a public pool. This is the quiet failure.
- **`server`, not `pool`.** The RHCOS default uses `pool`, which
  expects a name that resolves to several addresses. In an enclave you
  have specific hosts. A `pool` directive against a single-address name
  works but obscures what is configured, and the evidence pack has to
  state the time source.
- **No public pool line survives.** The file is replaced wholesale, not
  merged. That is the intent: there must be no fallback to
  `*.pool.ntp.org`, because a node that reaches a public NTP server is
  a node that reached the internet.

Compile and stage alongside the storage configs:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
cd ${OCP_INSTALL_ROOT}/manifests-src
butane 98-master-chrony.bu -o 98-master-chrony.yaml
butane 98-worker-chrony.bu -o 98-worker-chrony.yaml
```

The rendered file carries the config as a `data:` URL under
`spec.config.storage.files[].contents.source`. If you are building that
by hand because `butane` is not available, the encoding must be
unwrapped — `base64 -w0`, with no newline inserted anywhere — and the
prefix is `data:text/plain;charset=utf-8;base64,`. A wrapped blob is
still valid YAML, still applies, and decodes to a truncated file.
Check by decoding your own output back before you trust it:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
grep -o 'base64,[A-Za-z0-9+/=]*' \
  ${OCP_INSTALL_ROOT}/manifests-src/98-master-chrony.yaml |
  cut -d, -f2 | base64 -d
```

What comes back must be your `chrony.conf`, complete, last line
included.

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
