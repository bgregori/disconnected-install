# ATO evidence checklist

Work through this **together** — the engineer who built the cluster and
the ISSO. It takes about an hour and exists to turn a directory someone
was sent into a shared understanding of what this system is and what
risk it carries.

Do it before the pack is submitted, not after it is returned.

Environment: ______________________  Date: ____________

Built by: ______________________  ISSO: ______________________

---

## 1. What this system is

- [ ] `cluster-description.md` present and current
- [ ] Topology: single node ☐ · three-node compact ☐ · multi-node ☐
- [ ] OpenShift version: ____________
- [ ] Compliance Operator version: ____________
- [ ] Benchmark revision scanned against: ____________
- [ ] Dependency list complete: mirror registry, NTP, IdP, Tang (if
      used), audit destination

> The dependency list is the part most often omitted and most often
> read. Each entry is something that, if it goes away, degrades or
> stops the cluster.

## 2. Install-time controls

| Control | Evidence | ✓ |
|---|---|---|
| FIPS mode | `install-config.yaml` showing `fips: true`; install host `fips_enabled=1` | ☐ |
| FIPS installer | `openshift-install-fips` used, extracted from the local mirror | ☐ |
| Boot-disk encryption | `cryptsetup status root` from **every** node | ☐ |
| Encryption mode | TPM v2 ☐ · Tang/NBDE ☐ · both ☐ · none, accepted ☐ | ☐ |
| Supply chain | prep's `imageset-config.yaml` + transfer checksums + signed handoff contract | ☐ |
| No internet egress | network team's record of denied outbound attempts during the install window | ☐ |

- [ ] `install-config.yaml` in the pack is **redacted** — the pull
      secret removed

## 3. Authentication

| Rule | Control | Evidence | ✓ |
|---|---|---|---|
| CNTR-OS-000030 | IdP is LDAP or OpenID | `OAuth` CR showing the OpenID provider; no HTPasswd provider present | ☐ |
| CNTR-OS-000460 | As above | same | ☐ |
| CNTR-OS-000040 | `kubeadmin` removed | date, person, and the two named cluster-admins who existed at the time | ☐ |
| CNTR-OS-000430 | MFA | **from the IdP owner:** the realm/client authentication flow, plus a witnessed login | ☐ |
| CNTR-OS-000760 | Token lifetime ≤ 28800 s | `OAuth` CR read-back | ☐ |

- [ ] cluster-admin is bound to a **group**, not to individual users
- [ ] Current membership of that group, dated: ______________________
- [ ] Break-glass `kubeconfig`: where it is, and who can retrieve it:
      ______________________________________________

> The last line has no technical evidence. It is a written statement by
> a named person, and an assessor will ask for it.

## 4. Encryption at rest

- [ ] etcd encryption enabled — `APIServer` resource
- [ ] Migration **complete**, not merely configured
- [ ] Either: a demonstration that a secret is unreadable in etcd
- [ ] Or: a recorded decision **not** to run that check, with a reason

> A documented decision not to run a risky command is acceptable
> evidence. An undocumented gap is not.

- [ ] etcd backup destination and its encryption posture, in writing
      from whoever owns backups

## 5. Scan results

- [ ] **Baseline** — dated, taken before any remediation
- [ ] Baseline annotated with what had and had not been done to the
      cluster at that point
- [ ] **After** — dated, taken after remediation
- [ ] **Delta** between them
- [ ] Both profiles in both sets: `ocp4-stig` **and** `rhcos4-stig`
- [ ] Operator version and benchmark revision recorded alongside each
- [ ] Counts: baseline `FAIL` ______ → after `FAIL` ______
- [ ] Any `PASS` → `FAIL` in the delta explained
- [ ] `ERROR` results investigated, not counted as passes
- [ ] On a multi-node cluster: per-node results, not just the
      profile-level verdict

## 6. Exceptions register

- [ ] Every remaining `FAIL` has a row
- [ ] Every row has a status: Scheduled / Waived / Deviation
- [ ] **No row has an empty reason**
- [ ] Every Scheduled row has a date and an owner
- [ ] Every Waived row has an approver — the ISSO, not the engineer —
      and a review date
- [ ] Every Deviation row says what compensates for it

## 7. Documented deviations

- [ ] Controls that cannot be met in a disconnected environment are
      recorded as deviations rather than left as failures
- [ ] Any time-boxed hardening deviation during the build is recorded,
      with evidence it was reverted

## 8. Manual controls

| Control | Evidence | ✓ |
|---|---|---|
| Banner — web console | screenshot, dated | ☐ |
| Banner — CLI login | capture, dated | ☐ |
| Banner — node SSH | capture, dated | ☐ |
| Banner wording | the approved text, and who provided it, and when | ☐ |
| Audit forwarding | configuration **and** a record from the destination showing events arriving | ☐ |
| Audit retention | the period, confirmed by the destination's owner | ☐ |
| RBAC review | reviewed list, reviewer name, date, what was removed | ☐ |
| MFA attestation | from the IdP owner, as a document | ☐ |

- [ ] The **full** `MANUAL` list from the real scan was worked, not just
      these four

## 9. Ongoing

- [ ] Re-scan cadence agreed: ____________
- [ ] Who receives scan results: ____________
- [ ] RBAC review interval agreed: ____________
- [ ] Exceptions register review dates in a calendar
- [ ] IdP CA expiry: ____________
- [ ] Registry CA expiry: ____________
- [ ] Client secret rotation owner and interval: ____________
- [ ] Drift alerts (File Integrity) have a named recipient and a
      response procedure
- [ ] Understood: **patching is a transfer window**, typical lead time
      ____________

## 10. Questions to ask the ISSO directly

1. Is the baseline / after / delta structure what you expect, or do you
   have a format?
2. Do you want raw `ComplianceCheckResult` YAML, or a rendered report?
3. Who approves the waivers, and by when?
4. What re-scan cadence do you expect, and who should see the results?
5. What would you want to see that is not in this pack?

Answers: ______________________________________________________________

______________________________________________________________________

---

## Sign-off

Evidence pack complete and walked through.

Prepared by: ______________________  Date: ____________

Reviewed by (ISSO): ______________________  Date: ____________
