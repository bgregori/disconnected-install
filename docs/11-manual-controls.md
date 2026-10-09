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

> **TODO:** needs validation on real hardware — the label selector
> above, and the full list of `MANUAL` results the `ocp4-stig` and
> `rhcos4-stig` profiles actually produce at the benchmark revision in
> use. This chapter covers the four that recur; the list is longer and
> is specific to the revision. Enumerate it from a real scan rather than
> working from this chapter's headings.

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

> **TODO:** needs validation on real hardware — how each of the three is
> configured: the web console login banner, whatever the CLI login path
> presents, and the node-level SSH banner (which on RHCOS is a
> `MachineConfig`, and therefore a reboot — see
> [chapter 10's reboot economics](10-remediation.md#reboot-economics)).
>
> Establish also whether the console banner mechanism supports the
> required wording without mangling it, since the mandated text is
> usually long and contains characters that do not survive casual
> templating.

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

> **TODO:** needs validation on real hardware — the log forwarding
> configuration against the destination actually in use, including
> whether the logging operator is in prep's mirror. **Check that
> first**: if the forwarder requires an operator that was never
> mirrored, this control is blocked on a transfer window, and that is a
> schedule problem rather than a technical one. See
> [13-day2.md](13-day2.md).
>
> Establish also what the audit configuration's own profile should be,
> since the default captures less than a hardened build generally
> requires, and changing it affects volume substantially.

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

> **TODO:** needs validation on real hardware — a defensible scope for
> the review. A raw dump of every binding in a fresh cluster is hundreds
> of lines, almost all of it platform defaults that nobody should be
> reviewing by hand. The useful artifact is the **non-default** set, and
> producing that requires knowing what the default set is. Capture the
> binding list immediately after install, before anything is added, and
> use it as the baseline — the same trick as chapter 9's scan baseline,
> for the same reason.

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
