# `scripts/`

Local helpers — PowerShell only. Each script is self-contained,
`[CmdletBinding()]`-aware, and supports `-WhatIf` where it mutates files.

## Inventory

| Script | Purpose |
|---|---|
| [`Reset-LocalState.ps1`](Reset-LocalState.ps1) | Wipes local operator state from the working tree. Removes tfvars / sidecar JSON / `.terraform/` caches / tfstate / tfplans / local logs in a single command. Handy before committing, sharing a fork, or starting a clean run. |

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

- [Starter updates](../docs/operators/run.md#updating-the-starter-itself) and local cleanup context
- [Retire a subscription](../docs/operators/retire-subscription.md) for Azure-side cleanup, not local file cleanup
- [`.gitignore`](../.gitignore) — the canonical list of files that should never be committed (this script's targets are a superset)
