# Subscription-vending bootstrap

Full reference for the PowerShell accelerator entry point and its current
Terraform implementation. The module replaces the manual
`Copy-Item terraform.tfvars.example → notepad → terraform init/plan/apply`
sequence with a guided, resumable flow inspired by the ALZ Accelerator.

> 🚀 **TL;DR:** import
> `powershell/SubscriptionVending/SubscriptionVending.psd1`, then run
> `Initialize-SubscriptionVending -Engine Terraform` or
> `Initialize-SubscriptionVending -Engine Bicep`. The module selects the
> starter and delegates to the existing Terraform wizard. It walks through
> every input, validates everything against Azure and GitHub APIs, then runs
> `terraform init / plan / apply`. Re-run the same command to resume.

```powershell
Import-Module ./powershell/SubscriptionVending/SubscriptionVending.psd1
Get-SubscriptionVendingEngine
Initialize-SubscriptionVending -Engine Terraform
```

Both engines are available. The bootstrap configuration carries the selected
engine into GitHub repository variables and renders either Terraform tfvars or
Bicep platform configuration.

> 🧹 **Need to undo a bootstrap** (wrong tenant, wrong repo, typo,
> abandoned POC)? The same wizard handles teardown — run
> `pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf` for a dry-run, then
> drop `-WhatIf` to apply. See
> [Destroying / undoing a bootstrap](#destroying--undoing-a-bootstrap)
> below.

## When to use the module, legacy wizard, or manual flow

| You want… | Use |
|---|---|
| First-time bootstrap through the accelerator interface | `Initialize-SubscriptionVending -Engine Terraform` or `Initialize-SubscriptionVending -Engine Bicep` |
| See available engines | `Get-SubscriptionVendingEngine` |
| Validate an existing sidecar against Azure and GitHub | `Test-SubscriptionVendingConfiguration -InputsPath <path>` |
| To re-collect inputs without touching Terraform | `Invoke-Bootstrap.ps1 -Phase configure` |
| A dry-run plan with no apply | `Invoke-Bootstrap.ps1 -PlanOnly` |
| Destroy an existing Terraform bootstrap | `Invoke-Bootstrap.ps1 -Destroy` |
| To drive Terraform yourself from a non-PowerShell environment | See the [manual bootstrap flow](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md#usage) |

The module, legacy wizard, and manual Terraform flow leave **identical
Terraform state** behind. The module is now the stable product boundary while
the legacy script remains the current Terraform implementation. Reruns are for
resuming an incomplete bootstrap, not for synchronizing files after the
generated repository has been handed over.

## Phases

```
┌───────────┐   ┌───────────┐   ┌───────────┐   ┌───────────┐
│ preflight │ → │ configure │ → │ validate  │ → │ terraform │
└───────────┘   └───────────┘   └───────────┘   └───────────┘
   tools           prompts        Azure + GH     init/plan/apply
   + auth          + sidecar      sanity check
```

Each phase is **individually runnable** via `-Phase <name>`. The default
is `all`.

| Phase | What happens | Re-runnable? | Side effects |
|---|---|---|---|
| `preflight` | Verifies Terraform is `>= 1.10.0` and `< 2.0.0`, Azure CLI is 2.64.0 or newer, GitHub CLI is 2.50.0 or newer, and PowerShell is 7.2 or newer. Resolves a GitHub token from `$env:GITHUB_TOKEN` or `gh auth token` without persisting it. Verifies the Azure session matches the configured tenant. | Always | None |
| `configure` | Prompts you for every bootstrap input, grouped by concern (see [Group reference](#group-reference-configure-phase)). Persists to `bootstrap/.bootstrap-inputs.json` (gitignored) **atomically per group**. Ctrl-C never loses more than one group's progress. On rerun, current values are shown as defaults; press Enter to keep. | Always; keep or edit per group | Writes to `.bootstrap-inputs.json` + rotates `.bak` |
| `validate` | Calls Azure (resource-group/SA/MG existence) + GitHub (`/user`, `/repos/...`, team/user lookups) to confirm the inputs are sane **before** `terraform apply` discovers them. Catches typos, missing scopes, wrong tenant, MG ID format mistakes. | Always | None — read-only |
| `terraform` | Renders `terraform.tfvars.json` from the sidecar (drift-aware — warns on hand-edits), runs `terraform init` (with `-reconfigure` when `-Reconfigure` is set), `terraform plan -out=tfplan`, then asks before `apply`. | Initial bootstrap or partial-failure recovery | Writes `terraform.tfvars.json`, runs Terraform |

## Parameters

| Parameter | Type | Default | Effect |
|---|---|---|---|
| `-Engine` | `Terraform` / `Bicep` | `Terraform` | Selects the starter package and generated runtime. |
| `-Phase` | `preflight` / `configure` / `validate` / `terraform` / `all` | `all` | Which phase(s) to run. |
| `-NonInteractive` | switch | off | Disable prompts. Required values that aren't in the JSON sidecar cause the script to fail. **Does NOT imply apply** — combine with `-AutoApprove`. |
| `-AutoApprove` | switch | off | Skip the `terraform apply` confirmation prompt. Without this flag, the script always asks (interactive) or refuses to apply (non-interactive). |
| `-PlanOnly` | switch | off | Run preflight + configure + validate + init + plan, then exit. Never applies. |
| `-Reconfigure` | switch | off | Pass `-reconfigure` to `terraform init`. Use after changing the state SA. |
| `-SkipPreflight` | switch | off | Bypass tool-version + auth checks. Escape hatch for environments where the checks return false negatives. |
| `-InputsPath` | string | `<script-dir>/.bootstrap-inputs.json` | JSON sidecar location. |
| `-TfvarsPath` | string | `<script-dir>/terraform.tfvars.json` | Rendered tfvars location. |
| `-StarterRoot` | string | `<repository>/starters` | Starter contract and manifest directory. Override only for testing or custom repository layouts. |
| `-ScriptRoot` | string | `$PSScriptRoot` | Bootstrap module directory. Only override for unusual layouts. |

`-WhatIf` is accepted only with destroy or local cleanup. Bootstrap mode rejects
it because configuration and Terraform initialization are not read-only.
Use `-PlanOnly` to preview bootstrap changes.

## Group reference (configure phase)

The wizard groups ~20 inputs into 13 thematic groups. Each group is
saved atomically as soon as it is collected, so Ctrl-C never loses more
than one group.

| # | Group | What it asks | Validation |
|---|---|---|---|
| 1 | `IdentityLocation` | `tenant_id`, `platform_subscription_id`, `location`, `uami_resource_group_name`, `uami_name` | GUID format, Azure-region name |
| 2 | `State` | Terraform only: `state_storage_account_resource_group_name`, `state_storage_account_name`, `state_container_name` | Storage-account naming rules (3-24 lowercase alphanumeric) |
| 3 | `Rbac` | `alz_root_management_group_id`, `connectivity_subscription_id`, `grant_user_access_administrator` | Bare MG name (not a full resource ID), GUID for sub IDs |
| 4 | `GitHubRepo` | `github_owner`, `github_repository_name`, `github_repository_visibility`, `github_default_branch`, `create_github_repository`, `github_oidc_subject_mode` | GitHub handle format and optional immutable owner-ID resolution |
| 5 | `BranchProtection` | `enforce_branch_protection`, `branch_protection_required_status_checks`, `branch_protection_required_approving_review_count` | Non-empty check names |
| 6 | `ProductionEnv` | `production_environment_name`, reviewer team handles + user handles | Resolves handles to numeric IDs and warns when team membership leaves fewer than two eligible approvers |
| 7 | `BillingScopes` | One entry per scope: key, `agreement_type` (EA/MCA/MPA), matching nested fields. Must include a `default` key. | `default` present, agreement-type ↔ nested-object consistency, path-string format on render |
| 8 | `ManagementGroups` | `management_group_ids` map with one entry per supported archetype | Full MG resource ID format |
| 9 | `Network` | `hub_virtual_network_resource_id` (optional) | `/subscriptions/<guid>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<name>` regex |
| 10 | `Tags` | `mandatory_tags` map (defaults to CAF: `managedby`/`source`/`deployedby`) | Tag-key naming (lowercase, no separators) |
| 11 | `CostAllocation` | `cost_allocation_tag` object: `name` / `required` / `pattern` | Tag-key naming for `name`, optional regex compiles |
| 12 | `CodeOwners` | `codeowners_default_team` (single handle), `codeowners_archetype_teams` (per-archetype overrides) | `@user` or `@org/team` format |
| 13 | `Skeleton` | `copy_skeleton_files`, `skeleton_commit_author`, `skeleton_commit_email` | Email format |

The production reviewer check is advisory. A one-person setup can continue
without changing the secure `prevent_self_review` default. When that person
initiates the workflow, a repository administrator can open the pending run
and select **Start all waiting jobs**, provided administrator bypass has not
been disabled for the environment.

## Sidecar lifecycle

```
.bootstrap-inputs.json          ← source of truth (gitignored)
.bootstrap-inputs.json.bak      ← previous version, kept after each save
terraform.tfvars.json           ← rendered by `-Phase terraform`, replaced on each run
```

**Editing rules:**

- 🔒 The sidecar records `starter_name`. A bootstrap cannot switch engines in
  place because generated files and Terraform ownership would become
  ambiguous. Start with a new sidecar and state, or perform an explicit
  migration.
- ✏️ **Edit `.bootstrap-inputs.json` directly** (or re-run the wizard) — this is the source of truth.
- ❌ **Do NOT hand-edit `terraform.tfvars.json`.** The wizard replaces it on every `-Phase terraform` run; your edits will be lost.
- 🛡️ The wizard adds a `# SourceHash:` marker to the rendered tfvars; on rerun, if the hash mismatches (i.e. you hand-edited the rendered file), the wizard warns and asks before overwriting.
- 🔄 `.bootstrap-inputs.json.bak` is rotated on every save — one-step recovery if you misclick.

## Tenant binding

Every Terraform invocation runs through the wizard's `Invoke-Terraform`
helper, which:

1. Runs `az account set --subscription $platform_subscription_id`.
2. Verifies `az account show --query tenantId` matches `$tenant_id` from
   the sidecar — refuses to continue on mismatch.
3. Sets process-scoped env vars: `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`,
   `GITHUB_TOKEN` (process scope only — never persisted to the user / machine).

This guards against the classic `azuread` / `azurerm` "fell through to
the default tenant" foot-gun.

## Resumability scenarios

These scenarios apply until the initial bootstrap succeeds. After handoff, the
generated repository owns its source files. Engine and workflow updates must be
delivered through repository pull requests, not another bootstrap apply. Use
the generated repository's `scripts/Update-SubscriptionVending.ps1` command to
prepare versioned upgrade pull requests.

| Scenario | What to do |
|---|---|
| Lost network during a prompt | Re-run; the last completed group is preserved in `.bootstrap-inputs.json`. The wizard will replay from the next group with current values as defaults (Enter to keep). |
| Validation fails (e.g. MG doesn't exist) | Fix the underlying Azure / GitHub state, re-run with `-Phase validate` to confirm before re-attempting Terraform. |
| `terraform plan` shows unexpected changes | Re-run with `-PlanOnly`, inspect, then either continue (`-Phase terraform` without `-PlanOnly`) or edit inputs (`-Phase configure`) and re-render. |
| `terraform apply` fails partway through | Re-run with `-Phase terraform`. Terraform itself handles partial state; nothing in the wizard interferes. |
| Need to reset all answers | `Remove-Item bootstrap/.bootstrap-inputs.json*` and re-run. Terraform state is unaffected. |

## Common invocations

```powershell
# First-time run, interactive, end-to-end
pwsh ./Invoke-Bootstrap.ps1 -Engine Terraform

# Just re-collect inputs (no Terraform)
pwsh ./Invoke-Bootstrap.ps1 -Phase configure

# Validate only (Azure + GitHub API checks)
pwsh ./Invoke-Bootstrap.ps1 -Phase validate

# Dry-run plan, never apply
pwsh ./Invoke-Bootstrap.ps1 -PlanOnly

# Apply existing sidecar without prompts (e.g. in CI / scripted re-run)
pwsh ./Invoke-Bootstrap.ps1 -Phase terraform -AutoApprove

# Move state SA / reinitialise backend
pwsh ./Invoke-Bootstrap.ps1 -Phase terraform -Reconfigure -AutoApprove

# Bypass tool-version checks (e.g. nonstandard `gh` install path)
pwsh ./Invoke-Bootstrap.ps1 -SkipPreflight
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Tool 'gh' not found in PATH` (preflight) | `gh` CLI not installed | Install GitHub CLI (`winget install GitHub.cli`) or pass `-SkipPreflight` and export `GITHUB_TOKEN` manually. |
| `Token missing 'workflow' scope` | The PAT used by `gh auth token` doesn't include `workflow` | Re-run `gh auth login -s workflow,repo,admin:org`. The wizard probes `/user` scopes via the `X-OAuth-Scopes` response header. |
| `az tenant mismatch: expected … got …` | Wizard refuses to run when `az account show` doesn't match `tenant_id` in sidecar | `az login --tenant <correct-tenant>` and retry. |
| `billing_scopes must contain a 'default' entry` | First-pass typo or skipped the default key in the BillingScopes group | `-Phase configure`, re-enter that group. |
| `terraform.tfvars.json appears hand-edited (SourceHash mismatch)` | Drift detection — the rendered file's hash doesn't match what the sidecar would re-render to | The wizard asks before overwriting. Either re-render (lose hand edits) or `-Phase terraform` to keep your edits and run Terraform against the existing file. |
| `Group 'BillingScopes' has 0 entries — at least 1 (default) required` | Pressed Enter through every prompt | Re-run, type at least the `default` entry's fields. |
| Wizard hangs on a prompt | Running in a non-PTY environment (e.g. some CI runners) | Use `-NonInteractive` and ensure `.bootstrap-inputs.json` is pre-populated; combine with `-AutoApprove` if you also want apply. |
| `tfplan` exists but `apply` was skipped | You ran `-PlanOnly` or declined the y/N prompt | `pwsh ./Invoke-Bootstrap.ps1 -Phase terraform -AutoApprove` will apply the existing plan. |

## Implementation notes

The module currently provides engine discovery, a stable bootstrap command,
and configuration validation. For Terraform it calls the existing single-file
`Invoke-Bootstrap.ps1` implementation. This compatibility boundary lets the
Terraform path remain stable while a Bicep starter and shared orchestration are
added incrementally.

The Terraform script is organised into nine sections (search for
`# Section N --`):

| Section | Purpose |
|---|---|
| 0 | Output helpers (`Write-Banner`, `Write-Header`, `Write-Ok`, `Write-Plan`, `Write-Done`, `Write-Skip`, etc.) |
| 1 | Validation primitives (`Test-Guid`, `Test-MgBareName`, `Test-StorageAccountName`, etc.) |
| 2 | Prompt helpers (`Read-PromptString`, `Read-PromptChoice`, `Read-PromptBool`) |
| 3 | JSON state I/O — atomic write + `.bak` rotation (`Get-Inputs`, `Save-Inputs`) |
| 4 | Preflight phase (`Test-ToolVersion`, `Invoke-Preflight`) |
| 5 | Configure phase — one `Configure-*` function per group (`Invoke-Configure` dispatches) |
| 6 | Validate phase (`Invoke-Validate`) |
| 7 | Render `terraform.tfvars.json` from the sidecar (`Render-Tfvars`) |
| 8 | Terraform phase (`Invoke-Terraform`) |
| 8.5 | Destroy / teardown helpers (`Assert-DestroyTenant`, `Approve-Action`, `Get-AzResource`, `Invoke-GhApi`, `Get-DestroyTargets`, `Invoke-TerraformDestroy`, `Invoke-ForceCleanup`, `Show-BillingReminders`, `Invoke-CleanBootstrapFolder`) |
| 9 | Main dispatcher (mode routing: BOOTSTRAP / DESTROY / CLEAN-ONLY) |

---

## Destroying / undoing a bootstrap

The same wizard also undoes itself. Use this when a bootstrap was
applied **by mistake** — wrong tenant, wrong GitHub repo, typo in a
Management Group ID, abandoned POC, you want a do-over — and you
want to delete the resources before re-running with corrected inputs.

> 🧹 **TL;DR** — `cd bootstrap; pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf`
> to see what would happen, then drop `-WhatIf` to do it interactively.
> Add `-IncludeStateContainer` and/or `-IncludeGitHubRepo` only when you
> really mean it. `-CleanBootstrapFolder` scrubs local files at the end.

### When to use destroy vs other recovery paths

| Situation | Use |
|---|---|
| You ran the bootstrap against the wrong tenant / wrong GitHub repo and want to start over | `Invoke-Bootstrap.ps1 -Destroy` (this section) |
| You want to **decommission a single vended subscription** (not the platform itself) | [Retire a subscription](operators/retire-subscription.md) |
| You want to re-collect bootstrap inputs without destroying anything | `Invoke-Bootstrap.ps1 -Phase configure` |
| You just want to see what bootstrap created without changing anything | `Invoke-Bootstrap.ps1 -Destroy -WhatIf` |
| You want to wipe local Terraform state + the sidecar files (no Azure / GitHub action) | `Invoke-Bootstrap.ps1 -CleanBootstrapFolder` |

### How destroy mode picks its path

```
                  ┌──────────────────────────────┐
                  │ Local terraform.tfstate file │
                  │ exists in bootstrap/ ?       │
                  └──────────────┬───────────────┘
                                 │
                ┌────────────────┴────────────────┐
                │                                 │
              YES                                 NO
                │                                 │
        ┌───────▼────────┐               ┌────────▼─────────┐
        │ terraform      │               │ Force-cleanup    │
        │ destroy        │               │ via az + gh APIs │
        │ (preferred)    │               │ (fallback)       │
        └────────────────┘               └──────────────────┘
        Knows EXACTLY what to            Reads the sidecar
        delete because state is          (.bootstrap-inputs.json)
        intact. Cleanest path.           and best-effort deletes
                                          by name.
```

`terraform destroy` is always the cleanest option when state is intact.
The force-cleanup path is the safety net for when state has been lost
(workstation rebuild, deleted state file, never migrated to a remote
backend) — it leans on the JSON sidecar to know what resources to look
for.

### Destroy-mode flow

```
┌───────────┐   ┌───────────┐   ┌───────────────────────┐
│ preflight │ → │ discover  │ → │ destroy + reminders   │
└───────────┘   └───────────┘   └───────────────────────┘
   tools          read-only        terraform destroy
   + auth         probe of         OR force-cleanup
   + tenant       Azure + GH       + billing-scope
   match                           reminders
```

Destroy mode is a single fixed flow (no `-Phase` selector). `-WhatIf`
discovers what exists and prints what would happen without performing
any deletes.

### Destroy-mode parameters

| Parameter | Purpose |
|---|---|
| `-Destroy` | Switches the wizard to destroy mode. Required for the other flags below to take effect. |
| `-WhatIf` | Standard PowerShell `-WhatIf`. Shows every action without performing any of them. |
| `-IncludeStateContainer` | Opt-in to deleting the Terraform state container. Refused even with this flag if the container has any blobs — would orphan **vended-sub state**, not just bootstrap state. |
| `-IncludeGitHubRepo` | Opt-in to deleting the entire GitHub repository. **This removes the seeded skeleton, every PR, every issue, all of it** — do not use unless you really mean it. |
| `-CleanBootstrapFolder` | After destroy, wipe `.terraform/`, `.terraform.lock.hcl`, `terraform.tfstate*`, `tfplan`, `.bootstrap-inputs.json[.bak]`, `terraform.tfvars.json`. Also works standalone (no `-Destroy`) — pure local cleanup. |
| `-AutoApprove` | Skip per-item `Y/N` prompts. **Tenant-mismatch refusal still applies.** |
| `-NonInteractive` | Disable all prompts. **Without `-AutoApprove` this becomes a hard refusal** at every destructive op — pair the two for unattended cleanup. |
| `-SkipPreflight` | Bypass tool + auth + tenant-match checks. Escape hatch. |

### Safety rails (destroy mode)

Enforced regardless of `-AutoApprove` or `-NonInteractive`:

| Rail | Why it exists | How to override |
|---|---|---|
| **Tenant mismatch refusal** | If `az account show --query tenantId` doesn't match `tenant_id` in the sidecar, the script throws and exits before touching anything — prevents wiping resources in the wrong tenant when an operator has multiple `az login` sessions. | `az login --tenant <correct-tenant>` and re-run, or fix the sidecar. There is no `-Force` flag for this. |
| **State container only deleted when empty** | The container holds **every vended subscription's Terraform state** keyed by `<archetype>/<sub-name>.tfstate`, not just bootstrap state. Deleting it while non-empty would orphan live workload state. | `az storage blob delete-batch --auth-mode login --account-name <sa> --source <container>` to clear it first, then re-run with `-IncludeStateContainer`. |
| **GitHub repo never deleted by default** | The repo holds the seeded skeleton **and** every vending PR history — you almost always want to keep it and just delete the orchestration variables. | `-IncludeGitHubRepo` — but the wizard still asks `Y/N` unless you also pass `-AutoApprove`. |
| **Billing scope role never touched** | Revoking `SubscriptionCreator` on the billing scope differs per agreement type (EA / MCA / MPA), needs different roles on the operator, and is easy to footgun. | The wizard prints the exact commands for each billing scope. Run them by hand. |
| **`-NonInteractive` without `-AutoApprove` refuses to delete** | Prevents accidental "I'll just run it headless" deletes that skipped a confirmation gate. | Always pair `-NonInteractive` with `-AutoApprove` for unattended runs. |
| **`-WhatIf` overrides everything** | Standard PowerShell semantics. | None — by design. |

### What destroy cleans up

#### Azure (in the platform subscription, in this order)

1. **Role assignments granted to the UAMI's `principalId`** — must be
   removed first so role-assignment orphans don't outlive the UAMI:
   - Terraform only: `Storage Blob Data Contributor` on the state container
   - `Contributor` on the ALZ root MG
   - `User Access Administrator` on the ALZ root MG (when
     `grant_user_access_administrator = true`)
   - `Network Contributor` on the hub VNet's resource group (when a hub
     VNet is configured)
   - **Any other assignments granted to the same principal** are also
     surfaced — discovery uses
     `az role assignment list --assignee <principalId> --all`, so if
     someone manually added extra roles to the same UAMI, you'll see
     them and can choose whether to revoke them.
2. **3 Federated Identity Credentials** on the UAMI — deleted
   implicitly when the UAMI itself is removed (Azure cascades).
3. **The pipeline UAMI**.
4. **Terraform state container** (Terraform starter only, opt-in via
   `-IncludeStateContainer`, and only when empty).

The script **never** touches the state storage account, the resource
group that holds the UAMI, the platform subscription, or any
Management Group.

#### GitHub (in the configured repo, in this order)

1. **Branch protection rule** on the default branch (usually `main`).
2. **`production` Environment** (or whatever
   `production_environment_name` was set to).
3. **Managed Actions repository variables**:
   - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
   - `VENDING_ENGINE`, `ALZ_ROOT_MANAGEMENT_GROUP_ID`,
     `AZURE_DEPLOYMENT_LOCATION`
   - Terraform only: `BACKEND_RESOURCE_GROUP_NAME`,
     `BACKEND_STORAGE_ACCOUNT_NAME`, `BACKEND_CONTAINER_NAME`

   Other variables (if any) are left alone.
4. **The repository itself** (opt-in only via `-IncludeGitHubRepo`).

#### Out-of-band (instructions only)

The script prints `SubscriptionCreator` revocation commands for every
billing scope in the sidecar's `billing_scopes` map, formatted for
each agreement type. **It never executes them.** Mirrors the
`next_step_billing_role` output of `bootstrap/outputs.tf`, but for
revocation:

| Agreement | Action |
|---|---|
| `EA` | Lists enrollment-account owners and prints the `az billing enrollment-account owner remove` command stub. |
| `MCA` | Prints the portal navigation path: Billing profile → Invoice section → Access control → remove `Azure subscription creator`. (MCA doesn't have first-class CLI revocation in `az billing`.) |
| `MPA` | Prints an `az role assignment delete --assignee-object-id ... --scope ...` command with the customer scope pre-filled. |

#### Local files (opt-in only via `-CleanBootstrapFolder`)

| Removed | Notes |
|---|---|
| `.terraform/`, `.terraform.lock.hcl` | Terraform provider cache + lock |
| `terraform.tfstate`, `terraform.tfstate.backup` | Local Terraform state |
| `tfplan` | Last plan binary |
| `.bootstrap-inputs.json`, `.bootstrap-inputs.json.bak` | Wizard sidecar + backup |
| `terraform.tfvars.json` | Last rendered tfvars |

### Common destroy invocations

```powershell
cd bootstrap

# Dry-run: discover + show what would be deleted, change nothing.
pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf

# Default interactive run — Y/N for every destructive op,
# state container + repo are skipped (no opt-in flags).
pwsh ./Invoke-Bootstrap.ps1 -Destroy

# Same as above but skip prompts.
pwsh ./Invoke-Bootstrap.ps1 -Destroy -AutoApprove

# Full do-over: nuke the UAMI, all RBAC, the (empty) state container,
# the GitHub repo, AND wipe local sidecar + tfstate.
# Will still ask Y/N for each destructive op unless -AutoApprove.
pwsh ./Invoke-Bootstrap.ps1 -Destroy `
    -IncludeStateContainer -IncludeGitHubRepo `
    -CleanBootstrapFolder `
    -AutoApprove

# Unattended cleanup (e.g. from CI). Refuses without -AutoApprove.
pwsh ./Invoke-Bootstrap.ps1 -Destroy -NonInteractive -AutoApprove

# Standalone local-file cleanup (no Azure / GitHub action).
pwsh ./Invoke-Bootstrap.ps1 -CleanBootstrapFolder
```

### Choosing the right destroy path

The two paths cover different failure modes. You almost never need to
think about which one is running — the script picks based on whether
`bootstrap/terraform.tfstate` exists — but the table below is useful
when triaging unexpected behaviour.

| Symptom | Path that runs | Notes |
|---|---|---|
| First bootstrap from a clean workstation, never migrated state to remote backend | `terraform destroy` | Local state was created by the wizard's `terraform apply`. Cleanest path. |
| State migrated to a remote backend after bootstrap | `terraform destroy` (if the backend was reconfigured to local for cleanup) OR force-cleanup | If you used `terraform init -migrate-state` to push state to Azure, point Terraform back at the remote (or copy state down) before cleanup. Otherwise force-cleanup is the safe fallback. |
| Workstation rebuilt, lost `terraform.tfstate` | Force-cleanup | Driven entirely from the sidecar. Best-effort by name. |
| Sidecar deleted too | Neither — script aborts | You'll have to clean up by hand. Look up the UAMI by name in the portal, list its role assignments, and remove them + the UAMI + the container + the GitHub variables manually. |

### Destroy-mode troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `az tenant mismatch. Expected: <X>  Actual: <Y>` | Active `az` session is on a different tenant than the one the bootstrap targeted. | `az login --tenant <X>` and re-run. The wizard refuses to operate cross-tenant — there's no override. |
| `Refusing to '<op>' in -NonInteractive mode without -AutoApprove` | Headless run hit a destructive op gate. | Add `-AutoApprove` for unattended runs (after verifying with `-WhatIf` first). |
| `State container '<c>' has N blob(s); refusing to delete` | The container still holds vended-sub state. | Either: (a) delete the vended-sub state files manually if you know they're stale, then re-run with `-IncludeStateContainer`; or (b) leave the container alone and re-run **without** `-IncludeStateContainer`. |
| `No sidecar found at <path>. -Destroy needs the sidecar` | The sidecar was deleted/moved, or the wizard never persisted it. | Pass `-InputsPath <path>` if you have the file elsewhere. If it's truly gone, you'll have to clean up by hand — without the sidecar the script can't know what to look for. |
| `gh api ... failed: HTTP 401` | `GITHUB_TOKEN` is missing or expired. | `gh auth refresh -h github.com -s workflow` or set `$env:GITHUB_TOKEN` to a PAT with `repo` (and `delete_repo` if using `-IncludeGitHubRepo`). |
| `gh api ... failed: HTTP 403 ... delete_repo` | Token lacks the `delete_repo` scope. | Re-issue the PAT with `delete_repo`, then export it as `GITHUB_TOKEN`. `gh auth login` does **not** request `delete_repo` by default. |
| `gh api ... failed: HTTP 404` for the repo | Repo already deleted or wrong owner/name in the sidecar. | Confirm with `gh repo view <owner>/<repo>`. If it's already gone, just skip with `N` at the prompt. |
| `terraform destroy` errors on `github_repository_file` resources | API-side rate limit or transient `gh` error. | Re-run — `terraform destroy` is idempotent. |
| Role assignment delete returns "RoleAssignmentNotFound" | Already removed (perhaps by `terraform destroy` from another workstation). | Safe to ignore. |

### What destroy intentionally does NOT do

- **Does not touch the platform state storage account, the platform
  subscription, or any Management Group.** Removing those is way out
  of scope for a bootstrap-undo flow — they're shared platform
  resources owned by someone else's pipeline.
- **Does not delete the resource group that holds the UAMI.** That RG
  pre-existed the bootstrap (the bootstrap takes its name as input);
  the operator who created it owns its lifecycle.
- **Does not revoke any role granted by something other than the
  bootstrap.** Discovery uses
  `az role assignment list --assignee <principalId> --all`, so anything
  granted manually to the same principal **will** appear in the
  discovery summary, but you choose `Y/N` per item — nothing is
  destroyed without confirmation.
- **Does not delete the `SubscriptionCreator` role on the billing
  scope.** See the "Out-of-band" section above for the manual commands.
- **Does not migrate state, push commits, or open PRs.** Pure
  destruction only.

## See also

- [Bootstrap reference](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md)
- [Operator guide](operators/bootstrap.md) for setup and where the wizard fits
- [`docs/billing-scopes.md`](billing-scopes.md) — `billing_scopes` map format
- [`docs/tagging.md`](tagging.md) — `cost_allocation_tag` + `mandatory_tags`
- [`docs/glossary.md`](glossary.md) — UAMI, FIC, OIDC subject claims, etc.
