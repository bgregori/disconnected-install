# Encryption at rest

etcd stores every `Secret`, `ConfigMap` and token in the cluster. By
default it stores them in a form that is readable to anyone who can read
the etcd data files — which, on an unencrypted disk, means anyone who can
read the disk.

This chapter is the *inside-the-cluster* half of that problem. The
outside half is boot-disk encryption, done at the manifest stage in
[chapter 3](03-manifests.md). **They are not substitutes for each
other**, and it is worth being precise about why, because "the disks are
encrypted" is frequently offered as a reason to skip this:

| | Protects against | Does not protect against |
|---|---|---|
| **LUKS boot-disk encryption** (ch. 3) | a disk leaving the building | anything at all on a running node, where the volume is unlocked |
| **etcd encryption** (here) | reading secrets out of etcd data files or an etcd backup on a running or backed-up system | an attacker with cluster API access and RBAC to read secrets |

An etcd backup copied to a share is the case that catches people. The
node it came from is encrypted; the backup is a file.

**Only one of the two is a STIG control, and it is this one.**
CNTR-OS-000780 — *the keystore must implement encryption to prevent
unauthorized disclosure of information at rest within the container
platform* — is checked by `api_server_encryption_provider_cipher`, so
a cluster that skips this chapter fails a scan and is told so. Nothing
in the benchmark asks about the disks, which is
[chapter 3's problem](03-manifests.md#it-is-not-a-stig-control-and-that-is-the-problem),
not this chapter's.

That cuts both ways, and the second direction is the one to watch:
because this control is scanned and disk encryption is not, "encryption
at rest" in a review conversation tends to resolve to whichever of the
two the scan mentioned. They are different mechanisms protecting
different things, and the evidence pack needs both named separately.

Unlike chapter 3, none of this is install-time. It is a day-1 operation
on a running cluster and it can be done late — so it is not a decision
that has to be made before the ISO, only one that has to be made before
anyone signs anything.

---

## Enabling it

What is known about the shape of the operation, and is worth
understanding before starting it:

- **It is asynchronous and slow.** Enabling encryption does not encrypt
  anything by itself; it causes the API servers to roll out with
  encryption configured, and then every affected resource is rewritten.
  On a large cluster that is a long time.
- **It rolls the API servers.** Expect API unavailability, or at least
  instability, during the rollout. On single node that is a full outage
  — see [topologies/sno.md](topologies/sno.md).
- **Resources are only encrypted once rewritten.** A `Secret` created
  before encryption was enabled is encrypted when the migration rewrites
  it, not when the flag is set. "Encryption is enabled" and "everything
  is encrypted" are different states and the gap between them is where
  people declare victory early.
- **It is not a one-way door.** Unlike disk encryption in chapter 3,
  this is a field you can change afterwards — including between cipher
  types, where the cluster migrates the data automatically. That makes
  the cipher decision below a decision you can revisit, which is worth
  knowing before you spend a week trying to get it right on paper.

### Which cipher

Two are supported. Both set the same field, `spec.encryption.type`, on
the single `APIServer` resource named `cluster`:

| Value | What it is |
|---|---|
| `aescbc` | AES-CBC with PKCS#7 padding and a 32-byte key. The longer-standing option; the only one in early 4.x. |
| `aesgcm` | AES-GCM with a random nonce and a 32-byte key. The newer option. |

**On FIPS, this repository does not have an answer and will not invent
one.** What can be said without guessing: AES-CBC and AES-GCM are both
NIST-approved modes, so the mode itself is unlikely to be the deciding
factor, and on a `fips: true` cluster the work is done by a validated
module either way. What has *not* been established is whether the
OpenShift implementation of either path is rejected or behaves
differently under FIPS on 4.21.

Decide it, record the decision and the reasoning in the evidence pack,
and verify it empirically — the migration either completes or it does
not, and the condition in the next section is what tells you which.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The field path and the two accepted values are documented. The
> unverified part is the FIPS interaction above. Run this in a change
> window with the break-glass `kubeconfig` from
> [chapter 5](05-first-access.md#the-credentials-the-installer-produced)
> to hand, because it rolls all three API servers and on single node
> that is a full outage.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get apiserver cluster -o jsonpath='{.spec.encryption}{"\n"}'
oc patch apiserver cluster --type merge \
  -p '{"spec":{"encryption":{"type":"aescbc"}}}'
oc get apiserver cluster -o jsonpath='{.spec.encryption.type}{"\n"}'
```

The first command captures the before state, which is usually empty,
and an empty before state is itself evidence worth keeping. Substitute
`aesgcm` if that is what you decided.

> ⚠️ **Do not take an etcd backup until the migration below reports
> complete.** A backup taken mid-migration is partially encrypted: some
> values enciphered, some plaintext, and no marker distinguishing them.
> It will restore, and it will look fine.

Watch it rather than assuming:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator kube-apiserver -w
oc get clusteroperator openshift-apiserver
oc get clusteroperator openshift-authentication
```

Three operators, because three API servers are involved. All three must
settle.

### Configured versus migrated

`Available=True` on those three operators means the API servers rolled
out with encryption configured. It says nothing about whether the
existing data has been rewritten. The condition that does is a separate
one, called `Encrypted`, and it is reported **per operator resource**
— not on the `APIServer` CR you patched, and not on the
`ClusterOperator`.

Three resources, because three sets of data are being migrated:

| Resource | Covers |
|---|---|
| `openshiftapiserver` | routes |
| `kubeapiserver` | secrets, config maps |
| `authentication.operator.openshift.io` | OAuth access and authorize tokens |

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> These are read-only. What to watch for is the trailing resource list
> in the message — it names what was encrypted, and a short or
> surprising list is more informative than the reason string. The fully
> qualified `authentication.operator.openshift.io` matters: plain
> `authentication` resolves to the config resource, which has no
> `Encrypted` condition and returns nothing, which reads as a failure
> and is not one.

```sh
# ===== RUN ON: THE CLUSTER =====
for r in openshiftapiserver kubeapiserver authentication.operator.openshift.io; do
  echo "== ${r}"
  oc get "${r}" \
    -o jsonpath='{range .items[0].status.conditions[?(@.type=="Encrypted")]}{.reason}{"\n"}{.message}{"\n"}'
done
```

All three must report `EncryptionCompleted`. `EncryptionInProgress`
means wait — the documented expectation is twenty minutes or longer
depending on the size of the etcd database, and on a cluster this size
it will be at the short end. Nothing is wrong until it stops changing.

Capture all three outputs. That block is the evidence for this chapter;
`oc get apiserver cluster` showing the type is configuration, and an
assessor who knows the difference will ask for this instead.

---

## Proving it

A statement that encryption is enabled is configuration. An assessor
asks for evidence, and the convincing evidence is a secret that is
unreadable in etcd.

Do not read a real secret to prove this. You are about to pipe etcd
contents into a terminal whose transcript is itself an evidence
artifact, and if encryption is *not* working — which is the case you
are testing for — you will have printed a live credential into it.
Create a throwaway with a known marker instead.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The uncertain parts are the container name (`etcdctl`, a sidecar that
> carries the client certificates pre-configured) and the etcd key
> layout `/kubernetes.io/secrets/<namespace>/<name>`. Both are stable
> across recent 4.x but neither has been checked here. Confirm the
> container exists with `oc -n openshift-etcd get pod <pod> -o
> jsonpath='{.spec.containers[*].name}'` before using `-c`.

```sh
# ===== RUN ON: THE CLUSTER =====
oc create secret generic etcd-encryption-probe -n default \
  --from-literal=probe=ENCRYPTION-PROBE-CANARY

ETCD_POD=$(oc -n openshift-etcd get pods -l app=etcd \
  -o jsonpath='{.items[0].metadata.name}')
oc -n openshift-etcd exec -c etcdctl "${ETCD_POD}" -- \
  etcdctl get /kubernetes.io/secrets/default/etcd-encryption-probe \
  | hexdump -C | head -20

oc delete secret etcd-encryption-probe -n default
```

What you are looking for in that hexdump:

- the prefix `k8s:enc:aescbc:v1:` (or `aesgcm`) followed by a key name,
  then binary — **this is the pass**
- the literal string `ENCRYPTION-PROBE-CANARY` anywhere in the output
  — **this is the failure**, and it means the value is on disk in
  plaintext

Grep for the canary rather than eyeballing it. A hexdump is exactly the
kind of output a tired person declares correct.

> ⚠️ **What not to type.** You are in a shell with write access to the
> cluster's entire state store, authenticated, with no confirmation
> prompts. `etcdctl del`, `put`, `txn`, `compact`, `defrag` and
> `move-leader` all do what they say and none of them ask. `del` with
> `--prefix` will take the cluster apart. Use `get` and nothing else,
> and do not use `get --prefix /kubernetes.io/secrets` — that dumps
> every secret in the cluster into your transcript, which is a disaster
> of a different kind.

**If this is judged too risky for the environment, decline it in
writing.** Capture the `APIServer` resource showing the encryption
type, the three `Encrypted` conditions showing migration complete, and
a recorded decision that direct etcd inspection was not performed, with
the reason and who made the call. A documented decision not to run a
risky command is acceptable evidence. An undocumented gap is not.

---

## Key rotation

Encryption keys are managed by the cluster and rotated on a schedule it
owns. That is usually the right answer, and it is worth knowing it is
happening rather than discovering it during an incident.

The documented behaviour, which is the answer to give an assessor and
the answer to back with evidence:

- Keys are rotated **every seven days**, by the cluster, without
  operator action.
- Up to **ten historical keys** are retained, so that a backup taken
  under an older key can still be decrypted.
- Nothing is required of an operator. There is no rotation command and
  no schedule to configure.

"The cluster handles it" is true and is not sufficient on its own. Show
the keys.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The namespace and naming convention below are the uncertain part —
> the keys are believed to live as `Secret` objects in
> `openshift-config-managed` named `encryption-key-<component>-<n>`,
> with the generation number incrementing on each rotation. If the
> filter returns nothing, drop the `grep` and look at the whole
> namespace rather than concluding there are no keys.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get secrets -n openshift-config-managed \
  --sort-by=.metadata.creationTimestamp \
  | grep '^encryption-key-'
```

The generation numbers and creation timestamps are the evidence: more
than one generation, with dates roughly a week apart, demonstrates
rotation actually happening rather than being merely configured. On a
cluster less than seven days old there will be exactly one, which is
correct and is worth noting as such so that a later reader does not
read it as a finding.

> ⚠️ **The encryption keys travel with the backup, and that is the
> problem.** An etcd backup writes a
> `static_kuberesources_<timestamp>.tar.gz` alongside the snapshot, and
> that tarball **contains the encryption keys**. The two files together
> are plaintext. Store them separately — and you still need both to
> restore, so "separately" means two locations with different access,
> not one of them discarded.

---

## What this does not cover

Worth stating in the evidence pack, because the gaps are reasonable and
look like oversights if they are not named:

- **Secrets in use are plaintext in memory**, in pods, and in any
  environment variable they are projected into. Encryption at rest is
  not encryption in use.
- **etcd backups.** If the backup is written to a volume or share that
  is not itself encrypted, the backup is the weak point. This is almost
  always outside the cluster's control and therefore nobody's job unless
  it is made somebody's.
- **RBAC is still the real control.** A user who can `oc get secret` is
  unaffected by any of this.

📌 **Handoff** The etcd backup destination and its encryption posture
belong to whoever owns backups, not to the cluster team. Ask, get an
answer in writing, and put it in the evidence pack. See
[12-evidence-pack.md](12-evidence-pack.md).

---

Next: [09-compliance-operator.md](09-compliance-operator.md).
