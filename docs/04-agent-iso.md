# Agent ISO and boot

Turning the install directory into bootable media, and getting the nodes
to consume it.

---

## The FIPS host requirement, once more

```sh
# ===== RUN ON: THE INSTALL HOST =====
cat /proc/sys/crypto/fips_enabled   # must be 1
openshift-install-fips version
```

Both, every time, immediately before generating the image. Not because it
changes — because it is the one precondition that is free to check and
expensive to discover afterwards, and because an install host that was
rebuilt or replaced between chapter 1 and here is exactly the sort of
thing that happens during a long build.

Two separate requirements, and a build satisfies either one without the
other with no complaint at generation time:

1. **The binary** is `openshift-install-fips`, extracted from your own
   registry. The generic `openshift-install` will not do.
2. **The host** is in FIPS mode. Red Hat requires the installation
   program to run from a RHEL 9 computer configured to operate in FIPS
   mode, whichever binary you used.

Prep states this in full at
[prep 01 — FIPS mode: host versus cluster](https://github.com/bgregori/disconnected-prep/blob/main/docs/01-prerequisites.md#fips-mode-host-versus-cluster),
including Red Hat's wording. It is not restated here.

---

## Generating the image

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The command is documented. What has not been seen here is the thing
> that matters most: **what the output looks like when the inputs were
> missing.** An ISO generated without chapter 3's `diskEncryption` block
> is byte-for-byte plausible, boots normally, and produces a working
> cluster with unencrypted disks. If the installer says nothing about
> custom manifests or disk encryption in its output, there is no signal
> at all, and the pre-flight below is the only defence. Record what it
> actually logs.

Check both of chapter 3's staging points, immediately before
generating. This is cheap and it is the last moment either question can
be asked:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
ls -1 ${OCP_INSTALL_ROOT}/cluster/openshift/ | wc -l
grep -A4 'diskEncryption' \
  ${OCP_INSTALL_ROOT}/cluster/cluster-manifests/agent-cluster-install.yaml
```

Two files in `openshift/` — the chrony pair — plus whatever the project
template added. If that number is not what chapter 3 left, stop here.

The `grep` is the more important of the two, and **an empty result is
the failure, not a clean pass.** `diskEncryption` absent means
`enableOn` defaults to `none`, the ISO builds without complaint, and
every node comes up unencrypted. Read the four lines back and check
`enableOn` and `mode` say what you decided; do not settle for the grep
exiting zero.

If `install-config.yaml` and `agent-config.yaml` are still present —
they will not be, if chapter 3 ran — copy them out now:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
cp -n ${OCP_INSTALL_ROOT}/cluster/install-config.yaml \
      ${OCP_INSTALL_ROOT}/install-config.yaml.bak 2>/dev/null || true
cp -n ${OCP_INSTALL_ROOT}/cluster/agent-config.yaml \
      ${OCP_INSTALL_ROOT}/agent-config.yaml.bak 2>/dev/null || true
ls -l ${OCP_INSTALL_ROOT}/*.bak
```

`-n` so this cannot overwrite the good copies chapter 3 took with
nothing. The `ls` is the check: if the two `.bak` files are not there,
the originals are gone and unbacked, and the install directory is no
longer reproducible. Stop and reconstruct them before generating.

Then generate:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
openshift-install-fips agent create image \
  --dir ${OCP_INSTALL_ROOT}/cluster --log-level=info
```

**Both `agent create cluster-manifests` and `agent create image` consume
and delete `install-config.yaml` and `agent-config.yaml`.** Chapter 3's
run is what usually removes them; this one removes whatever is left.
Either way it happens on every regeneration, so the `.bak` copies are
part of the procedure rather than a precaution.

Two things in the output are worth reading rather than scrolling past:

- **The rendezvous host IP.** The installer echoes it. It must be the
  address you put in `agent-config.yaml`, and it is where you go to
  watch the install.
- **The ISO path**, typically
  `${OCP_INSTALL_ROOT}/cluster/agent.x86_64.iso`.

The command also leaves `auth/kubeconfig` and `auth/kubeadmin-password`
in the install directory. Those are credentials and chapter 5 handles
them.

What is already known and does not need validating:

- The install directory is destroyed and rebuilt by re-running earlier
  stages. If you need to regenerate, assume you are starting from
  `install-config.yaml.bak`, `agent-config.yaml.bak` and the
  `manifests-src/` directory from chapter 3 — **and that the
  `diskEncryption` block you hand-edited into
  `cluster-manifests/agent-cluster-install.yaml` is gone with it.**
  Regenerating is the common way that block is silently lost. Keep a
  copy of the edited `agent-cluster-install.yaml` alongside the `.bak`
  files and re-apply it every time.
- The ISO embeds the mirror registry details, the CA and the pull secret.
  **It is a credential-bearing artifact.** Treat the file, and any copy
  of it on a share or an iDRAC virtual media mount, accordingly.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
ls -l ${OCP_INSTALL_ROOT}/cluster/
sha256sum ${OCP_INSTALL_ROOT}/cluster/*.iso
```

Record the checksum. If the ISO is copied to a share, mounted over the
network, or handed to a datacentre technician, the checksum is how you
know the thing that booted is the thing you built.

📌 **Handoff** Whoever mounts the media needs: the ISO, its checksum, the
boot order change required, and a clear statement that the ISO must be
unmounted after installation rather than left attached. A node that
reboots back into the installer is a confusing failure.

---

## What the ISO needs from the environment

Everything chapter 1 checked, now actually in use:

| Dependency | Needed for | Fails as |
|---|---|---|
| Mirror registry, reachable from the node network | every image pull during bootstrap | a hang, not an error |
| `imageDigestSources` in the embedded config | redirecting `quay.io` references to the mirror | an outbound connection attempt that times out slowly |
| DNS for `api.` and `*.apps.` | rendezvous and bootstrap | a hang |
| NTP | certificate validation | TLS errors that do not mention time |
| Tang servers, if NBDE | **node boot itself** | the node does not come up at all |

The first and the last are the ones worth re-checking in the hour before
you boot, because both are things another team can change without telling
you.

---

## Booting

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> **No timings are given below, deliberately.** "It has been eleven
> minutes, is that bad" is the question actually asked at this point,
> and the honest answer requires having watched it on this hardware.
> Inventing a number here would produce exactly the wrong intervention
> at exactly the wrong moment. Time each phase on the first install and
> write the numbers in — they are among the most useful things this
> chapter will ever contain.

The sequence, which is unusual enough to be worth stating:

1. **Every node boots the same ISO.** There is no per-node media and no
   provisioning host. Each node finds its own configuration inside the
   ISO by matching its NIC's MAC address against `agent-config.yaml`.
   A MAC typo means that node gets no configuration at all.
2. **One control plane node becomes the rendezvous host** — the one
   whose address is `rendezvousIP`. It runs the assisted service and
   acts as the bootstrap node. Boot it first, or at least confirm it
   came up, because the others have nothing to register with until it
   has.
3. **The other nodes register, get validated, and install.** RHCOS is
   written to disk on all of them.
4. **The non-rendezvous nodes reboot into the cluster.**
5. **The rendezvous host reboots last and joins**, which is what
   completes bootstrapping. A rendezvous host that appears to hang
   while the others are already up is normal at this point, not a
   failure.

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
sha256sum ${OCP_INSTALL_ROOT}/cluster/agent.x86_64.iso
```

Compare against the checksum recorded above, after the ISO has been
copied to wherever the out-of-band controller reads it from. A share, a
mount and a transfer are three places it can be truncated, and a
truncated ISO boots far enough to be confusing.

**Unmount the media once installation completes.** A node that reboots
back into the installer looks like a node that failed to install.

> ⚠️ **STIG** Out-of-band management interfaces are usually on their own
> restricted network with their own access controls, and virtual media
> may be disabled by policy. Confirm you can actually mount an ISO on the
> day you ask for access, not on the day you need to boot. The fallback —
> physical media, or a USB device — has its own policy problems on a
> hardened site, and sorting either out is measured in days of paperwork
> rather than minutes.

### Watching it

> 🚧 **DRAFT -- NOT VALIDATED.** Written from documentation, not executed
> against a cluster. Verify before running. Replace this block with the
> command as run, then update VALIDATION.md.
>
> The commands are documented; what they look like *in this environment*
> is not. The assisted service's web endpoint in particular may or may
> not be reachable from where you are sitting — the install host is
> often on a management VLAN and the rendezvous IP is on the node
> network, which is the same split chapter 1 warned about. Establish
> which of the three routes below actually works from the install host
> and delete the other two.

From the install host, if the API is far enough along:

```sh
# ===== RUN ON: THE INSTALL HOST =====
: "${OCP_INSTALL_ROOT:?set it first -- see 01-intake.md}"
openshift-install-fips agent wait-for bootstrap-complete \
  --dir ${OCP_INSTALL_ROOT}/cluster --log-level=debug
```

From the rendezvous host itself, which is where the evidence is before
the API exists. The SSH key is the one in `install-config.yaml`, and
the user is `core`:

```sh
# ===== RUN ON: A NODE =====
sudo journalctl -u assisted-service -f
sudo journalctl -u agent -f
sudo podman ps -a
```

`assisted-service` runs only on the rendezvous host. `agent` runs on
all of them. The distinguishing evidence for the failure below is in
the first.

And the collection command, for when it has gone wrong and you want
someone else to look:

```sh
# ===== RUN ON: THE INSTALL HOST =====
ssh core@<rendezvous-ip> agent-gather -O > agent-gather.tar.xz
```

> ⚠️ **STIG** That archive contains the cluster's ignition configs, and
> therefore the mirror pull secret. It is a credential-bearing artifact
> in the same way the ISO is. Treat the file accordingly, and do not
> put it anywhere a support case will reach without clearing that
> first.

The single most likely failure, stated plainly so it is the first thing
you check: **a pull reaching for `quay.io`**. That means
`imageDigestSources` was wrong or incomplete. It presents as a stall with
no error, because there is nothing to connect to and the timeout is long.

---

Next: [05-first-access.md](05-first-access.md).
