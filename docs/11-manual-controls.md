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
> The label key is confirmed, but
> [chapter 9's selector caveats](09-compliance-operator.md#reading-the-results)
> apply here unchanged and matter more than anywhere else: a selector
> that matches nothing returns an empty list that reads as "no manual
> controls". That is the most expensive wrong answer in this chapter.
> What has **not** been established is how the benchmark's control
> statuses map onto `MANUAL` check results on a running cluster —
> which is the thing the command above actually returns.

### How big this chapter is

The benchmark's own control file answers the question the scan does
not, and the number is smaller and stranger than you would guess.
At V2R6 there are **83 controls**:

| Status in the benchmark | Count |
|---|---|
| `automated` | 75 |
| `manual` | 5 |
| `not applicable` | 2 |
| `partial` | 1 |

The five `manual` ones are the honest ones: images limited to offered
capabilities, PPSM registration of ports and protocols, separation of
user and management functionality, Alert Manager receivers for audit
failures, and privileged access for vulnerability scanning. Three of
those carry no rules at all.

**But the real scope is nine or ten, not five**, because two controls
marked `automated` cannot be settled by a scan:

- **CNTR-OS-000090** (RBAC, **high**) — marked automated, but its only
  rule has no OVAL and no CEL. The entire check is prose ending "if
  these results show users with privileged access that do not require
  that access, this is a finding." A human decides. See below.
- **CNTR-OS-000130** (the banner, low) — automated, but all four rules
  are existence checks that never read your text. See above.

And the two `not applicable` controls are not free either — they are
free *only if somebody writes down why*, which is the MFA attestation
at the end of this chapter.

> 🚧 **DRAFT -- NOT VALIDATED.** These counts are read from the
> benchmark's control file at V2R6, not from a scan. How many results
> actually come back labelled `MANUAL` on a cluster is a different
> number and has not been measured — control status and check-result
> status are not the same thing. Record both.

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
than the web console.** One control covers it — **CNTR-OS-000130**,
level low, nominally automated — and it lists **four** rules, because
there are four surfaces, not the three an earlier draft of this chapter
assumed:

| Surface | Mechanism | Rule |
|---|---|---|
| Console, before login | OAuth login template | `oauth_login_template_set` |
| Console, IdP chooser | OAuth provider-selection template | `oauth_provider_selection_set` |
| Console, after login | `ConsoleNotification` | `classification_banner` |
| `oc` CLI | `motd` ConfigMap | `openshift_motd_exists` |

The IdP-chooser page is the one nobody thinks of. It appears when more
than one identity provider is configured, its stated rationale is
branding rather than consent, and it still has to pass.

> ⚠️ **All four rules are existence checks. None of them reads your
> text.** `classification_banner` matches `.spec.text` against `".*"` —
> which an empty string satisfies. `openshift_motd_exists` wants
> `.data.message` to be non-empty. The two template rules check only
> that a template name is set.
>
> So a cluster with four blank banners **passes the banner control**.
> The DISA check text is a human reading the words; the scanner is not
> that human. A green `CNTR-OS-000130` is evidence that four objects
> exist, and nothing more — which is why the evidence for this control
> is screenshots, and why this chapter is in the manual-controls
> chapter at all.

**Node SSH is deliberately absent from that list.** See below; the
answer there is not what you would expect.

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

### 3. The node SSH banner — the STIG does not want one

An earlier draft of this chapter had a `MachineConfig` here writing
`/etc/issue` and `/etc/issue.net`, costing a rolling reboot. **That was
the wrong question.**

> ⚠️ **The STIG requires node SSH to be turned off.**
> **CNTR-OS-001010**, level **high**: *"Red Hat Enterprise Linux CoreOS
> (RHCOS) must disable SSHD service."* Rule `service_sshd_disabled`,
> pulled into two further controls. There is no `/etc/issue` rule, no
> `sshd` banner rule, nothing — the RHEL STIG's banner rules **do not
> carry over** to `rhcos4-stig`, which is the natural assumption and is
> wrong.
>
> So there is no node-SSH banner to configure, and writing one is
> effort spent hardening an interface the benchmark says should not be
> listening. The control to satisfy is "sshd is disabled", and the
> evidence is that it is.

This has a consequence worth facing early rather than at remediation
time: **`oc debug node/` is how you inspect a node from here on.**
Every `RUN ON: A NODE` block in this repository assumes that, which is
why none of them is written as an `ssh` command. If your operational
procedures assume SSH to nodes, that assumption and this control are
in conflict, and the conversation belongs at intake rather than at
assessment.

> 🚧 **DRAFT -- NOT VALIDATED.** The control and the rule name are read
> from the benchmark's control file, not from a cluster. Whether
> `service_sshd_disabled` ships an automated remediation, and what it
> does to an in-progress debug session, has not been established.
> Verify before running, then update VALIDATION.md.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get compliancecheckresult -A | grep -i sshd
```

```sh
# ===== RUN ON: A NODE =====
systemctl is-enabled sshd.service
systemctl is-active sshd.service
```

If a local-console banner is required by something **other** than the
OpenShift STIG — a site policy, or the RHEL STIG applied to the
hardware — then it is a `MachineConfig` writing `/etc/issue`, and it
costs a rolling reboot; batch it with
[chapter 10's rollout](10-remediation.md#reboot-economics) rather than
taking a reboot of its own. Record it as a site requirement, not as a
CNTR-OS control, because it is not one.

### 4. What the CLI shows

`oc login` is the interface nobody checks, and it is the one the
earlier draft got most wrong: it said there was no documented way to
put a banner in front of it. **There is.**

The mechanism is a `ConfigMap` named `motd` in namespace `openshift`,
with the key `data.message`. `oc` reads it on login and prints it.
That is what `openshift_motd_exists` checks, and the DISA check text is
literally "Login to OpenShift using the oc cli tool… If the DoD Notice
and Consent Banner is not displayed, this is a finding."

Two caveats, and both matter for what you can honestly write down:

> ⚠️ **It prints *after* authentication, not before.** `oc` fetches the
> token first and displays the message on the way out. The SRG wording
> is "before granting access", and strictly this does not do that.
> DISA accepts it anyway — the check text asks only whether the banner
> appeared. Do not write "consent obtained before access" for the CLI
> path; write what it is.
>
> ⚠️ **A permissions failure is silently swallowed.** If the user
> cannot read that ConfigMap, `oc` ignores the error and prints
> nothing. No warning, no non-zero exit. So the banner can be
> correctly configured, the rule can pass — it checks the ConfigMap,
> not the user's access to it — and no human ever sees it.
>
> Whether an ordinary user can read it depends on RBAC that may not be
> granted by default. Test as a real user, not as yourself:

```sh
# ===== RUN ON: THE CLUSTER =====
oc auth can-i get configmap/motd -n openshift --as=<a-real-user>
```

A `no` there means the banner never displays for that person, and the
scan will not tell you. Then log in as them and look.

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
> The audit profile is on `apiservers.config.openshift.io/cluster` at
> `spec.audit.profile`, values `Default`, `WriteRequestBodies`,
> `AllRequestBodies` and `None` — confirmed, as is **which one the
> benchmark expects**: `ocp4-stig` sets
> `var_openshift_audit_profile=WriteRequestBodies`, so that is the
> value the scan asserts and there is no need to guess at the
> strictest. What is drafted is the patch below having been run.
>
> `Default` logs metadata on reads and writes but no request bodies —
> except OAuth access-token requests. `WriteRequestBodies` adds the
> body of every `create`, `update`, `patch`, `delete` and
> `deletecollection`.

```sh
# ===== RUN ON: THE CLUSTER =====
oc get apiserver cluster -o jsonpath='{.spec.audit}{"\n"}'

oc patch apiserver cluster --type=merge \
  -p '{"spec":{"audit":{"profile":"WriteRequestBodies"}}}'

oc get clusteroperator kube-apiserver -w
```

> ⚠️ **This rolls the API servers.** Not a node reboot, but a
> control-plane rollout that takes several minutes per instance and, on
> [single node](topologies/sno.md), is an API outage. Watch the
> `NodeInstallerProgressing` condition reach `AllNodesAtLatestRevision`
> rather than guessing when it is done. And the volume change is the
> part that bites later: `WriteRequestBodies` stores the request body
> of every mutating call, and `AllRequestBodies` stores reads too.
> Agree the retention number **and** the volume with the SIEM owner
> before you turn it up, or you will turn it back down in a month and
> have to explain why.

> ⚠️ **Do not write "all write request bodies are captured" in the
> pack.** Even under `WriteRequestBodies`, three object types are
> logged at **metadata level only** — `Secret`, `Route` and
> `OAuthClient` — as are the OpenShift OAuth server's own events. That
> is deliberate and correct, since the bodies are the secrets. But it
> is an exception to the sentence everyone writes, and it is the kind
> of overstatement an assessor checks. Write the exception alongside
> the profile name.
>
> Scope, while you are recording it: the profile governs the OpenShift
> API server, the Kubernetes API server, the OpenShift OAuth API
> server and the OpenShift OAuth server. Not the nodes, and not the
> kubelet.

### Forwarding it off-cluster

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> On OpenShift 4.21 the API group is `observability.openshift.io/v1`.
> `logging.openshift.io/v1` was **removed** in Logging 6.0, along with
> the `ClusterLogging` resource and the Fluentd and Elasticsearch
> collectors; Vector is the only collector now, and there is no
> automated 5.x → 6.x upgrade. The shape below is the 6.x case and is
> the only one that applies here. Check with
> `oc api-resources | grep -i clusterlogforwarder` anyway.
>
> ⚠️ **The STIG's own fix text is wrong on 4.21.** The remediation
> DISA ships for `audit_log_forwarding_enabled` at V2R6 tells you to
> apply a `logging.openshift.io/v1` `ClusterLogForwarder`, which does
> not exist on this cluster. Applied verbatim it fails. The *rule*
> has caught up and checks both API groups; the fix text an assessor
> reads has not. Expect to explain this, and keep the explanation
> short: the benchmark is pinned to an older logging line than the
> platform ships.
>
> **Version matters as a mirror-gate item, not just a detail.** OCP
> 4.21 is supported by Logging **6.6** or **6.5**; 6.4 reached end of
> maintenance in July 2026. Whichever prep mirrored is what you have,
> and if it mirrored 6.4 or a 5.x line, this chapter stops until
> there is another transfer window.

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
separate cluster role binding — and the order is not optional:

> ⚠️ **Bind the role first. Adding `audit` to `inputRefs` without the
> `collect-audit-logs` binding does not fail the manifest — the
> operator deletes the entire collector DaemonSet.** All log
> collection stops, not just audit. The cluster goes from forwarding
> application and infrastructure logs to forwarding nothing, and the
> cause is a missing RBAC grant rather than anything the forwarder
> says about itself.

```sh
# ===== RUN ON: THE CLUSTER =====
oc create serviceaccount audit-collector -n openshift-logging
oc adm policy add-cluster-role-to-user collect-audit-logs \
  -z audit-collector -n openshift-logging

# confirm the binding exists BEFORE applying the forwarder
oc get clusterrolebinding -o wide | grep collect
```

Then apply the forwarder, and check the resource agrees it is allowed:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterlogforwarder audit-forwarder -n openshift-logging -o yaml
oc get clusterlogforwarder audit-forwarder -n openshift-logging \
  -o jsonpath='{.status.conditions[?(@.type=="Authorized")]}{"\n"}'
oc get pods -n openshift-logging
oc get daemonset -n openshift-logging
```

The `Authorized` condition is the one that catches the trap above, and
the DaemonSet being present is the blunt version of the same check.

`inputRefs: [audit]` is the whole control. A pipeline that forwards
`application` and `infrastructure` but not `audit` looks like working
log forwarding on every dashboard and satisfies nothing here. The
benchmark's own check is exactly that:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterlogforwarders -n openshift-logging -o json |
  jq -r '.items[].spec.pipelines[].inputRefs | contains(["audit"])'
```

**Two controls rest on this, and one of them is CAT I.**
CNTR-OS-000170 (**high**) — "must initiate session audits at system
startup" — and CNTR-OS-000220 (medium) — "must provide the ability to
send audit logs to a central enterprise repository" — list the same
four rules, including `audit_log_forwarding_enabled` and
`cluster_logging_operator_exist`. Forwarding is not a nice-to-have
medium finding; skipping it fails a high one.

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
whether they should — and unusually, the benchmark agrees while
appearing not to.

> **CNTR-OS-000090 is marked `automated` and is not.** It is level
> **high**, and its rule `rbac_least_privilege` ships no OVAL, no CEL
> and no template. Its whole check is the prose below, and its failure
> clause is the string "RBAC needs review". So it will appear in your
> results as a check with a verdict, and that verdict means only that
> the scanner looked at nothing. Budget for it here even though it
> will not show up in a `MANUAL` selector.

The benchmark's own prescribed review — worth using verbatim, because
it is what the assessor's check text says:

```sh
# ===== RUN ON: THE CLUSTER =====
oc describe clusterrole.rbac
oc describe clusterrolebinding.rbac
oc describe rolebinding.rbac
```

"If these results show users with privileged access that do not require
that access, this is a finding." That is the whole test.

More usefully for actually finding things:

```sh
# ===== RUN ON: THE CLUSTER =====
oc get clusterrolebinding -o wide | grep cluster-admin
oc get rolebinding -A -o wide
oc adm policy who-can '*' '*'
```

> **A citation note that matters if the pack is challenged.**
> `oc adm policy who-can` and the three `oc describe …rbac` commands
> are documented by Red Hat and are safe to cite as procedure.
> `oc auth can-i --list --as=<user>` — which is the command most
> engineers reach for and which does work — **does not appear in the
> OpenShift authentication and authorization documentation at all.**
> It is inherited kubectl behaviour. Use it to investigate; cite the
> documented ones in the pack.

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

The benchmark says so itself. CNTR-OS-000430 is marked **not
applicable** in the control file, with the justification: *"Applicable
to Identity Management Provider and not OCP… Verify with IdM service
provider admins that the IdM meets the requirements."* So the
attestation below is not you working around a gap in the scan — it is
the evidence the benchmark explicitly asks for in place of a check.

> **The same justification covers CNTR-OS-000460, and that one carries
> 27 SRG requirements.** It is level **high**, it is also marked not
> applicable, and its justification pushes the entire FIPS-validated
> LDAP/OIDC question onto the identity provider. That makes this
> section the highest-leverage paragraph in the chapter: one
> conversation with the IdP owner discharges two controls, one of them
> high, and twenty-seven SRG mappings behind them.
>
> It also means the IdP owner is answering an accreditation question,
> not doing you a favour. Ask in those terms, and get it in writing
> from someone who can be held to it.

This is why the evidence has to come from somewhere else.

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
