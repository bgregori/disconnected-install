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

These five are cited because they have been read and confirmed. Four
more are cited elsewhere — three for FIPS in
[chapter 2](02-install-config.md#fips-true) and one for etcd encryption
in [chapter 8](08-encryption-at-rest.md) — and nothing else in this
repository cites a rule ID at all. See
[the README](../README.md#on-stig-rule-ids).

> ⚠️ **These five carry no benchmark revision.** They were confirmed
> during earlier work and the revision was not written down, which is
> the exact omission this repository warns about everywhere else. The
> four cryptography rules were read at **V2R6** and say so. Re-confirm
> these against your own revision before any of them reaches an SSP,
> and record it here when you do.

One is independently corroborated: `ocp4-stig` sets
`var_oauth_token_maxage=8h` in the content, which is the 28800 seconds
CNTR-OS-000760 requires. That is not the same as having read the
benchmark, but it is more than nothing.

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

The secret is a credential from the moment it is issued. It should not
reach your shell history, and it should not sit in a file on the install
host afterwards. Whatever form the creation command takes, pass it from
standard input or a file, not as an argument — arguments are visible in
`ps` to every local account.

**The key name is not freely chosen.** The OAuth stack reads the client
secret from the key `clientSecret` and from nowhere else. A secret with
the right value under the wrong key is not an error: the identity
provider is silently not honoured, and the failure names neither the
secret nor the key.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The key name `clientSecret` is documented and is the part least likely
> to be wrong. What to check first is the handling below — that `read -s`
> leaves nothing in history on your shell, and that `shred` does
> something useful on the filesystem you are on. On tmpfs or a
> copy-on-write filesystem it does not.

```sh
# ===== RUN ON: THE CLUSTER =====
umask 077
read -rs -p 'IdP client secret: ' IDP_SECRET; echo
printf '%s' "${IDP_SECRET}" > /tmp/idp-client-secret
unset IDP_SECRET
oc create secret generic keycloak-client-secret \
  -n openshift-config \
  --from-file=clientSecret=/tmp/idp-client-secret
shred -u /tmp/idp-client-secret
```

`--from-file=clientSecret=<path>` names the key explicitly, which is the
form to use. The shorter `--from-file=<path>` takes the key from the
file's *basename*, so it only works if the file happens to be called
`clientSecret` — and it fails silently in exactly the way described
above when it is not. Do not use `--from-literal`: that puts the
credential in `argv`.

Confirm the key name without printing the value:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get secret keycloak-client-secret -n openshift-config \
  -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'
```

That must print exactly `clientSecret`, and nothing else. It prints key
names only, which matters because this terminal transcript is an
evidence artifact — see
[12-evidence-pack.md](12-evidence-pack.md).

---

## Step 2 — the IdP CA

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

To capture the chain as presented rather than as you were told it is:

```sh
# ===== RUN ON: THE CLUSTER =====
openssl s_client -connect <idp-host>:<port> -servername <idp-host> \
  -showcerts </dev/null 2>/dev/null \
  | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' > idp-ca.pem
```

Then strip the leaf from the top of that file. The bundle the cluster
needs is the issuing chain, not the serving certificate.

**The key name is not freely chosen here either.** The certificate must
be under `ca.crt`, and as with the client secret a wrong key means the
identity provider is silently not honoured.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Verify first that the PEM you load is the issuing chain and not the
> leaf — the `sed` extraction above keeps everything the server sent,
> leaf included, and a bundle containing the leaf can validate today and
> fail at the next certificate renewal.

```sh
# ===== RUN ON: THE CLUSTER =====
oc create configmap keycloak-idp-ca \
  -n openshift-config \
  --from-file=ca.crt=idp-ca.pem
oc get configmap keycloak-idp-ca -n openshift-config \
  -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'
```

That must print exactly `ca.crt`. `--from-file=idp-ca.pem` would give
you a key named `idp-ca.pem`, a `ConfigMap` that looks correct in
`oc get`, and an IdP that never works.

---

## Step 3 — the OAuth CR

The cluster has exactly one `OAuth` resource, named `cluster`. Editing it
is how identity providers are added, and an empty `identityProviders`
list is how OpenShift ends up with only `kubeadmin`.

What is known and is not a guess:

- **The provider type must be OpenID** (or LDAP). HTPasswd is prohibited
  by CNTR-OS-000030 and CNTR-OS-000460. There is no intermediate
  HTPasswd step in this build.
- **`groups` is the claim that is usually missing.** Keycloak does not
  emit group membership by default. A cluster that authenticates
  perfectly but assigns nobody any privileges is a claim-mapper problem
  presenting as an RBAC problem, and people lose a day to it.

### 3a — the Keycloak side

Two things have to be true on the IdP before the cluster side can
work, and neither is the default.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> This is the highest-uncertainty block in the chapter. The group
> membership mapper's configuration key names have changed between
> Keycloak major versions, and no RHBK version has been configured
> against a cluster here — see
> [VALIDATION.md](../VALIDATION.md#not-verified--the-honest-list) and
> the related gap in
> [01-intake.md](01-intake.md#the-idp-facts). Verify against the RHBK
> version actually deployed, in its admin console, before trusting the
> CLI form below. Check `full.path` first: it decides the spelling of
> the group name the cluster will see, and step 4 turns on that
> spelling.

```sh
# ===== RUN ON: THE IDP HOST =====
KC=/opt/keycloak/bin/kcadm.sh
REALM=ocp
${KC} config credentials --server https://idp.services.local:8443 \
  --realm master --user admin
CLIENT_UUID=$(${KC} get clients -r "${REALM}" -q clientId=openshift \
  --fields id --format csv --noquotes)
${KC} create "clients/${CLIENT_UUID}/protocol-mappers/models" -r "${REALM}" \
  -s name=groups \
  -s protocol=openid-connect \
  -s protocolMapper=oidc-group-membership-mapper \
  -s 'config."claim.name"=groups' \
  -s 'config."full.path"=false' \
  -s 'config."id.token.claim"=true' \
  -s 'config."access.token.claim"=true' \
  -s 'config."userinfo.token.claim"=true'
```

`full.path=false` emits `platform-admins`. `full.path=true` emits
`/platform-admins`, with a leading slash, and the binding in step 4
would have to be spelled that way too. Pick one deliberately and write
it down — this is the single most common cause of "authentication works
but nobody has any permissions".

The other IdP-side requirement is the redirect URI. The Keycloak client
must permit
`https://oauth-openshift.apps.<cluster>.<base-domain>/oauth2callback/<idp-name>`,
where `<idp-name>` is the `name` field of the provider in the `OAuth`
CR below — `keycloak` as written here. Change one and you must change
the other. A mismatch fails at the IdP, with an IdP-side error page the
cluster never sees and never logs.

### 3b — the cluster side

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> Check `extraScopes` first. Requesting a scope the realm does not
> define makes the whole authorization request fail with
> `invalid_scope`, before any claim mapping happens — so a `groups`
> entry here that RHBK does not recognise breaks login entirely rather
> than merely omitting groups. If login fails outright after applying
> this, remove `extraScopes` before touching anything else.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/oauth-cluster.yaml =====
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: keycloak
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: openshift
      clientSecret:
        name: keycloak-client-secret
      ca:
        name: keycloak-idp-ca
      extraScopes:
      - email
      - profile
      - groups
      claims:
        preferredUsername:
        - preferred_username
        name:
        - name
        email:
        - email
        groups:
        - groups
      issuer: https://idp.services.local:8443/realms/ocp
```

Notes on fields that are not interchangeable:

- `issuer` must be `https`, with no query string and no fragment, and
  must match the `iss` claim the IdP actually puts in the token
  exactly. A trailing slash is a mismatch.
- `clientSecret.name` and `ca.name` are references to the objects from
  steps 1 and 2, resolved in `openshift-config`. The namespace is not
  configurable.
- Each `claims` entry is an ordered list and the **first non-empty**
  claim wins. That is a fallback mechanism, not an and.
- `mappingMethod: claim` is the default and the right choice here: it
  refuses to log a user in if their identity name is already claimed by
  a different identity. The permissive alternatives exist to migrate
  between providers and have no place in a new build.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc apply -f ${OCP_INSTALL_ROOT}/cluster/oauth-cluster.yaml
```

Applying the `OAuth` CR triggers a rollout of the authentication
operator. Watch it rather than immediately trying to log in:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator authentication -w
```

A failed configuration leaves the operator `Degraded` with a message
that is usually specific. Read it before changing anything.

The login page gives you nothing useful, so these are the three places
to look instead:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> These are read-only and safe to run. What has not been established is
> which of them actually carries the useful message for a *wrong claim
> mapping* as opposed to a wrong secret or an untrusted CA — those are
> different failures and they do not all surface in the same place.
> Record which one told you, when it does.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusteroperator authentication \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{.message}{"\n\n"}{end}'
oc -n openshift-authentication logs -l app=oauth-openshift --tail=100
oc -n openshift-authentication get events --sort-by=.lastTimestamp | tail -20
```

A wrong or missing `clientSecret` key, and a CA that does not validate
the IdP's chain, both produce a `Degraded` operator. A wrong *claim*
mapping does not — the operator is perfectly healthy, login succeeds,
and the problem only appears as missing privileges. That asymmetry is
why step 4 reads the group name back from the cluster rather than
trusting what the IdP owner told you.

---

## Step 4 — bind a real group to cluster-admin

Before this, the only cluster-admin is `kubeadmin` and the break-glass
certificate. After it, there is a group of named humans.

> ⚠️ **STIG** Bind a **group**, not a user. A user binding has to be
> maintained by hand as people join and leave, which means it will not
> be, and an account with cluster-admin belonging to someone who left is
> a finding that is both common and indefensible. A group binding moves
> that lifecycle to the IdP, where it already exists.

**The spelling is the trap.** The name in the claim and the name you
type into the binding are both just strings. A mismatch binds a group
that does not exist — silently, successfully, and with no error from
anything. `oc get clusterrolebinding` will show you a perfectly valid
binding to nobody.

So do not type the group name from memory, from the IdP owner's email,
or from the Keycloak console. Read it back from the cluster.

### First, make the group exist

With `claims.groups` configured, OpenShift creates a `Group` object the
first time a member of that group logs in. Before any login, `oc get
groups` is empty and there is nothing to bind to. Have one person — the
non-privileged tester from step 6 will do — log in through the IdP
once, then:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The specific thing to confirm is that a login actually materialises
> `Group` objects on this version, rather than only `User` and
> `Identity`. If `oc get groups` stays empty after a successful login,
> the `groups` claim is not arriving and you are back in step 3a — the
> mapper, or `extraScopes`, or `full.path`.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get groups
oc get identity -o custom-columns=NAME:.metadata.name,USER:.user.name
oc get user -o name
```

Copy the group name out of that output. If it has a leading slash, your
Keycloak mapper has `full.path=true` and the binding needs the slash
too — or go back and set it to `false`, which is the cleaner answer.

### Then bind it

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/cluster/rbac-platform-admins.yaml =====
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins-cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: platform-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
```

Written as a file rather than `oc adm policy add-cluster-role-to-group`
because the file is the evidence. Chapter 12 wants the binding as a
reviewed artifact, not as a command somebody says they ran.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
oc apply -f ${OCP_INSTALL_ROOT}/cluster/rbac-platform-admins.yaml
```

Confirm the binding exists and names what you think it names:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterrolebinding -o wide | grep cluster-admin
oc get clusterrolebinding platform-admins-cluster-admin \
  -o jsonpath='{.subjects[*].kind}/{.subjects[*].name}{"\n"}'
```

And confirm it *resolves*, which is the part the previous command
cannot tell you. Impersonation answers the question without needing the
human in the room:

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> `--as-group` with `--as` is the documented way to test a binding
> without the account; what is unverified is whether the authorizer
> treats an impersonated group identically to a claim-provided one on
> this version. A `yes` here is strong evidence but it is not a
> substitute for step 6, which stays mandatory.

```sh
# ===== RUN ON: THE CLUSTER =====
oc auth can-i '*' '*' --all-namespaces \
  --as=probe-not-a-real-user --as-group=platform-admins
oc auth can-i '*' '*' --all-namespaces \
  --as=probe-not-a-real-user --as-group=platform-admins-typo
```

The first must return `yes`. The second must return `no`. If both
return `yes` you have a binding somewhere that grants more than you
think, and you need to find it before step 7.

---

## Step 5 — set the token lifetime

**CNTR-OS-000760** requires `accessTokenMaxAgeSeconds` no greater than
**28800** — eight hours. It is a field on the same `OAuth` CR named
`cluster`.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The uncertain part is the path, `spec.tokenConfig`. Confirm it with
> `oc explain oauth.spec.tokenConfig` against your own cluster before
> patching — a merge patch against a path that does not exist creates
> the path, succeeds, and configures nothing, which is the worst
> possible outcome for a control you then declare satisfied.

```sh
# ===== RUN ON: THE CLUSTER =====
oc explain oauth.spec.tokenConfig
oc patch oauth cluster --type merge \
  -p '{"spec":{"tokenConfig":{"accessTokenMaxAgeSeconds":28800}}}'
oc get oauth cluster \
  -o jsonpath='{.spec.tokenConfig.accessTokenMaxAgeSeconds}{"\n"}'
```

The read-back must print `28800`. An empty line means the patch landed
somewhere else and the control is **not** satisfied, regardless of what
the patch command reported.

If you have not yet applied step 3's `OAuth` CR, add `tokenConfig` to
that file instead and save yourself a second rollout of the OAuth
server. The two are the same resource; they are separate steps here
only because the rule is separate.

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

**This is the one command in the repository where a wrong guess is
unrecoverable.** Red Hat's own documentation says so plainly: run it
before another user is `cluster-admin` and OpenShift must be
reinstalled. There is no undo, there is no recovery procedure, and in
an airgapped enclave a reinstall is a transfer window and a change
board, not an afternoon.

So the gate comes first, and it comes before you read the command.

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

**The gate is not provisional.** The command below is a draft and will
be replaced when it is run. The six boxes above are not a draft, are
not replaced, and do not move. If a future version of this chapter has
a validated command and no gate, that is a regression.

### The command

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The credential is a `Secret` named `kubeadmin` in `kube-system` — not
> a `User`, which is why `oc delete user kubeadmin` finds nothing and
> leaves the credential working. Confirm with the `oc get` below that
> the object exists and is the one you expect **before** deleting it;
> that read is the last reversible thing you will do in this chapter.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get secret kubeadmin -n kube-system
oc delete secret kubeadmin -n kube-system
```

### Afterwards

```sh
# ===== RUN ON: THE CLUSTER =====
oc get secret kubeadmin -n kube-system
oc get clusteroperator authentication
```

`NotFound` on the first command is the pass, and it is the line to
capture for the evidence pack.

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
