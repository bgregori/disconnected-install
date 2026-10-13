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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **No timings are given, deliberately** — see
> [04](04-agent-iso.md#booting). The most common operational error at
> this stage is deciding something has hung when it has not, and
> intervening; a made-up number in this repository would cause exactly
> that. Record the real ones on the first install.

Two commands, in order, and the second is not optional:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
openshift-install-fips agent wait-for bootstrap-complete \
  --dir ${OCP_INSTALL_ROOT}/cluster --log-level=info
```

`bootstrap-complete` returns when the API server is up on the control
plane. That is not an installed cluster — it is the point at which the
rendezvous host stops being special and the install continues without
it.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
openshift-install-fips agent wait-for install-complete \
  --dir ${OCP_INSTALL_ROOT}/cluster --log-level=info
```

`install-complete` is the one that means what you want it to mean. Both
read state from the install directory, so `--dir` must point at the
directory the ISO was generated from — a fresh or re-created directory
makes them fail in ways that look like cluster problems.

If either exits non-zero, go back to
[04 — watching it](04-agent-iso.md#watching-it) for the rendezvous-host
logs. The wait commands report that something did not happen; they do
not report why.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **A check that reports success wrongly is worse than no check**, and
> this one has a specific way of doing that, described below. The query
> below has not been run and has not caught a real failure. Until it
> has, treat a clean result as weak evidence and the `crictl` check
> further down as the stronger one.

The trap first, because it inverts the obvious command. A pod's
`spec.containers[].image` is the reference the workload *asked for*,
and on a correctly mirrored cluster it still says `quay.io`. IDMS
rewriting happens in CRI-O at pull time, below the API. So the field
everybody greps is the field that proves nothing in either direction.

`status.containerStatuses[].imageID` is what was actually pulled:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get pods -A -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}' |
  sed 's#@sha256:.*##' | sort -u
```

Every line should name the mirror registry. A line naming `quay.io` or
`registry.redhat.io` is one of two things, and they are different
problems:

- **A pull that succeeded from the internet.** The airgap is not what
  you think it is. This is a finding in its own right, independent of
  the install.
- **A reference that was never pulled on this cluster**, carried in
  some other way. Chase it; do not assume the first explanation.

Confirm the mirror configuration actually landed, too, since an empty
one produces no errors at all on a cluster whose images are already
cached:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get imagedigestmirrorset -o yaml | grep -c 'mirrors:'
```

That count must match the one chapter 2 took from prep's IDMS. A
mismatch means `imageDigestSources` was incomplete, and the platform
images will pull while the operator images will not — a failure that
waits until chapter 9.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **Run this once while nothing is wrong.** The moment you need
> `must-gather` is the worst possible moment to discover the invocation
> is different from the one written here. What is uncertain is whether
> `--image-for` resolves through IDMS the way the form below assumes,
> and whether the mirrored image is reachable by the digest the release
> payload names.

The default invocation pulls from `registry.redhat.io` and hangs. The
disconnected form has to name the image, and because mirrored images
are digest-referenced rather than tagged, the reference cannot be typed
from memory. Ask the release payload for it:

```sh
# ===== RUN ON: THE CLUSTER =====
oc adm release info --image-for=must-gather
```

That returns a digest reference, which IDMS then redirects to the
mirror. Feed it straight back in:

```sh
# ===== RUN ON: THE CLUSTER =====
oc adm must-gather --image="$(oc adm release info --image-for=must-gather)" \
  --dest-dir=./must-gather.local
```

If `release info` itself cannot reach the payload, you have a pull-path
problem rather than a `must-gather` problem — go back to the section
above.

`support-tools` is a separate image and is only present if prep
mirrored it. Chapter 1's mirror gate should have confirmed that. If it
is absent, obtaining it is a transfer window, not a command.

---

Next: [06-day1-cluster-config.md](06-day1-cluster-config.md).
