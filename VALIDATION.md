# Validation record

What in this repository has actually been executed against real
infrastructure, and what has not. Kept so that anyone handed this repo
can tell proven behaviour from reasoned behaviour.

The short version, stated first because it is the only thing most
readers need:

> **Nothing in this repository has been executed against a cluster.**

This is a skeleton. The chapter structure, the ordering, the decisions
and the failure modes are real and reasoned. The procedures are, for the
most part, deliberately absent.

---

## Why it is empty rather than plausible

A reader with a printed copy cannot tell a verified command from an
invented one. Both are monospaced. Both look authoritative. The second
costs a day, or a reinstall, or — in
[chapter 7](docs/07-identity.md#step-7--delete-kubeadmin) — a cluster
nobody can administer.

So where a procedure has not been run, this repository writes the
section heading, states what the step must achieve and the failure mode
it prevents, and marks it:

```
> **TODO:** needs validation on real hardware -- <what specifically>
```

An empty section is a known gap. A fabricated one is a trap. The whole
repository is built on preferring the first.

---

## What *has* been validated, elsewhere

Everything this repository inherits from
[disconnected-prep](https://github.com/bgregori/disconnected-prep),
which was run end to end on 2026-10-02 against a genuinely airgapped,
FIPS-enabled, STIG-hardened RHEL 9.6 environment — a real 29 GB mirror
of OpenShift 4.21.34 plus operators, across a private subnet with no NAT
gateway, no internet gateway route and no VPC endpoints.

Carried into this repository and relied upon:

| Fact | Source |
|---|---|
| `openshift-install-fips` extracted from the local registry reports 4.21.34 with a release reference resolving to the local registry | [prep VALIDATION](https://github.com/bgregori/disconnected-prep/blob/main/VALIDATION.md) |
| A `fips: true` cluster requires both the FIPS binary **and** a host in FIPS mode | [prep 01](https://github.com/bgregori/disconnected-prep/blob/main/docs/01-prerequisites.md#fips-mode-host-versus-cluster) |
| The three install-config requirements, and that `imageDigestSources` is the one forgotten | [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#the-three-install-config-requirements) |
| oc-mirror writes **multiple** YAML documents into one IDMS file; copying the first alone breaks operator pulls | prep VALIDATION, bug 1 |
| Disk encryption is a `MachineConfig` at the manifest stage, TPM v2 or Tang, and FIPS forces `aes-cbc-essiv:sha256` | [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#disk-encryption-the-other-decision-made-at-install) |
| `oc apply -f cluster-resources/` then `disableAllDefaultSources` | [prep 08](https://github.com/bgregori/disconnected-prep/blob/main/docs/08-handoff.md#after-the-install-completes) |
| Applying IDMS/ITMS triggers a rolling restart of every node; on single node that is a full API outage | prep 08 |
| Mirrored operator images are **digest-referenced, not tagged** — `repo:latest` checks fail against a healthy mirror | prep VALIDATION |
| Quay's `_catalog` endpoint rejects basic auth | prep VALIDATION |
| Signature artifacts are **files**, not a `signatures/` directory | prep VALIDATION, bug 13 |
| On a hardened host, a freshly installed binary needs `restorecon` **then** `fapolicyd-cli --file add`, in that order, per host | prep 01, prep VALIDATION |
| `401` from a registry's `/v2/` is the pass, not a failure | [prep 05](https://github.com/bgregori/disconnected-prep/blob/main/docs/05-registry.md#trust-the-ca) |
| Incremental mirroring depends on `working-dir/.history/`; a delta was measured at 9.1 GB against a 29 GB initial mirror | [prep 09](https://github.com/bgregori/disconnected-prep/blob/main/docs/09-day2-delta.md) |

Every command in this repository that is not inside a `TODO` either
comes from that list, or is a generic Unix or `oc` read-only query whose
behaviour does not depend on anything unverified.

Prep's own record is equally explicit about *its* gaps, and one of them
is this repository's starting point:

> **A real cluster install from this mirror.** Out of scope for this
> repo; the handoff bundle has not been consumed by an installer. In
> particular the generated `imageDigestSources` is correct against the
> IDMS but has not been proven by booting an agent ISO.

So the very first thing this repository will validate is the last thing
prep could not.

---

## STIG rules cited, and why only five

Five rule IDs appear, all in [chapter 7](docs/07-identity.md), all
concerning authentication. They were read and confirmed during the
sibling work:

| Rule | Requirement |
|---|---|
| CNTR-OS-000030 | IdP must be LDAP or OpenID; HTPasswd prohibited |
| CNTR-OS-000460 | As above, different control family |
| CNTR-OS-000040 | `kubeadmin` credential must be removed |
| CNTR-OS-000430 | MFA — satisfied at the IdP |
| CNTR-OS-000760 | `accessTokenMaxAgeSeconds` ≤ 28800 |

No other rule ID is cited anywhere. Rule IDs are not stable across
benchmark revisions, the identifier in the published benchmark differs
from the Compliance Operator's rule object name, and a wrong citation
survives review, reaches the SSP, and is found by the assessor — at
which point every other citation is in question. See
[appendix-stig-cluster.md](docs/appendix-stig-cluster.md#why-so-few-rule-ids-appear-in-this-repository).

---

## Not verified — the honest list

Everything else. Stated by chapter so the gaps are navigable rather than
a single disclaimer:

| Chapter | Status |
|---|---|
| [01 Intake](docs/01-intake.md) | **Mostly real.** Checks are generic shell or carried from prep. The mirror content gate and the Keycloak `groups` claim are TODO. |
| [02 install-config](docs/02-install-config.md) | **Partly real.** The three disconnected requirements and the pull secret come from prep. Topology, networking and schema validation are TODO. |
| [03 Manifests](docs/03-manifests.md) | **Mostly TODO.** The window, the stakes and the decisions are real; the MachineConfig content for disk encryption, chrony and the project template is not written. |
| [04 Agent ISO](docs/04-agent-iso.md) | **Mostly TODO.** The FIPS host requirement is from prep. The generation command and boot procedure are not written. |
| [05 First access](docs/05-first-access.md) | **Partly real.** Credential handling and the cluster-operator checks are real; bootstrap watch and the pull-path proof are TODO. |
| [06 Day-1 config](docs/06-day1-cluster-config.md) | **Mostly real** — it is prep's post-install step, restated. OSUS and the full pull-path proof are TODO. |
| [07 Identity](docs/07-identity.md) | **Structure real, commands TODO.** The ordering, the gate before deleting `kubeadmin` and the five rules are the substance. No `Secret`, `ConfigMap`, `OAuth` CR or deletion command is written. |
| [08 Encryption at rest](docs/08-encryption-at-rest.md) | **Mostly TODO.** The distinction from disk encryption, and the configured-versus-migrated trap, are real. |
| [09 Compliance Operator](docs/09-compliance-operator.md) | **Partly real.** The baseline-first argument, capture commands and result taxonomy are real. Install manifests, `ScanSettingBinding` and the label selectors are TODO. |
| [10 Remediation](docs/10-remediation.md) | **Partly real.** Reboot economics, the review discipline and the delta capture are real. The review and apply mechanism is TODO. |
| [11 Manual controls](docs/11-manual-controls.md) | **Mostly real as a process.** What each control requires and what evidence satisfies it is written; the configuration for banner and audit forwarding is TODO. |
| [12 Evidence pack](docs/12-evidence-pack.md) | **Real.** Structure, not procedure — nothing here needs hardware. |
| [13 Day-2](docs/13-day2.md) | **Partly real.** The handback to prep and the drift table are real. Upgrade procedure, scheduled scans and File Integrity are TODO. |
| [topologies/sno](docs/topologies/sno.md) | **Outage semantics real, configuration TODO.** |
| [topologies/compact](docs/topologies/compact.md) | **Outage semantics real, configuration TODO.** |
| [troubleshooting](docs/troubleshooting.md) | **Partly real.** Failures inherited from prep are written; cluster-side diagnostics are TODO. |

Beyond the chapters:

- **Any topology other than what is eventually built.** Expect the first
  validated topology to be the only validated one for a while, and the
  other topology page to stay reasoned.
- **Architectures other than `amd64`**, matching prep's limit.
- **Red Hat build of Keycloak specifically.** The IdP facts are known;
  no RHBK version has been configured against a cluster, and the
  `groups` claim behaviour has changed between Keycloak major versions.
- **Any interaction between FIPS mode and the benchmark content.** Some
  checks are satisfied by FIPS and some made irrelevant by it; which is
  which has not been established.

---

## How to update this file

When a procedure is validated:

1. Replace the `TODO` block with the command, as run.
2. Add a row to **What has been validated** above, naming the
   environment and the date.
3. Move the chapter's row in the table out of TODO.
4. If a rule ID was confirmed, add it to the rules table **with the
   benchmark revision**.

Record what failed as well as what worked. Prep's most useful section is
its list of twenty-one bugs that passed review and failed on real
hardware; this repository will have its own, and they are worth more
than the clean procedures.
