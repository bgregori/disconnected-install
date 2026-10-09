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

> **TODO:** needs validation on real hardware — the command that produces
> the agent ISO, its `--dir` semantics, what it leaves behind in the
> install directory, and the generated file's name and location.
>
> Establish in particular: whether generation consumes or preserves the
> manifests placed in chapter 3, and what the output looks like when the
> manifest directory was empty — because an ISO generated without the
> disk-encryption MachineConfig is indistinguishable from a correct one
> until a node is running.

What is already known and does not need validating:

- The install directory is destroyed and rebuilt by re-running earlier
  stages. If you need to regenerate, assume you are starting from
  `install-config.yaml.bak` and the `manifests-src/` directory from
  chapter 3.
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

> **TODO:** needs validation on real hardware — the boot procedure for
> this environment: virtual media attach, boot order, the rendezvous host
> behaviour, and what normal progress looks like so that abnormal
> progress is recognisable. Include approximate timings, because "it has
> been eleven minutes, is that bad" is the question actually asked at
> this point, and the honest answer requires having watched it.

> ⚠️ **STIG** Out-of-band management interfaces are usually on their own
> restricted network with their own access controls, and virtual media
> may be disabled by policy. Confirm you can actually mount an ISO before
> the change window, not during it. The fallback — physical media, or a
> USB device — has its own policy problems on a hardened site.

### Watching it

> **TODO:** needs validation on real hardware — where the agent-based
> installer reports progress before the cluster API exists, and how to
> reach it. This matters more here than in a connected install because
> the most likely failure is a silent hang on an image pull, and the
> distinguishing evidence is in logs that exist only on the rendezvous
> node.

The single most likely failure, stated plainly so it is the first thing
you check: **a pull reaching for `quay.io`**. That means
`imageDigestSources` was wrong or incomplete. It presents as a stall with
no error, because there is nothing to connect to and the timeout is long.

---

Next: [05-first-access.md](05-first-access.md).
