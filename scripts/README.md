# Scripts

Scripts are a convenience for repeat runs, **not the product**. They
contain no hidden logic and echo every command before executing it, so
the terminal transcript is an accurate record of what was run — which
matters more here than in
[disconnected-prep](https://github.com/bgregori/disconnected-prep),
because that transcript is itself an accreditation artifact. See
[docs/12-evidence-pack.md](../docs/12-evidence-pack.md).

Every script runs exactly the commands its chapter shows under **"By
hand"**. A reader with a printed copy and no repository gets the same
result.

```sh
# ===== RUN ON: THE INSTALL HOST =====
cp config/install.env.example config/install.env
chmod 600 config/install.env
${EDITOR} config/install.env
```

Numbered to sort into execution order, with gaps for insertions.
Odd-numbered scripts are optional.

| Script | Chapter | Status |
|---|---|---|
| `00-preflight.sh` | [01 Intake](../docs/01-intake.md) | **written** — install-host checks only |
| `check-docs.py` | — | **written** — unnumbered; see below |
| `02-verify-environment.sh` | [01 Intake](../docs/01-intake.md) | not written — runs on a node, not here |
| `04-mirror-gate.sh` | [01 Intake](../docs/01-intake.md) | not written |
| `10-build-install-config.sh` | [02 install-config](../docs/02-install-config.md) | not written |
| `20-stage-manifests.sh` | [03 Manifests](../docs/03-manifests.md) | not written |
| `30-create-iso.sh` | [04 Agent ISO](../docs/04-agent-iso.md) | not written |
| `40-day1-config.sh` | [06 Day-1 config](../docs/06-day1-cluster-config.md) | not written |
| `50-identity.sh` | [07 Identity](../docs/07-identity.md) | not written |
| `60-compliance-install.sh` | [09 Compliance Operator](../docs/09-compliance-operator.md) | not written |
| `62-capture-baseline.sh` | [09 Compliance Operator](../docs/09-compliance-operator.md) | not written |
| `70-capture-after.sh` | [10 Remediation](../docs/10-remediation.md) | not written — queries the cluster |
| `72-delta.sh` | [10 Remediation](../docs/10-remediation.md) | **written** — local files only |
| `90-evidence-pack.sh` | [12 Evidence pack](../docs/12-evidence-pack.md) | **written** — local files only |

Three of the numbered set exist. The rest are listed so the numbering
is settled and so the gaps are visible, not because stubs are useful —
an empty script that exits zero is a worse lie than a missing one.

They are unwritten for the reason the whole repository is a skeleton: a
script that runs an unverified command is the same hazard as a doc that
prints one, with less opportunity for the reader to notice. See
[VALIDATION.md](../VALIDATION.md).

**Where the line is drawn.** `72-delta.sh` and `90-evidence-pack.sh`
are written because they touch only files that are already on disk —
`diff`, `join`, `cp`, `sha256sum`. Neither makes a single call to a
cluster or a registry, so neither can bake an unverified `oc`
invocation into a script. That is the whole test, and it is why
`62-capture-baseline.sh` is *not* written despite being the more
useful of the pair: the commands that produce `summary.txt` depend on
label keys [chapter 9](../docs/09-compliance-operator.md#reading-the-results)
still says to confirm against a real cluster, and a script is the
worst place to hard-code something like that. Capture by hand, then
let the scripts do the arithmetic.

## `check-docs.py` — the odd one out

Unnumbered, because it is not part of the execution order and never
runs on the install host. It checks the documentation against itself,
on a laptop or in CI:

```sh
# ===== RUN ON: ANYWHERE =====
./scripts/check-docs.py
```

- **drafts** — counts every 🚧 marker per chapter and reconciles it
  against [VALIDATION.md](../VALIDATION.md)'s table and the headline
  totals in that file and the top-level README
- **hosts** — every `sh` / `bash` / `yaml` block opens with a
  `RUN ON:` or `EDIT IN:` marker on its first line
- **versions** — the target OpenShift version stated in this README's
  parent, [docs/versions.md](../docs/versions.md) and
  `config/install.env.example` all agree, `OCP_MINOR` is derived rather
  than typed, and every 🔄 version marker is well formed
- **links** — every relative link resolves, file and heading anchor
  both

The first of those is the reason the script exists. The draft count is
this repository's stated measure of its own progress and the thing a
reader uses to tell a verified command from an invented one, and it is
maintained by hand — it had already drifted by one within a single
drafting pass. A count that drifts **low** is the one defect here that
nobody downstream can detect, because it makes the repository look
more validated than it is. That is not a thing to leave to whoever
remembers.

It runs on every push, with `shellcheck`, from
`.github/workflows/check-docs.yml`.

## Two that will never be written

Some chapters should not be automated, and the numbering above reflects
that.

**Remediation.** [Chapter 10](../docs/10-remediation.md) is
review-then-apply by default, and the review is the point. A script that
applies remediations is the auto-apply variant wearing a disguise, and
the terminal transcript it produces is evidence of exactly the thing the
chapter argues against.

**Deleting `kubeadmin`.** [Chapter 7's
gate](../docs/07-identity.md#the-gate) is a human checklist with a
second person involved. Automating past it defeats it.

## Conventions

`lib/common.sh` is adapted from prep's and keeps its behaviour:

- `run` echoes each command before executing it
- `die` on an unmet precondition, never a silent fallback
- `confirm` refuses to prompt when stdin is not a terminal, rather than
  reading EOF as a refusal and aborting a backgrounded run
- `assert_executes` retries briefly, because a freshly allowlisted binary
  is not trusted instantaneously on a fapolicyd host
- `require_fips_host` is a hard failure here, unlike prep's advisory
  version — this is the host that runs `openshift-install-fips`
- `warn_wrong_host` exists because many of this repository's checks are
  meaningless on the install host and must say so rather than passing
