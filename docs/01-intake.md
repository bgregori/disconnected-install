# Intake

What must be true before you generate an ISO. This chapter is a gate, not
a setup step: everything in it is a check, and every check that fails here
is cheap compared to the same fact discovered at bootstrap, on the wrong
side of an airgap, with a change window burning.

Work it top to bottom. It ends with the handoff bundle verified, the
environment confirmed, and the mirror proven to contain what chapters 6
through 10 will install.

---

## Where the install tree lives

Everything this repository creates goes under one directory, named
`OCP_INSTALL_ROOT` throughout. **Decide it now and export it**, because
every later command is written in terms of it:

```sh
# ===== RUN ON: THE INSTALL HOST =====
export OCP_INSTALL_ROOT=/data/ocp-install     # or ~/ocp-install -- see below
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 0755 "${OCP_INSTALL_ROOT}"
```

`install -d` rather than `mkdir -p`, for two reasons that both bite here: a
volume you provisioned for this is root-owned, so the directory has to be
created with `sudo` and handed to the account that will write into it; and
`install` applies mode `0755` directly instead of subtracting the STIG
`umask 0077`.

> ⚠️ **STIG `$HOME` is usually the wrong choice.** The hardened builds put
> `/home` on its own file system, sized for user files and frequently
> quota'd, `nodev,nosuid`, or on NFS. This tree holds the handoff bundle,
> the install directory and at least one agent ISO. Put `OCP_INSTALL_ROOT`
> on the volume you provisioned for it.

**Make it durable.** An `export` dies with the shell, and the failure mode
is `cd ${OCP_INSTALL_ROOT}` silently landing you in your home directory —
or worse, `openshift-install --dir ${OCP_INSTALL_ROOT}/cluster` creating a
second, empty install directory under `/cluster` while the real one still
holds your manifests.

```sh
# ===== RUN ON: THE INSTALL HOST =====
sudo tee /etc/profile.d/ocp-install.sh <<'EOF'
export OCP_INSTALL_ROOT=/data/ocp-install
EOF
sudo chmod 0644 /etc/profile.d/ocp-install.sh
sudo restorecon -v /etc/profile.d/ocp-install.sh
```

Log out and back in, or `source /etc/profile.d/ocp-install.sh`, then
confirm before running anything that writes:

```sh
# ===== RUN ON: THE INSTALL HOST =====
echo "${OCP_INSTALL_ROOT:?not set -- see 01-intake.md}"
df -h "${OCP_INSTALL_ROOT}"
```

Chapters from here on open with that same `${OCP_INSTALL_ROOT:?...}`
guard. It costs nothing when the variable is set and stops the command
running against the wrong directory when it is not.

An already-running `tmux` server keeps the environment it was started
with. After adding the drop-in, start a new session — or `tmux
kill-server` first.

---

## The install host

One host, and it is not necessarily either of prep's two.

| | Requirement |
|---|---|
| OS | RHEL 9 |
| FIPS mode | **`fips_enabled=1`** — non-negotiable, see below |
| Network | routable to the mirror registry, and to the cluster API/VIPs once they exist |
| Out-of-band | reachable iDRAC/iLO/IPMI with virtual media, or whatever else will present the ISO |

> ⚠️ **The host that runs `openshift-install-fips` must itself be in FIPS
> mode.** This is a Red Hat requirement for a `fips: true` cluster and it
> is independent of which binary you use — the generic installer on a FIPS
> host and the FIPS installer on a non-FIPS host are both unsupported
> configurations. It is also a host rebuild, not a setting, so settle it
> before you need it. Prep states the requirement in full at
> [prep 01 — FIPS mode: host versus cluster](https://github.com/bgregori/disconnected-prep/blob/main/docs/01-prerequisites.md#fips-mode-host-versus-cluster);
> it is not restated here.

```sh
# ===== RUN ON: THE INSTALL HOST =====
cat /etc/redhat-release
cat /proc/sys/crypto/fips_enabled   # must be 1
getenforce                          # expect Enforcing
umask                               # 0077 on a STIG build
```

The install host is **permanent**, or at least its contents are. The
install directory holds the kubeadmin password, the generated kubeconfig
and the ignition configs, and chapter 12 needs the build transcript. Do
not treat it as scratch.

---

## Verify the handoff bundle

Prep's output is six artifacts and four facts, listed in
[prep 08 — what prep owes the install side](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#what-prep-owes-the-install-side).
Check them against
[prep's handoff contract](https://github.com/bgregori/disconnected-prep/blob/main/checklists/handoff-contract.md)
with the prep engineer present. That conversation takes fifteen minutes
and is the cheapest step in this repository.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
cd ${OCP_INSTALL_ROOT}/handoff

sha256sum -c SHA256SUMS

ls -l install-config-fragment.yaml \
      pull-secret.json \
      certs/rootCA.pem \
      imageset-config.yaml
ls -l cluster-resources/
ls -l bin/openshift-install-fips bin/oc
```

`imageset-config.yaml` looks like a record-keeping file and is not. It is
the only authoritative statement of what exists in the registry, and
chapters 6 and 9 read it to decide whether an operator can be installed at
all. If it is missing, go back to prep rather than guessing from the
registry contents.

Then prove the installer binary runs on this host — on a hardened build a
freshly copied binary will not:

```sh
# ===== RUN ON: THE INSTALL HOST =====
sudo install -m 0755 -o root -g root \
  ${OCP_INSTALL_ROOT}/handoff/bin/openshift-install-fips /usr/local/bin/
sudo install -m 0755 -o root -g root \
  ${OCP_INSTALL_ROOT}/handoff/bin/oc /usr/local/bin/

sudo restorecon -v /usr/local/bin/openshift-install-fips /usr/local/bin/oc
sudo fapolicyd-cli --file add /usr/local/bin/openshift-install-fips
sudo fapolicyd-cli --file add /usr/local/bin/oc
sudo fapolicyd-cli --update

openshift-install-fips version
oc version --client
```

> ⚠️ **STIG** Relabel first, then trust: `restorecon` changes the file, so
> adding it to the fapolicyd database beforehand achieves nothing. The
> trust database is per-host — prep doing this on the registry host did
> nothing for this one. Background in
> [prep's FIPS/STIG appendix](https://github.com/bgregori/disconnected-prep/blob/main/docs/appendix-fips-stig.md).

`openshift-install-fips version` must report the version prep mirrored,
with a release image reference resolving to **your** registry rather than
`quay.io`. A reference to quay.io means you have the wrong binary.

---

## The environment, checked from where it matters

Four facts about the target network. Every one of them is confirmable in
under a minute now, and every one of them, discovered later, costs a
reinstall or a change window.

> ⚠️ **None of these may be checked from the install host, and none may be
> checked from the registry host.** The question is always what a *cluster
> node* will see. The install host frequently sits on a management VLAN
> with its own resolver and its own routes; a name that resolves there and
> not on the node network is the single most common cause of an agent
> install that hangs at bootstrap with nothing useful in the logs.
>
> Before the cluster exists, "a node" means any host already on the node
> network — a jump box, an existing node, the Tang server. After it
> exists, use a debug shell.

### Registry reachable from the node network

```sh
# ===== RUN ON: A NODE =====
dig +short registry.airgap.local
curl -kI https://registry.airgap.local:8443/v2/
```

**`401` is the pass.** The registry API answering "who are you" proves it
is serving `/v2/` and not merely listening. `-k` is correct here and only
here: this host has no reason to trust a CA that lives on the registry
host, and the cluster gets that CA properly as `additionalTrustBundle` —
see [02-install-config.md](02-install-config.md). Chasing the certificate
error from here hides whether DNS and routing work, which is the actual
question.

Check the certificate was issued for the name the cluster will use, too,
because it fails late and expensively:

```sh
# ===== RUN ON: A NODE =====
openssl s_client -connect registry.airgap.local:8443 \
  -servername registry.airgap.local </dev/null 2>/dev/null |
  openssl x509 -noout -subject -ext subjectAltName
```

The `subjectAltName` must contain the exact FQDN that appears in
`imageDigestSources`.

### DNS

```sh
# ===== RUN ON: A NODE =====
dig +short api.<cluster>.<base-domain>
dig +short test.apps.<cluster>.<base-domain>      # proves the wildcard
```

Both are required, including on a single-node cluster. Querying the
wildcard with a literal `*` tests nothing — use any name under `.apps.`.

Reverse records matter too on some agent-based installs.

> **TODO:** needs validation on real hardware — whether the agent-based
> installer requires PTR records for the node addresses in this topology,
> and what it reports when they are absent. State the requirement only
> once it has been observed.

### Time

```sh
# ===== RUN ON: A NODE =====
chronyc sources
chronyc tracking
timedatectl
```

Certificate validation fails on skew, and an airgapped network often has
no working time source at all — the usual default points at
`pool.ntp.org`, which is unreachable here. The failure presents as TLS
errors during bootstrap and does not mention time. Chapter 3 configures
chrony on the nodes themselves; this check is about whether there is
anything for them to point at.

📌 **Handoff** Record the NTP server addresses now. Chapter 3 needs them
before ignition, which is before any node can tell you it has a problem.

### VIPs

The API and ingress VIPs must be **unused** addresses on the machine
network, not allocated by DHCP, and not already answering.

```sh
# ===== RUN ON: A NODE =====
ping -c2 <api-vip>        # must NOT answer
ping -c2 <ingress-vip>    # must NOT answer
arping -c2 -I <iface> <api-vip>
```

A VIP that answers belongs to something else, and the cluster will fight
it. On single node the VIP story is different — see
[topologies/sno.md](topologies/sno.md).

---

## The mirror gate

**This is the hard gate of the chapter.** Everything above fails loudly.
This one fails silently, four chapters later, when a `Subscription` sits
in `InstallPlanPending` forever because the operator you are installing
was never mirrored.

The rule: **nothing in chapters 6 through 10 may install content that is
not already in the registry.** Specifically this repository later needs

| Chapter | Content |
|---|---|
| [09](09-compliance-operator.md) | `compliance-operator`, and the `ocp4-stig` / `rhcos4-stig` profile content it ships |
| [13](13-day2.md) | `file-integrity-operator` |
| [05](05-first-access.md), [troubleshooting](troubleshooting.md) | `must-gather` and `support-tools` diagnostic images |

Nothing identity-related appears in that list, and that is deliberate: the
IdP is Red Hat build of Keycloak running **outside** the cluster, on a
services host. Nothing about chapter 7 needs mirroring.

Check against `imageset-config.yaml` from the bundle first, because it is
the authoritative statement and it is a `grep`:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
grep -n 'name:' ${OCP_INSTALL_ROOT}/handoff/imageset-config.yaml
```

Then confirm the images are actually present in the registry, rather than
merely named in a config file — a mirror run can be configured correctly
and still have failed partway.

> **TODO:** needs validation on real hardware — the exact per-image check
> that proves the compliance content is pullable from the mirror. Prep
> established that mirrored operator images are **digest-referenced, not
> tagged**, so the obvious `oc image info <repo>:latest` fails against a
> healthy mirror, and that Quay's `_catalog` endpoint rejects basic auth.
> Work out the correct form against a real registry before writing it
> here. Until then, treat prep's
> [`80-verify-mirror.sh`](https://github.com/bgregori/disconnected-prep/blob/main/scripts/80-verify-mirror.sh)
> exit status as the gate and record who ran it, on which host, and when.

If content is missing, stop. The answer is a prep Day-2 delta — see
[13-day2.md](13-day2.md) — and that is a transfer window, measured in
days. Finding out now is the entire point of this section.

---

## The IdP facts

Chapter 7 configures the cluster to authenticate against Red Hat build of
Keycloak running outside it. Collect these from the IdP owner **now**, not
in chapter 7, because two of them require work on their side and one of
them requires a meeting.

| Fact | Notes |
|---|---|
| Issuer URL | The realm's issuer. Must be reachable from the cluster — this is an egress path the network team may not have anticipated. |
| Client ID | Created on the IdP for this cluster specifically. One per cluster. |
| Client secret | Treated as a credential from the moment it is issued. It lands in a `Secret`. |
| IdP CA | The CA that signed the IdP's serving certificate. Lands in a `ConfigMap`. Needed even if the IdP uses a CA the rest of the estate trusts, because the cluster trusts nothing by default. |
| Claim names | `preferred_username`, `email`, `name`, `groups` |
| The group that gets `cluster-admin` | A real group with real people in it. See below. |

The `groups` claim is the one that is most often missing. Keycloak does
not include group membership in the token by default, and a cluster that
authenticates perfectly but assigns nobody any privileges looks like an
RBAC problem rather than a claim-mapper problem.

> **TODO:** needs validation on real hardware — the Keycloak-side
> configuration that emits a `groups` claim in the form the cluster's
> OpenID provider expects, and what the cluster logs when it is absent.
> Verify against the RHBK version actually deployed; this has changed
> between Keycloak major versions.

📌 **Handoff** The group bound to `cluster-admin` must exist and be
populated **before** chapter 7 deletes `kubeadmin`. The order is not
negotiable: deleting the only working credential before another one is
proven leaves you with a cluster nobody can administer. Agree the group
name and its membership with whoever owns identity, in writing, now.

---

## Decide before you install

These cannot be changed after the cluster exists. Changing any of them
means a reinstall.

1. **`fips: true`.** Set at install, immutable afterwards. See
   [02-install-config.md](02-install-config.md).
2. **Boot-disk encryption, and which mode.** TPM v2, Tang/NBDE, or both
   with a threshold. Configured as a `MachineConfig` in the window between
   `create manifests` and `create ignition-configs` — see
   [03-manifests.md](03-manifests.md). Prep raises this at handoff
   precisely because it is not an `install-config.yaml` field and so gets
   missed:
   [prep 08 — disk encryption](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#disk-encryption-the-other-decision-made-at-install).
3. **Topology.** Single node, three-node compact, or multi-node. Replica
   counts are install-time. See
   [topologies/sno.md](topologies/sno.md) and
   [topologies/compact.md](topologies/compact.md).
4. **Cluster name and base domain.** Baked into every certificate the
   cluster issues.
5. **Machine, service and pod network CIDRs.** Changing the service or pod
   network after install is not supported.

A sixth is expensive for a different reason: **whether the default-deny
`NetworkPolicy` project template is in place from the start**. Adding it
later is possible but means auditing every project created in the
meantime. Chapter 3 sets it at the manifest stage for that reason.

---

Next: [02-install-config.md](02-install-config.md).
