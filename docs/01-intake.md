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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> What is uncertain is not the check but the requirement. The agent-based
> installer takes each node's name from the `hostname:` field in
> `agent-config.yaml` when one is set, and from DHCP when it is not;
> reverse DNS is what fills the gap when neither does. So whether a
> missing PTR is fatal depends on a file you have not written yet
> ([02-install-config.md](02-install-config.md)). Run the check anyway —
> it is twenty seconds — and **record what the installer actually says
> when a record is absent**, because that sentence is the thing worth
> having and nobody has seen it here.

```sh
# ===== RUN ON: A NODE =====
for ip in <node-ip-1> <node-ip-2> <node-ip-3>; do
  printf '%-16s -> %s\n' "${ip}" "$(dig +short -x "${ip}" || true)"
done
```

An empty right-hand column is the thing to resolve before boot. The
failure it guards against is a node that comes up named
`localhost.localdomain`, which does not join and does not say why — set
`hostname:` explicitly for every host in `agent-config.yaml` and the
question stops mattering.

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
| [sno](topologies/sno.md) | **LVM Storage** — if the topology is single node |
| [compact](topologies/compact.md) | **OpenShift Data Foundation** — if the topology is three-node compact |

The last two are easy to miss because they belong to a topology rather
than a chapter, and the topology is chosen elsewhere. A cluster with no
storage operator installs perfectly and then has nowhere to put a
`PersistentVolumeClaim`, which surfaces as a workload problem weeks
later rather than an install one. Check whichever applies to the shape
you are building, and only that one.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Two established facts shape this and both break the obvious command.
> Mirrored operator images are **digest-referenced, not tagged**, so
> `oc image info <repo>:latest` fails against a *healthy* mirror — a
> failure here means nothing until you know which kind it is. And Quay's
> `_catalog` endpoint rejects basic auth, so enumerating the registry
> from outside is not the route. The draft below goes through the catalog
> image instead, which **is** tagged, and reads the digests out of it.
> What is unverified is the catalog's on-disk layout under `/configs/`
> and whether prep's mirror names the catalog repository the way this
> assumes.

Point `oc` at the bundle's credentials and the bundle's CA first. It does
not find either on its own, and the error when it cannot is a 401 that
reads like a mirror problem rather than a local one:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
export REGISTRY_AUTH_FILE=${OCP_INSTALL_ROOT}/handoff/pull-secret.json
sudo cp ${OCP_INSTALL_ROOT}/handoff/certs/rootCA.pem \
        /etc/pki/ca-trust/source/anchors/mirror-rootCA.pem
sudo restorecon -v /etc/pki/ca-trust/source/anchors/mirror-rootCA.pem
sudo update-ca-trust extract
```

Then the catalog, which is the one tagged thing in the mirror:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc image info registry.airgap.local:8443/redhat/redhat-operator-index:v4.21

mkdir -p ${OCP_INSTALL_ROOT}/catalog-check
oc image extract \
  registry.airgap.local:8443/redhat/redhat-operator-index:v4.21 \
  --path /configs/:${OCP_INSTALL_ROOT}/catalog-check/

ls ${OCP_INSTALL_ROOT}/catalog-check/ | grep -E 'compliance|file-integrity'
```

A package directory present in the catalog proves the catalog knows about
the operator. It does **not** prove the operator's images came across.
For that, take one digest the catalog names and ask the registry for it
directly:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
grep -ho 'sha256:[0-9a-f]\{64\}' \
  ${OCP_INSTALL_ROOT}/catalog-check/compliance-operator/* | sort -u | head -3

oc image info registry.airgap.local:8443/compliance/<repo>@sha256:<digest>
```

`oc image info` returning a manifest is the pass. A 404 against a digest
the catalog names is the exact failure this gate exists to catch: a
mirror configured correctly that failed partway, which looks fine from
every other angle until chapter 9 hangs in `InstallPlanPending`.

Until the above has been run for real, the gate is prep's
[`80-verify-mirror.sh`](https://github.com/bgregori/disconnected-prep/blob/main/scripts/80-verify-mirror.sh)
exit status — record who ran it, on which host, and when. That is a
validated check and the block above is not; prefer it, and treat the
draft as the thing you are trying to replace it with.

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

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **Verify against the RHBK version actually deployed.** Group-membership
> mapper behaviour has changed between Keycloak major versions, and this
> is written from the general Keycloak model rather than from a
> configured realm. What is being established is a fact about the IdP, so
> get it in writing from the IdP owner as well as observing it.

On the IdP, the client used by this cluster needs a **Group Membership**
protocol mapper. The settings that matter:

> The same mapper is drafted again, in `kcadm.sh` form, at
> [07 — step 3a](07-identity.md#3a--the-keycloak-side). That is
> deliberate: here it is a fact to *collect and agree* before anything
> is built, there it is a thing to *configure*. The two must say the
> same thing — in particular both set the full-path behaviour off — and
> if you change one, change the other.

| Setting | Value | Why |
|---|---|---|
| Mapper type | Group Membership | The claim does not exist otherwise. |
| Token Claim Name | `groups` | Must match the `groups` claim name chapter 7 configures. The name is not freely chosen on one side only. |
| Full group path | **Off** | With it on the claim carries `/platform-admins`, with a leading slash. The cluster then creates a group literally named `/platform-admins`, your `ClusterRoleBinding` names `platform-admins`, and nothing matches. This is the trap. |
| Add to ID token | On | |
| Add to access token | On | |
| Add to userinfo | On | |

Prove it from the IdP side before chapter 7 goes anywhere near the
cluster, by fetching a token for a real member of the admin group and
reading the claim out of it:

```sh
# ===== RUN ON: THE IDP HOST =====
curl -s -X POST \
  "https://idp.example.mil/realms/<realm>/protocol/openid-connect/token" \
  -d grant_type=password \
  -d client_id=<client-id> \
  -d client_secret=<client-secret> \
  -d username=<a-real-member> \
  -d password=<their-password> \
  -d scope=openid |
  python3 -Ic 'import sys,json,base64
t=json.load(sys.stdin)["id_token"].split(".")[1]
print(json.dumps(json.loads(base64.urlsafe_b64decode(t+"==")),indent=2))'
```

The payload must contain `"groups": ["platform-admins", ...]` — a flat
list, no leading slashes, and the admin group present. Record this
output; chapter 12 wants evidence that group mapping was proven before
`kubeadmin` was deleted.

**What it looks like when the mapper is missing** is the reason to check
here rather than later: authentication *succeeds*. The user logs in,
`oc whoami` returns their name, and they can do nothing. `oc get groups`
is empty, the authentication operator is `Available=True`, and nothing
in any log says "no groups claim", because from the cluster's point of
view nothing failed. It reads as an RBAC problem and gets debugged as
one, for about a day.

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
2. **Boot-disk encryption, and which mode.** TPM v2 **or** Tang/NBDE —
   on the agent-based installer they do not combine, so decide which
   single failure mode the site accepts. Configured as a
   `diskEncryption` block in
   `cluster-manifests/agent-cluster-install.yaml`, which exists only
   after `agent create cluster-manifests` has run — see
   [03-manifests.md](03-manifests.md). Prep raises this at handoff
   precisely because it is not an `install-config.yaml` field and so gets
   missed:
   [prep 08 — disk encryption](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#disk-encryption-the-other-decision-made-at-install).
   The field **defaults to no encryption**, so "we didn't decide" and
   "we decided against it" produce the same cluster.
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
