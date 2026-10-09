# First access and bootstrap watch

From "the nodes are booting" to "I have a kubeconfig and the cluster
operators are settling".

---

## The credentials the installer produced

The install directory holds two things that are credentials, and both are
written in plain text:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
ls -l ${OCP_INSTALL_ROOT}/cluster/auth/
```

| File | What it is |
|---|---|
| `kubeconfig` | a `system:admin` certificate, not subject to the OAuth stack and not revocable by deleting a user |
| `kubeadmin-password` | the password for the temporary `kubeadmin` account |

> ⚠️ **STIG** Both are findings waiting to happen if they stay where they
> are. `kubeadmin` is deleted in [chapter 7](07-identity.md) — but only
> after the external IdP works and another cluster-admin exists, and not
> before. The `kubeconfig` certificate is a harder problem: it survives
> the deletion of `kubeadmin`, it cannot be revoked by any user-management
> action, and it is the reason this file has to be handled as a
> break-glass credential rather than as a convenience.
>
> Decide now where it will live afterwards — an offline safe, a
> credential vault, a sealed envelope — and record the decision. Chapter
> 12 asks for it. "It is still in the install directory on the install
> host" is an answer an assessor will not accept.

```sh
# ===== RUN ON: THE INSTALL HOST =====
chmod 600 ${OCP_INSTALL_ROOT}/cluster/auth/kubeconfig
chmod 600 ${OCP_INSTALL_ROOT}/cluster/auth/kubeadmin-password

export KUBECONFIG=${OCP_INSTALL_ROOT}/cluster/auth/kubeconfig
oc whoami            # system:admin
```

---

## Watching the bootstrap

> **TODO:** needs validation on real hardware — the agent-based
> installer's wait/monitor commands, what their normal output looks like,
> and roughly how long each phase takes on this hardware. Record the
> timings: the most common operational error at this stage is deciding
> something has hung when it has not, and intervening.

What to look at once the API answers:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get nodes
oc get clusteroperators
oc get clusterversion
```

`oc get clusteroperators` is the one that matters. A cluster is not
installed when the API answers; it is installed when every operator is
`Available=True`, `Progressing=False`, `Degraded=False`. Expect several
minutes of churn.

### What a disconnected failure looks like here

Two patterns, and they are different problems:

**An operator stuck `Progressing` with image pull errors naming
`quay.io` or `registry.redhat.io`.** `imageDigestSources` is incomplete —
it covered the release payload but not an operator source, which is
exactly what happens when only the first YAML document of prep's IDMS was
copied. This is not fixable by editing anything on a running cluster in
the way you would hope; see [troubleshooting](troubleshooting.md).

**An operator stuck with x509 errors naming the registry.** The CA did
not arrive. `additionalTrustBundle` was missing,
`additionalTrustBundlePolicy: Always` was not set, or the pasted
certificate lost its indentation.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get events -A --sort-by=.lastTimestamp | tail -50
oc describe clusteroperator <name>
```

---

## Prove the pull path, early

Before doing anything else, confirm that what the cluster is actually
pulling comes from the mirror. Doing this now, rather than in
[chapter 6](06-day1-cluster-config.md), means finding a wrong
`imageDigestSources` while the cluster is still empty and reinstalling is
cheap.

> **TODO:** needs validation on real hardware — the check that proves
> every running image reference resolves to the mirror. The shape is
> clear (enumerate the images actually in use, confirm each resolves
> through IDMS to the mirror registry) but the command that does it
> accurately has not been run, and a check that reports success wrongly
> is worse than no check. Write it only once it has caught a real
> failure.

The weaker check that is available immediately, and is worth doing
anyway:

```sh
# ===== RUN ON: A NODE =====
sudo crictl images | head -40
```

Every reference should name the mirror registry. One that names
`quay.io` is either a pull that succeeded from somewhere it should not
have — which means the airgap is not what you think it is — or a cached
reference, which needs chasing.

---

## Diagnostics

`must-gather` and `support-tools` are in prep's mirror if someone asked
for them. Chapter 1's mirror gate should have confirmed it. If they are
absent, you have no diagnostic collection in an environment where you
most need it, and obtaining them is a transfer window.

> **TODO:** needs validation on real hardware — the `oc adm must-gather`
> invocation against a mirrored image. The default pulls from
> `registry.redhat.io`, so the disconnected form requires `--image` with
> the mirrored reference; the exact reference depends on how prep's
> mirror laid the image out, and prep established that mirrored images
> are digest-referenced rather than tagged. Confirm the working form and
> record it here, because the moment you need this command is the worst
> moment to work it out.

---

Next: [06-day1-cluster-config.md](06-day1-cluster-config.md).
