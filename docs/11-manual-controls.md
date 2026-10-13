# Manual controls

The controls a scanner marks `MANUAL`: it cannot determine the answer
automatically, so somebody has to, and record it.

These are the ones that get lost. A `FAIL` appears on a remediation
list. A `MANUAL` appears nowhere — it is not a failure, so nothing
chases it, and it is not a pass, so the control is unsatisfied. The gap
is discovered during assessment.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A -l compliance.openshift.io/check-status=MANUAL
```

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The label key `compliance.openshift.io/check-status` is believed
> correct — see
> [chapter 9's selector caveats](09-compliance-operator.md#reading-the-results),
> which apply here unchanged and matter more, because a selector that
> matches nothing returns an empty list that reads as "no manual
> controls". That is the most expensive wrong answer in this chapter.
> The **full list** of `MANUAL` results the profiles produce is specific
> to the benchmark revision in use and has not been enumerated.

Enumerate it from your own scan, write it to a file, and work that file:

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
MANUAL=${OCP_INSTALL_ROOT}/evidence/$(date +%Y-%m-%d)-manual
mkdir -p ${MANUAL}

oc get compliancecheckresult -A \
  -l compliance.openshift.io/check-status=MANUAL \
  -o custom-columns=NAME:.metadata.name,SEVERITY:.severity \
  | sort | tee ${MANUAL}/manual-controls.txt | wc -l
```

A count of zero on a freshly scanned STIG baseline is not a result, it
is a broken selector. Reconcile it against the total before believing
it, exactly as chapter 9 does.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> A `ComplianceCheckResult` is believed to carry `description` and
> `instructions` fields, where `instructions` is the content author's
> text telling a human what to check by hand. If that field exists at
> your content version it is the single most useful thing in this
> chapter, because it is revision-matched and this page is not. Confirm
> the field names from `-o yaml` on one result first.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult <name> -n openshift-compliance -o yaml

# if the fields are there, the whole set in one pass:
oc get compliancecheckresult -A \
  -l compliance.openshift.io/check-status=MANUAL -o json |
  jq -r '.items[] | "## \(.metadata.name)\n\(.description // "")\n\n\(.instructions // "")\n"' \
  > ${MANUAL}/manual-instructions.md
```

That file is the real work list, and it goes in the evidence pack beside
your answers — an assessor reading "what were you asked to check" and
"what you found" side by side is the whole point of the chapter.

Work the real list, not this chapter's headings. The four below are the
ones that need the most work and the most coordination with other teams,
which is why they are called out.

---

## The login banner

**Requirement:** a consent banner is displayed before authentication,
with the wording your organisation mandates, on every interface a human
uses to reach the cluster.

**Failure mode it addresses:** without it, unauthorised access may not
be prosecutable. This is a legal control rather than a technical one,
which is exactly why engineers skip it.

The part that is routinely half-done: **"every interface" means more
than the web console.** The console, the CLI login, and the node SSH
path are three separate places, configured three separate ways, and a
banner on the console alone satisfies nobody.

### 1. Before authentication — the OAuth login template

This is the one that satisfies "before granting access". The OpenShift
OAuth server renders an HTML login page, and that page can be replaced
with your own, carrying the consent text above the username field.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The mechanism is believed to be a secret in `openshift-config` holding
> a full HTML template, referenced from `spec.templates.login` on the
> cluster `OAuth` object, with `oc adm create-login-template` producing
> a valid starting point. Uncertain: whether the generated template's
> required placeholders have changed at 4.21, and what the OAuth server
> does with a template that is missing one — a broken login page is a
> cluster nobody can log into, which puts this in the same family as
> [chapter 7's `kubeadmin` deletion](07-identity.md).

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
mkdir -p ${OCP_INSTALL_ROOT}/day2/banner
oc adm create-login-template > ${OCP_INSTALL_ROOT}/day2/banner/login.html
# edit login.html: paste the approved text, leaving every {{ }}
# placeholder and every form field exactly as generated

oc create secret generic login-template \
  --from-file=login.html=${OCP_INSTALL_ROOT}/day2/banner/login.html \
  -n openshift-config

oc patch oauth cluster --type=merge \
  -p '{"spec":{"templates":{"login":{"name":"login-template"}}}}'
```

> ⚠️ **Keep a working `kubeconfig` open in another terminal, and do not
> close it until you have logged in through the new page.** This change
> is to the authentication path itself. Reverting is
> `oc patch oauth cluster --type=json -p '[{"op":"remove","path":"/spec/templates/login"}]'`,
> which you can only run if you are still authenticated.

The approved text is usually long, and HTML is the part that goes wrong:
`&`, `<`, `>` and smart quotes pasted from a Word document will either
break the page or render as mojibake, and a consent banner with mangled
wording is not the approved wording. Paste into the template, then view
the rendered page and read it against the source character for
character. That reading **is** the evidence, not a formality.

### 2. After authentication — the console banner

`ConsoleNotification` puts a persistent band across the web console.
It is not a consent banner — it appears after login, so it satisfies a
different thing — but it is usually also required, and it is trivial.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> `console.openshift.io/v1` `ConsoleNotification` with
> `spec.location: BannerTop` is the believed shape. Do not confuse it
> with `consoles.operator.openshift.io/cluster`, which carries console
> *customization* — product name, logo, documentation links — and is a
> different object for a different purpose.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/day2/banner/console-notification.yaml =====
apiVersion: console.openshift.io/v1
kind: ConsoleNotification
metadata:
  name: classification-banner
spec:
  text: "<the approved text>"
  location: BannerTop
  color: "#fff"
  backgroundColor: "#c00"
```

### 3. The node SSH banner

A different thing entirely, configured a different way, and the one
that costs a reboot.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> On RHCOS this is a `MachineConfig` writing `/etc/issue` and
> `/etc/issue.net` and pointing `sshd` at the latter — **and therefore a
> rolling reboot**, see
> [chapter 10's reboot economics](10-remediation.md#reboot-economics).
> Batch it with the remediation rollout rather than taking a reboot of
> its own. Uncertain: whether the scanner checks `/etc/issue`,
> `/etc/issue.net`, or the `sshd` `Banner` directive, and whether
> `sshd_config.d/` drop-ins are honoured at this RHCOS version — the
> safe answer is to set all of them consistently. Also worth checking
> whether the `rhcos4-stig` profile already ships a remediation for
> this, in which case apply that instead of hand-writing one.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get complianceremediation -n openshift-compliance | grep -iE 'banner|issue|motd'
```

If a remediation exists, use it: a content-supplied remediation is
checked by the same content that scans it, and a hand-written one is a
second thing to keep in step. If none exists, a `MachineConfig` writing
the file is the fallback, and the file body must be base64-encoded into
the Ignition source — which is the second place the long approved text
gets mangled.

Verify from a node, not from the install host:

```sh
# ===== RUN ON: A NODE =====
cat /etc/issue.net
sshd -T 2>/dev/null | grep -i banner
```

### What the CLI shows

`oc login` is the interface nobody checks. Against an OpenID IdP it
sends you to a browser, where you see the OAuth login template from
step 1; against other flows it may show nothing at all.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> There is no reliable documented way to put a banner in front of a
> plain `oc login` prompt. Establish empirically what your users
> actually see — run `oc login` the way they run it and look — and if
> the answer is "nothing", that is a finding to record and discuss, not
> a gap to paper over. Writing "banner configured" when the CLI path
> shows none is precisely the untrue evidence-pack entry this
> repository is built to avoid.

📌 **Handoff** The wording is not yours to write. Get the approved text
from whoever owns it, in a form you can paste without editing, and keep
a copy of the request in the evidence pack — "this is the text we were
given, on this date, by this person" closes the question permanently.

**Evidence:** a screenshot of each interface showing the banner, dated.
This is one of the few places a screenshot is the right artifact.

---

## Audit log forwarding and retention

**Requirement:** audit records are forwarded off-cluster to a system the
cluster cannot modify, and retained for the mandated period.

**Failure mode it addresses:** audit records held only on the node that
produced them are deleted by log rotation, by a node replacement, or by
an attacker with root on that node. An audit trail an attacker can
delete is not an audit trail.

The retention period is an organisational number, not a technical one,
and it is usually longer than anyone's default. The destination is
usually a SIEM owned by another team.

This is the control with the longest lead time in the chapter, because
it needs: a destination that exists, a network path to it, a credential
or certificate, and agreement about format. In an airgapped enclave the
destination is inside the enclave, which is a smaller problem than it
sounds but still someone else's system.

**Check the mirror first.** The forwarder is an operator, and on an
airgapped cluster an operator that was never mirrored makes this control
a scheduling problem rather than a technical one — a transfer window
measured in days, via
[prep's Day-2 delta loop](13-day2.md). Find that out before you design
anything:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get packagemanifest -A | grep -iE 'logging|loki|observability'
```

Nothing listed: stop, raise the delta, and tell whoever owns the ATO
schedule today rather than in three weeks.

### What is captured, before where it goes

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The API server audit profile is believed to live on
> `apiservers.config.openshift.io/cluster` at `spec.audit.profile`, with
> values `Default`, `WriteRequestBodies`, `AllRequestBodies` and `None`.
> The default captures metadata only, which is less than a hardened
> build generally requires. Uncertain: which value your benchmark
> expects — check what the scan actually asserts rather than assuming
> the strictest is right.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get apiserver cluster -o jsonpath='{.spec.audit}{"\n"}'

oc patch apiserver cluster --type=merge \
  -p '{"spec":{"audit":{"profile":"WriteRequestBodies"}}}'

oc get clusteroperator kube-apiserver -w
```

> ⚠️ **This rolls the API servers.** Not a node reboot, but a
> control-plane rollout that takes several minutes per instance and, on
> [single node](topologies/sno.md), is an API outage. And the volume
> change is the part that bites later: `WriteRequestBodies` stores the
> request body of every mutating call, and `AllRequestBodies` stores
> reads too. Agree the retention number **and** the volume with the SIEM
> owner before you turn it up, or you will turn it back down in a month
> and have to explain why.

### Forwarding it off-cluster

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **The API group depends on which logging version prep mirrored, and
> the two are not compatible.** Logging 6.x uses
> `observability.openshift.io/v1` and requires an explicit service
> account; Logging 5.x used `logging.openshift.io/v1` and did not. A
> manifest written against the wrong one is rejected outright, which is
> the good failure — the bad one is a valid manifest that silently
> forwards nothing. Check with
> `oc api-resources | grep -i clusterlogforwarder` before writing
> anything, and treat the shape below as the 6.x case only.

```yaml
# ===== EDIT IN: ${OCP_INSTALL_ROOT}/day2/logging/audit-forwarder.yaml =====
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: audit-forwarder
  namespace: openshift-logging
spec:
  serviceAccount:
    name: audit-collector
  outputs:
    - name: siem
      type: syslog                 # or kafka / splunk / otlp, per the SIEM
      syslog:
        url: tls://<siem-host>:6514
  pipelines:
    - name: audit-to-siem
      inputRefs:
        - audit
      outputRefs:
        - siem
```

The service account needs permission to collect audit logs, which is a
separate cluster role binding and is the step that gets skipped:

```sh
# ===== RUN ON: THE CLUSTER =====
oc create serviceaccount audit-collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-audit-logs \
  -z audit-collector -n openshift-logging

oc get clusterlogforwarder audit-forwarder -n openshift-logging -o yaml
oc get pods -n openshift-logging
```

`inputRefs: [audit]` is the whole control. A pipeline that forwards
`application` and `infrastructure` but not `audit` looks like working
log forwarding on every dashboard and satisfies nothing here.

Two airgap-specific traps: the TLS trust for the SIEM endpoint is a
secret you have to create, and the enclave's internal CA is not in the
collector's trust store by default; and the SIEM hostname has to resolve
from inside the cluster, which is the enclave's DNS and not the install
host's.

📌 **Handoff** Ask the SIEM owner for three things in one message: the
destination and protocol, the retention period they will actually
provide, and confirmation that they can see the cluster's records
arriving. The third is the only one that is evidence.

**Evidence:** the forwarding configuration, plus a record from the
destination showing cluster audit events arriving, dated. Configuration
alone proves intent, not function.

---

## RBAC review

**Requirement:** cluster privileges are reviewed, and every holder of
elevated privilege is justified.

**Failure mode it addresses:** privilege accumulates. Service accounts
created for a one-off task keep their bindings; people who changed roles
keep their group membership; a binding added during an incident at 3am
is never revisited. Nobody notices because nothing breaks.

A scanner cannot do this. It can list who has what; it cannot say
whether they should.

The review that is actually useful:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterrolebinding -o wide
oc get clusterrolebinding -o wide | grep cluster-admin
oc get rolebinding -A -o wide
oc adm policy who-can '*' '*'
```

For every cluster-admin holder: is it a **group** or a user? Chapter 7
required a group binding for exactly this reason — a group binding moves
the joiner/leaver problem to the IdP, where it is already solved. A user
binding is a thing somebody has to remember, which means it is a thing
nobody will.

Then the service accounts, which are where the real surprises are:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterrolebinding -o json |
  jq -r '.items[] | select(.subjects[]?.kind=="ServiceAccount") |
         "\(.metadata.name)\t\(.roleRef.name)\t\(.subjects[].namespace)/\(.subjects[].name)"'
```

### Scoping the review

A raw dump of every binding in a fresh cluster is hundreds of lines,
almost all of it platform defaults that nobody should be reviewing by
hand. The useful artifact is the **non-default** set, and producing that
requires knowing what the default set is.

So capture the binding list immediately after install, before anything
is added, and use it as the baseline — the same trick as
[chapter 9's scan baseline](09-compliance-operator.md#why-the-baseline-comes-first),
for the same reason. Hundreds of lines nobody reads is the same as no
review at all; twelve lines of delta gets read.

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> These are generic `oc` reads and should work as written; what is
> unvalidated is whether the sorted output is **stable enough to
> `diff`** across days. Platform controllers rewrite some bindings, and
> if resource versions or ordering leak into the output the delta fills
> with noise and stops being read. If that happens, narrow the captured
> fields rather than abandoning the baseline.

```sh
# ===== RUN ON: THE CLUSTER =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
RBAC=${OCP_INSTALL_ROOT}/evidence/$(date +%Y-%m-%d)-rbac
mkdir -p ${RBAC}

oc get clusterrolebinding -o json |
  jq -r '.items[] | .metadata.name as $n | .roleRef.name as $r |
         (.subjects // [])[] | "\($n)\t\($r)\t\(.kind)\t\(.namespace // "-")/\(.name)"' |
  sort > ${RBAC}/clusterrolebindings.txt

oc get rolebinding -A -o json |
  jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.roleRef.name)"' |
  sort > ${RBAC}/rolebindings.txt

wc -l ${RBAC}/*.txt
```

Take this **once, immediately after install**, before chapter 7's group
binding and before anything else is added. That snapshot is the
reference. Every later review is a diff against it:

```sh
# ===== RUN ON: THE CLUSTER =====
diff ${OCP_INSTALL_ROOT}/evidence/<install-date>-rbac/clusterrolebindings.txt \
     ${RBAC}/clusterrolebindings.txt
```

The lines that appear are the review. Each one gets a name, a reason and
a date, or it gets removed.

If you are reading this *after* the cluster has been in use and no such
snapshot exists, you cannot reconstruct it — the install-time state is
gone. Take the snapshot now anyway, label it honestly as a late
baseline, and review the full list once by hand to get there. Doing that
twice is the cost of having skipped it once.

**Evidence:** the reviewed list, with a reviewer name and a date, and a
statement of what was removed. A review that removed nothing is
suspicious; a review that removed nothing *and says so, with reasoning*
is fine.

**Cadence:** this is not a one-off. Agree a review interval and put it
in [13-day2.md](13-day2.md)'s cadence table.

---

## MFA attestation

**CNTR-OS-000430.** Multifactor authentication is required.

**It is satisfied at the IdP, not in the cluster.** The cluster delegates
authentication to Red Hat build of Keycloak
([chapter 7](07-identity.md)); whether a second factor was presented is
decided there and the cluster never sees it. There is no cluster-side
configuration that satisfies this control and no cluster-side evidence
that it is satisfied.

This is why it is `MANUAL`, and why the evidence has to come from
somewhere else.

**Evidence** — from the IdP owner, not from the cluster:

- The RHBK realm's authentication flow, showing the second factor
  required for the realm or the client this cluster uses
- Confirmation that it applies to **this client**, not merely to the
  realm in general — a client with a more permissive flow is the
  specific gap here
- A witnessed login to the cluster requiring the second factor, dated.
  Chapter 7 step 6 already does this; capture it there rather than
  repeating it.

📌 **Handoff** Ask the IdP owner for the flow configuration as a
document, not a screenshot of a console they can change. And ask who is
notified if that flow is modified — a control satisfied at install and
quietly relaxed later is worse than one that was never satisfied,
because the evidence pack now says something untrue.

---

## Recording the answers

Each of these produces a written answer, a dated artifact, and a named
person. [12-evidence-pack.md](12-evidence-pack.md) collects them, and
[checklists/ato-evidence.md](../checklists/ato-evidence.md) is the list
to work through.

The one thing not to do: mark a `MANUAL` control satisfied because it
is obviously fine. If it were determinable, the scanner would have
determined it.

---

Next: [12-evidence-pack.md](12-evidence-pack.md).
