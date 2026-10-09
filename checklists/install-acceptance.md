# Install acceptance checklist

Complete before the cluster is handed to anyone, and before
[checklists/ato-evidence.md](ato-evidence.md).

Environment: ______________________  Date: ____________  By: ____________

---

## 1. Intake — before anything was built

- [ ] Handoff bundle checksums verified (`sha256sum -c SHA256SUMS`)
- [ ] [Prep's handoff contract](https://github.com/bgregori/disconnected-prep/blob/main/checklists/handoff-contract.md)
      walked through **with the prep engineer**, not read alone
- [ ] `openshift-install-fips` runs on the install host, and reports a
      release reference resolving to **your** registry, not `quay.io`
- [ ] Install host `fips_enabled=1`
- [ ] Registry resolves and answers `401` **from the node network**
- [ ] Registry certificate `subjectAltName` contains the FQDN used in
      `imageDigestSources`
- [ ] `api.<cluster>.<base-domain>` resolves from the node network
- [ ] `*.apps.<cluster>.<base-domain>` resolves from the node network
- [ ] NTP source reachable from the node network
- [ ] API and ingress VIPs confirmed **unused**
- [ ] **Mirror gate:** compliance-operator, file-integrity-operator and
      diagnostics confirmed present in the mirror
- [ ] IdP facts collected: issuer, client ID, secret, CA, claim names
- [ ] The group to be bound to `cluster-admin` exists and is populated

## 2. install-config.yaml

- [ ] `fips: true`
- [ ] `imageDigestSources` entry count **equals** the IDMS entry count
- [ ] `additionalTrustBundle` present, correctly indented
- [ ] `additionalTrustBundlePolicy: Always`
- [ ] Pull secret is the **mirror** secret, key matches the registry
      reference including port
- [ ] `sshKey` present and attributable to a named person
- [ ] A copy kept **outside** the install directory, mode `0600`

## 3. Manifests, before ignition

- [ ] Disk encryption MachineConfig present for **`master` and
      `worker`**, not just `master`
- [ ] Mode decided and recorded: TPM v2 ☐ · Tang/NBDE ☐ · both ☐ ·
      none, accepted by ISSO ☐
- [ ] If Tang: servers reachable from the node network, thumbprints are
      from the servers actually deployed
- [ ] If TPM v2: TPM 2.0 present and enabled in firmware on every node
- [ ] Chrony MachineConfig present, pointing at the enclave source
- [ ] Default-deny project template in place, or deferred to day 1 with
      a written note
- [ ] Source manifests archived outside the install directory

## 4. Install

- [ ] ISO checksum recorded
- [ ] ISO unmounted from virtual media after installation
- [ ] All nodes `Ready`
- [ ] All cluster operators `Available=True`, `Progressing=False`,
      `Degraded=False`
- [ ] `kubeconfig` and `kubeadmin-password` mode `0600`
- [ ] Break-glass `kubeconfig` storage location **decided and recorded**

## 5. Day-1 cluster config

- [ ] `cluster-resources/` applied
- [ ] MachineConfigPools settled (`UPDATED=True`, `UPDATING=False`)
      before anything else was applied
- [ ] `disableAllDefaultSources: true`
- [ ] Mirrored `CatalogSource` still present and `READY`
- [ ] `oc get packagemanifest -A` is non-empty
- [ ] `/etc/containers/registries.conf.d/` populated on a node
- [ ] Mirror-only pull path evidenced — including the network team's
      record of denied outbound attempts

## 6. Identity

- [ ] IdP is OpenID (or LDAP). **No HTPasswd provider exists**
      — CNTR-OS-000030, CNTR-OS-000460
- [ ] Authentication operator `Available=True`, `Degraded=False`
- [ ] A **group** is bound to `cluster-admin`, not a user
- [ ] A named human logged in and is cluster-admin, proven with
      `oc auth can-i '*' '*' --all-namespaces`
- [ ] A **second** named human is also cluster-admin
- [ ] A human **not** in the group logged in and is **not**
      cluster-admin
- [ ] Second factor required at login — CNTR-OS-000430
- [ ] `accessTokenMaxAgeSeconds` ≤ 28800 — CNTR-OS-000760
- [ ] **Then** `kubeadmin` deleted — CNTR-OS-000040
- [ ] Deletion date, person, and the two cluster-admins at the time:
      ______________________________________________
- [ ] IdP CA expiry date recorded and in a calendar: ____________

## 7. Encryption

- [ ] Boot disk: `cryptsetup status root` shows LUKS2 on **every** node
- [ ] Cipher `aes-cbc-essiv:sha256` (expected under FIPS)
- [ ] etcd encryption enabled
- [ ] etcd encryption **migration complete**, not merely configured
- [ ] All three API server operators settled

## 8. Compliance baseline

- [ ] Compliance Operator installed **from the mirrored catalog**
- [ ] `ocp4-stig` and `rhcos4-stig` both scanned
- [ ] **Baseline captured before any remediation**, dated, and copied
      off the cluster
- [ ] Operator version and benchmark revision recorded with it
- [ ] `MANUAL` and `ERROR` results enumerated, not just `FAIL`

## 9. Remediation

- [ ] Remediations reviewed before applying — not auto-applied on the
      first run
- [ ] Declined remediations recorded in the exceptions register with
      reasons, at the time
- [ ] Remediations batched; rollout count planned and communicated
- [ ] Re-scan completed
- [ ] Delta produced and read **in both directions** — including any
      `PASS` → `FAIL`
- [ ] Every remaining `FAIL` labelled Scheduled / Waived / Deviation

## 10. Manual controls

- [ ] Banner: console, CLI and node SSH — all three, with the approved
      wording
- [ ] Audit forwarding configured **and** records confirmed arriving at
      the destination
- [ ] Retention period confirmed by the destination's owner
- [ ] RBAC reviewed, with a reviewer name and date
- [ ] MFA attestation obtained from the IdP owner

## 11. Known limits — state each one aloud

- [ ] Only the mirrored **version** exists; upgrades need a prep cycle
- [ ] Only the mirrored **architecture** can be installed
- [ ] Operators absent from `imageset-config.yaml` are **not
      installable**; adding one is a transfer window
- [ ] The **mirror registry is production infrastructure** — if it goes
      away, the cluster cannot pull images
- [ ] If Tang: **the Tang servers are production infrastructure** — if
      they go away, nodes do not boot
- [ ] The **IdP is on the critical path** for human access
- [ ] Typical transfer lead time: ____________

## 12. Topology-specific

### Single node

- [ ] Understood: every MachineConfig change is a **full outage**
- [ ] Remediations batched into planned windows, not applied ad hoc

### Three-node compact

- [ ] Two nodes can carry the third's workload during a drain
- [ ] etcd healthy before any rollout was started
- [ ] Storage rebuild behaviour understood relative to rollout pace

---

## Sign-off

Install complete and verified.

Name: ______________________  Date: ____________

Received by: ______________________  Date: ____________
