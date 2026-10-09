# Identity

Pointing the cluster at the external identity provider, binding a real
group to `cluster-admin`, proving a human can log in, and only then
deleting `kubeadmin`.

**The order in this chapter is the chapter.** Every step is
individually easy and the sequence is what stops you locking yourself out
of a cluster that has no other credential.

---

## What this chapter satisfies

| Rule | Requirement |
|---|---|
| **CNTR-OS-000030** | The identity provider must be LDAP or OpenID. HTPasswd is prohibited. |
| **CNTR-OS-000460** | The same prohibition, under a different control family. |
| **CNTR-OS-000040** | The `kubeadmin` credential must be removed. |
| **CNTR-OS-000430** | Multifactor authentication — satisfied **at the IdP**, not in the cluster. |
| **CNTR-OS-000760** | `accessTokenMaxAgeSeconds` no greater than 28800 (eight hours). |

These five are cited because they have been read and confirmed. Nothing
else in this repository cites a rule ID — see
[the README](../README.md#on-stig-rule-ids).

Note what CNTR-OS-000030 and CNTR-OS-000460 jointly rule out: the
HTPasswd provider that almost every OpenShift walkthrough uses as a quick
way to get a second admin account before deleting `kubeadmin`. In this
build that intermediate step is itself prohibited, so the external IdP
has to work *first*. That is the reason this chapter's ordering is tight.

---

## The IdP is outside the cluster

Red Hat build of Keycloak runs on a services host, not in the cluster.

Three consequences worth stating, because each one removes a question
that would otherwise be asked:

- **Nothing identity-related needs mirroring.** No RHBK images, no
  operator, no change to prep's ImageSetConfiguration. Chapter 1's mirror
  gate does not cover identity because there is nothing to cover.
- **The IdP's availability is the cluster's availability, for humans.**
  If RHBK is down, nobody logs in. Workloads keep running and the
  break-glass `kubeconfig` still works, which is precisely why the
  break-glass `kubeconfig` has to be kept somewhere retrievable.
- **The cluster must reach the issuer URL.** This is outbound traffic
  from an airgapped cluster to a host on the services network, and it is
  routinely missed by the firewall request because identity is agreed
  before networking is.

📌 **Handoff** The IdP owner needs to know that this cluster is now a
client of theirs: a client ID that must not be deleted, a secret that
must be rotated on a schedule somebody owns, and a CA whose expiry breaks
cluster login when it passes.

---

## The five things the cluster consumes

Collected in [chapter 1](01-intake.md#the-idp-facts). If you skipped
that, go back — two of these take days to obtain.

| | Consumed as |
|---|---|
| Issuer URL | a field in the `OAuth` CR |
| Client ID | a field in the `OAuth` CR |
| Client secret | a `Secret` in `openshift-config` |
| IdP CA | a `ConfigMap` in `openshift-config` |
| Claim names | `preferred_username`, `email`, `name`, `groups` — mapped in the `OAuth` CR |

The CA `ConfigMap` is required even when the IdP's certificate is signed
by a CA the rest of the estate trusts. The cluster does not inherit the
estate's trust store.

---

## Step 1 — the client secret

> **TODO:** needs validation on real hardware — the `Secret` creation
> command and the exact key name the OAuth stack reads it from. The key
> name is not freely chosen and a wrong one produces an authentication
> failure that names neither the secret nor the key.

The secret is a credential from the moment it is issued. It should not
reach your shell history, and it should not sit in a file on the install
host afterwards. Whatever form the creation command takes, pass it from
standard input or a file, not as an argument — arguments are visible in
`ps` to every local account.

---

## Step 2 — the IdP CA

> **TODO:** needs validation on real hardware — the `ConfigMap` creation
> command and the key name the OAuth stack expects the certificate under.

Verify the certificate before you load it, not after:

```sh
# ===== RUN ON: THE CLUSTER =====
openssl x509 -in idp-ca.pem -noout -subject -issuer -dates
```

Check the expiry date and write it down. 📌 **Handoff** An IdP CA that
expires takes cluster login with it, and the failure arrives without
warning on a date nobody has in a calendar.

Confirm the chain is the one actually in use, from somewhere that is not
the IdP host:

```sh
# ===== RUN ON: THE CLUSTER =====
openssl s_client -connect <idp-host>:<port> -servername <idp-host> \
  </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
```

An IdP that presents an intermediate chain needs the whole chain, not
just the root. This is a common and confusing failure because `curl`
from a host with the full estate trust store succeeds while the cluster
does not.

---

## Step 3 — the OAuth CR

The cluster has exactly one `OAuth` resource, named `cluster`. Editing it
is how identity providers are added, and an empty `identityProviders`
list is how OpenShift ends up with only `kubeadmin`.

> **TODO:** needs validation on real hardware — the `OAuth` CR with an
> OpenID identity provider configured against RHBK: the provider stanza,
> the claim mapping block for `preferred_username`, `email`, `name` and
> `groups`, the references to the `Secret` and `ConfigMap` from steps 1
> and 2, and the `extraScopes` needed to make the `groups` claim appear.
>
> Establish also what the authentication operator reports while the
> configuration is wrong, because that is the diagnostic you will
> actually use — the login page gives nothing useful.

What is known and is not a guess:

- **The provider type must be OpenID** (or LDAP). HTPasswd is prohibited
  by CNTR-OS-000030 and CNTR-OS-000460. There is no intermediate
  HTPasswd step in this build.
- **`groups` is the claim that is usually missing.** Keycloak does not
  emit group membership by default. A cluster that authenticates
  perfectly but assigns nobody any privileges is a claim-mapper problem
  presenting as an RBAC problem, and people lose a day to it.

Applying the `OAuth` CR triggers a rollout of the authentication
operator. Watch it rather than immediately trying to log in:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator authentication -w
```

A failed configuration leaves the operator `Degraded` with a message
that is usually specific. Read it before changing anything.

---

## Step 4 — bind a real group to cluster-admin

Before this, the only cluster-admin is `kubeadmin` and the break-glass
certificate. After it, there is a group of named humans.

> **TODO:** needs validation on real hardware — the `ClusterRoleBinding`
> that binds the IdP-provided group to `cluster-admin`, and how the group
> name from the `groups` claim is spelled in the binding. The spelling is
> the trap: the name in the claim and the name you type are both strings,
> and a mismatch binds a group that does not exist, silently and
> successfully.

> ⚠️ **STIG** Bind a **group**, not a user. A user binding has to be
> maintained by hand as people join and leave, which means it will not
> be, and an account with cluster-admin belonging to someone who left is
> a finding that is both common and indefensible. A group binding moves
> that lifecycle to the IdP, where it already exists.

Confirm the binding exists and names what you think it names:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterrolebinding -o wide | grep cluster-admin
```

---

## Step 5 — set the token lifetime

**CNTR-OS-000760** requires `accessTokenMaxAgeSeconds` no greater than
**28800** — eight hours. It is a field on the same `OAuth` CR named
`cluster`.

> **TODO:** needs validation on real hardware — the patch that sets it
> and the confirmation read-back. The field is `accessTokenMaxAgeSeconds`
> under the OAuth CR's token configuration; the exact path has not been
> verified here and is not guessed at.

The failure mode it addresses: a token issued to a workstation stays
valid long after the session that produced it ended, so a stolen
`~/.kube/config` is a durable credential rather than a transient one.
Eight hours aligns it with a working day.

> Setting this restarts the OAuth server. Existing sessions are affected.
> Do it now, while nobody else depends on the cluster, rather than in a
> month.

---

## Step 6 — prove a human can log in

**Do not skip this, and do not do it yourself from a shell that already
has `KUBECONFIG` set.** The point is to prove the path a real person
takes.

```sh
# ===== RUN ON: THE CLUSTER =====
unset KUBECONFIG
oc login https://api.<cluster>.<base-domain>:6443
oc whoami
oc whoami --show-console
oc auth can-i '*' '*' --all-namespaces
```

`oc auth can-i '*' '*' --all-namespaces` must return `yes` for a member
of the cluster-admin group. That one command is the gate for step 7.

Three things to confirm, with a second person present:

- [ ] A named human in the cluster-admin group logs in and is
      cluster-admin
- [ ] A named human **not** in that group logs in and is **not**
      cluster-admin
- [ ] Logging in requires the second factor the IdP enforces
      (**CNTR-OS-000430**)

The second item matters as much as the first. A claim mapper that grants
everybody the admin group passes the first test perfectly.

---

## Step 7 — delete kubeadmin

**CNTR-OS-000040.** The `kubeadmin` credential is a well-known,
unattributable, shared account and must be removed.

> **TODO:** needs validation on real hardware — the resource name and
> namespace of the `kubeadmin` credential and the command that removes
> it, plus what the cluster reports afterwards to confirm it is gone.
> This is documented by Red Hat; it is not written here because it has
> not been executed here, and this is the one command in the repository
> where a wrong guess is unrecoverable.

### The gate

Do not run it until **all** of these are true. Tick them on paper.

- [ ] The external IdP is configured and the authentication operator is
      `Available=True`, `Degraded=False`
- [ ] A named human, not you, has logged in through the IdP
- [ ] That human is cluster-admin, proven with
      `oc auth can-i '*' '*' --all-namespaces`
- [ ] A **second** named human is also cluster-admin, so that one person
      leaving does not lock out the cluster
- [ ] The break-glass `kubeconfig` from
      [chapter 5](05-first-access.md#the-credentials-the-installer-produced)
      is stored somewhere retrievable by someone other than you, and that
      location is recorded
- [ ] Someone other than you has read this list and agrees

The failure this gate prevents: a cluster with no working
administrative credential, in an airgapped enclave, where the recovery
procedure involves physical access to a node. It has happened to people
who were being careful.

### Afterwards

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator authentication
```

Confirm the console no longer offers a `kubeadmin` login, and confirm
your IdP login still works. If the authentication operator goes
`Degraded` after the deletion, you have a problem that needs the
break-glass kubeconfig — which is why it had to be retrievable first.

📌 **Handoff** Record the date, the person who ran it, and the two named
cluster-admins who existed at the time. Chapter 12 collects this as the
evidence for CNTR-OS-000040; "we deleted it" without a date and a
witness is weaker evidence than it looks.

---

## What chapter 9 will check

The compliance scan will report on all five rules above. Running this
chapter before the baseline scan means the baseline reflects the cluster
you intend to have — see
[09-compliance-operator.md](09-compliance-operator.md). Running it after
means your baseline has five authentication findings that you already
know about and that make the real findings harder to see.

---

Next: [08-encryption-at-rest.md](08-encryption-at-rest.md).
