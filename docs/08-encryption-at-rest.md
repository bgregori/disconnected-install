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

---

## Enabling it

> **TODO:** needs validation on real hardware — the patch to the
> `APIServer` resource that enables encryption, the supported cipher
> choices and which one is correct under `fips: true`, and the
> read-back that confirms the chosen type is in effect.
>
> Establish specifically: whether the cipher choice interacts with FIPS
> mode at all, because a cipher that is permitted on a non-FIPS cluster
> and rejected on a FIPS one is the kind of detail that turns a ten
> minute change into a day.

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

Watch it rather than assuming:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator kube-apiserver -w
oc get clusteroperator openshift-apiserver
oc get clusteroperator openshift-authentication
```

Three operators, because three API servers are involved. All three must
settle.

> **TODO:** needs validation on real hardware — the condition on the
> `APIServer` or `kube-apiserver` resource that reports migration
> *complete* rather than merely *configured*. This is the thing to check
> before declaring the control satisfied, and it is not the same as the
> operator being `Available`.

---

## Proving it

A statement that encryption is enabled is configuration. An assessor
asks for evidence, and the convincing evidence is a secret that is
unreadable in etcd.

> **TODO:** needs validation on real hardware — the procedure that reads
> a known `Secret` directly out of etcd and shows it is not plaintext.
> This requires an etcd client inside an etcd pod and is a destructive-
> adjacent operation on a production cluster; write it only once it has
> been done safely, and include the warning about what not to type.
>
> The weaker-but-safe alternative, if the above is judged too risky for
> the environment: capture the `APIServer` resource showing the
> encryption type, plus the operator conditions showing migration
> complete, and record that direct etcd inspection was declined with a
> reason. A documented decision not to run a risky command is acceptable
> evidence. An undocumented gap is not.

---

## Key rotation

Encryption keys are managed by the cluster and rotated on a schedule it
owns. That is usually the right answer, and it is worth knowing it is
happening rather than discovering it during an incident.

> **TODO:** needs validation on real hardware — the rotation behaviour
> and whether anything is required of an operator. If the answer is
> "nothing, it is automatic", say that explicitly with the evidence,
> because an assessor will ask about key management and "the cluster
> handles it" needs backing.

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
