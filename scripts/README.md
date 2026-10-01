# `scripts/`

Local helpers — PowerShell only. Each script is self-contained,
`[CmdletBinding()]`-aware, and supports `-WhatIf` where it mutates files.

## Inventory

| Script | Purpose |
|---|---|
| [`Update-SubscriptionVending.ps1`](Update-SubscriptionVending.ps1) | Previews and applies a tagged accelerator release to managed files in a generated repository. |
| [`Grant-SubscriptionCreatorRole.ps1`](Grant-SubscriptionCreatorRole.ps1) | Grants the pipeline identity SubscriptionCreator on an EA or MCA billing scope. |
| [`Reset-LocalState.ps1`](Reset-LocalState.ps1) | Wipes local operator state from the working tree. Removes tfvars / sidecar JSON / `.terraform/` caches / tfstate / tfplans / local logs in a single command. Handy before committing, sharing a fork, or starting a clean run. |

## `Update-SubscriptionVending.ps1`

Run this helper from a generated vending repository. Preview is the default:

```powershell
pwsh ./scripts/Update-SubscriptionVending.ps1 -TargetVersion v0.4.0
```

Use `-Apply` to create `upgrade/accelerator-<version>` and update the working
tree. Add `-CreatePullRequest` only when the script should also commit, push,
and call `gh pr create`. `-Latest` is available as an explicit alternative to
`-TargetVersion`.

The updater downloads the target tagged source archive, evaluates its
`upgrade-manifest.json`, and compares it with the managed-file hashes recorded
at bootstrap or the previous upgrade. Older repositories without hashes use
their explicitly supplied current release as the comparison baseline.
Repository-owned requests, rendered platform configuration, CODEOWNERS, and
local additions are excluded. A locally changed managed file becomes a
blocking conflict only when the target release also changes or removes it.
All conflicts are reported before any file is written.

Repositories without `.accelerator/metadata.json` must supply both
`-CurrentVersion` and `-Starter` during their first upgrade. Run the updater
from the target accelerator release checkout with `-RepositoryRoot` pointing
to the older generated repository. See the
[upgrade runbook](../docs/operators/upgrade.md) for
the full lifecycle and post-merge deployment step.

## `Reset-LocalState.ps1`

This helper targets the shared Terraform-based bootstrap and Terraform runtime
artifacts. Bicep compiler output under `bicep/out/` is gitignored but is not
removed by this script.

### What it removes

| Category | Pattern (any depth under the working-tree root) |
|---|---|
| Bootstrap input state | `terraform.tfvars`, `terraform.tfvars.json`, `.bootstrap-inputs.json`, `.bootstrap-inputs.json.bak` |
| Terraform local artefacts | `.terraform/` (recursive), `.terraform.lock.hcl`, `terraform.tfstate`, `terraform.tfstate.backup`, `tfplan`, `*.tfplan`, `plan.txt` |
| Stray local logs / shell artefacts | `.run.log`, single-char `^-[a-zA-Z]$` files (shell-redirect leftovers like `-w`) |

### What it never touches

- `.git/` — the working tree may itself be a git repo
- Any `*.tfvars.example` file — these ship deliberately
- Any `*.tftpl` file — bootstrap-rendered templates ship as templates

### Usage

```powershell
# Dry-run: list every file that would be removed
pwsh ./scripts/Reset-LocalState.ps1 -WhatIf

# Real run with interactive y/N prompt (default)
pwsh ./scripts/Reset-LocalState.ps1

# One-shot / CI / scripted (no prompt)
pwsh ./scripts/Reset-LocalState.ps1 -SkipPrompt
```

### Parameters

| Parameter | Default | Effect |
|---|---|---|
| `-Root` | parent of the script | Working-tree root to scan. Override only for unusual layouts. |
| `-WhatIf` | off | Dry-run; lists candidates without deleting. |
| `-SkipPrompt` | off | Skip the final `Delete? [y/N]` prompt. |

### Safety guarantees

- Each match is checked against an exclusion regex before deletion
  (`\.git`, `*.tfvars.example`, `*.tftpl`).
- Directory matches are de-duplicated against any file matches that
  fall under them (so a `.terraform/providers/...` file inside a
  `.terraform/` directory match is only counted once).
- Output is **always** shown (`[FILE]` / `[DIR]` markers + size) before
  any deletion happens, even without `-WhatIf`.
- A non-zero exit code is returned if any deletion fails — useful for
  CI pipelines that wrap this script.

## See also

- [Upgrade a generated repository](../docs/operators/upgrade.md) and local cleanup context
- [Retire a subscription](../docs/operators/retire-subscription.md) for Azure-side cleanup, not local file cleanup
- [`.gitignore`](../.gitignore) — the canonical list of files that should never be committed (this script's targets are a superset)
