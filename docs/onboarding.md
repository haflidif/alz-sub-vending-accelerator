# Operator onboarding

One-time setup the platform team performs **before** any subscription can be
vended. After this is done, day-to-day vending happens via PRs — see
[`first-vend.md`](first-vend.md).

> Total time: ~15 minutes (mostly waiting for the bootstrap apply and a
> billing-role round-trip).

## Prerequisites — confirm you have these

| # | Requirement | How to verify |
|---|---|---|
| 1 | **ALZ deployed** — root MG with `corp`/`online`/`sandbox` (or your equivalent) child MGs | `az account management-group list -o table` |
| 2 | **Platform/management subscription** with a Terraform state storage account (typically deployed by the [ALZ Terraform Accelerator](https://github.com/Azure/alz-terraform-accelerator)) | `az storage account list --subscription <mgmt-sub> -o table` |
| 3 | **Billing scope** ID(s) — EA enrollment account, MCA invoice section, or MPA customer | `az billing account list -o table` (full discovery commands in [`docs/billing-scopes.md`](billing-scopes.md)) |
| 4 | **Optional: hub VNet** — full Azure resource ID if you peer corp/online subs to it | `az network vnet show --ids <id>` |
| 5 | **GitHub org** + a **PAT** with `repo` (and `admin:org` if creating a new repo) | `gh auth status` |
| 6 | **Az CLI logged in** to the platform tenant with rights to create UAMI, assign roles at MG scope, and create blob containers in the state SA | `az account show` |
| 7 | **PowerShell 7.2+, Terraform `>= 1.15.5` and `< 1.16.0`, Azure CLI 2.64.0+, and GitHub CLI 2.50.0+** | `$PSVersionTable.PSVersion`; `terraform version`; `az version`; `gh version` |

If you're missing item 1 or 2 (testing in a green-field tenant), create a
minimal MG hierarchy, platform subscription, and state storage account by
any means first. If you already have an Azure Landing Zone, skip this
entirely.

> ### One shared Terraform bootstrap layer
>
> The skeleton ships **one** Terraform bootstrap layer that the
> operator runs locally:
> [`bootstrap/`](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/tree/main/bootstrap).
> It creates the
> pipeline UAMI, OIDC federation, MG-scoped RBAC, GitHub repo + branch
> protection + production environment, and seeds the vending skeleton
> into that new repo with either `terraform/terraform.auto.tfvars` or
> `bicep/platform.json` pre-filled.
> It is idempotent and safe to re-run.
>
> For green-field POC tenants you'll first need the prerequisites (root MG
> hierarchy, platform/management subscription, state storage account) in
> place so `bootstrap/` has something to bind to — create them by any
> means. **If you already have an Azure Landing Zone, you don't need this
> step.**
>
> Once those prerequisites exist, pass their values (state SA name,
> platform subscription ID) to `bootstrap/` as inputs.

---

## Step 1: Run the bootstrap module

The accelerator ships the `SubscriptionVending` PowerShell module as its
operator entry point. Select Terraform or Bicep when creating the vending
repository. Both engines delegate the one-time repository and identity setup
to [`Invoke-Bootstrap.ps1`](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/Invoke-Bootstrap.ps1), preserving
the existing prompts, validation, saved answers, and resumability.

```powershell
az login --tenant <your-tenant-id>
$env:GITHUB_TOKEN = "<your PAT>"

Import-Module ./powershell/SubscriptionVending/SubscriptionVending.psd1
Get-SubscriptionVendingEngine
Initialize-SubscriptionVending -Engine Terraform # or Bicep
```

The wizard runs four phases:

| Phase | What happens | Re-runnable? |
|---|---|---|
| `preflight` | Verifies `terraform`, `az`, `gh`, `pwsh` versions and resolves a GitHub token. | Yes |
| `configure` | Prompts you for every bootstrap input, grouped by concern. Answers are persisted to `bootstrap/.bootstrap-inputs.json` (gitignored) and the wizard re-shows current values as defaults on the next run. | Yes — keep / edit per group |
| `validate` | Calls Azure + GitHub APIs to confirm the inputs are sane *before* you wait for `terraform apply` to discover them. | Yes |
| `terraform` | Renders `terraform.tfvars.json`, then runs `init → plan → apply`. Apply asks for an explicit `y/N` (or pass `-AutoApprove`). | Yes (Terraform handles its own state) |

Two of the inputs carry the most variation; the wizard prompts
for both but they deserve up-front thought:

* **Billing scopes** — `billing_scopes` is a map; the `default` key is
  mandatory. See [`docs/billing-scopes.md`](billing-scopes.md) for
  discovery commands per agreement type.
* **Cost-allocation tag** — operator-configurable tag KEY + required-flag
  + optional regex. See [`docs/tagging.md`](tagging.md).

When the wizard finishes, capture these outputs from
`terraform -chdir=bootstrap output`:

| Output | Used by |
|---|---|
| `uami_principal_id` | The next step (billing-role grant) |
| `github_repository_full_name` | Your new vending repo |
| `next_step_billing_role` | A copy-paste reminder of step 2 |

The [bootstrap reference](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md)
describes every resource the bootstrap creates.

### Useful wizard flags

| Flag | Use case |
|---|---|
| `-Phase configure` | Re-collect inputs without touching Terraform. |
| `-Phase validate` | Just run the Azure/GitHub API sanity checks. |
| `-PlanOnly` | End-to-end dry-run; renders `terraform.tfvars.json` and runs `plan`, no `apply`. |
| `-AutoApprove` | Skip the apply confirmation prompt (use in CI / scripted re-runs). |
| `-NonInteractive` | Disables prompts; required values must already be in `.bootstrap-inputs.json`. Combine with `-AutoApprove` to apply unattended. |
| `-Reconfigure` | Pass `-reconfigure` to `terraform init` (e.g. after moving the state SA). |
| `-SkipPreflight` | Bypass tool-version + token checks. Escape hatch. |

### Advanced — bypass the wizard (manual flow)

If you prefer to drive Terraform directly (e.g. running inside a
non-PowerShell CI runner), the legacy flow still works:

```powershell
cd bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars        # fill in every value by hand

az login --tenant <your-tenant-id>
$env:GITHUB_TOKEN = "<your PAT>"

terraform init
terraform plan
terraform apply
```

The wizard simply automates this sequence with input validation and a
JSON-rendered `terraform.tfvars.json` instead of HCL. Either flow leaves
identical state behind.

---

## Step 2 — Grant `SubscriptionCreator` on the billing scope

The only thing the Terraform bootstrap **cannot** do, because billing-role
assignments live outside the ARM control plane. Use the upstream
[ALZ PowerShell helper][grant-script] which assigns role definition
`a0bcee42-bf30-4d1b-926a-48d21664ef71`.

[grant-script]: https://github.com/Azure/ALZ-PowerShell-Module/blob/main/src/ALZ/Public/Grant-SubscriptionCreatorRole.ps1

```powershell
Install-Module -Name ALZ -Scope CurrentUser
Import-Module ALZ
```

### EA (Enterprise Agreement)

```powershell
Grant-SubscriptionCreatorRole `
  -servicePrincipalObjectId "<uami_principal_id from step 1>" `
  -billingAccountID "<ea-billing-account-id>" `
  -enrollmentAccountID "<enrollment-account-id>"
```

### MCA (Microsoft Customer Agreement)

```powershell
Grant-SubscriptionCreatorRole `
  -servicePrincipalObjectId "<uami_principal_id from step 1>" `
  -billingAccountID "<mca-billing-account-name>" `
  -billingProfileID "<billing-profile-name>" `
  -invoiceSectionID "<invoice-section-name>"
```

### Looking up billing IDs

```bash
# EA
az billing account list --query "[].{name:name, displayName:displayName}" -o table
az billing enrollment-account list -o table

# MCA
az billing profile  list --account-name "<billing-account>" -o table
az billing invoice-section list --account-name "<billing-account>" --profile-name "<profile>" -o table
```

### Workaround if `Grant-SubscriptionCreatorRole` returns `415 Unsupported Media Type`

Older versions of the helper hit a `415` from `az rest`. Grant the role
directly:

```powershell
$ba='<ea-billing-account-id>'
$ea='<enrollment-account-id>'
$oid='<uami_principal_id>'
$tid='<tenant-id>'
$rdef='a0bcee42-bf30-4d1b-926a-48d21664ef71'  # SubscriptionCreator
$assign=[guid]::NewGuid().ToString()
$body=@{properties=@{
  principalId=$oid; principalTenantId=$tid
  roleDefinitionId="/providers/Microsoft.Billing/billingAccounts/$ba/enrollmentAccounts/$ea/billingRoleDefinitions/$rdef"
}} | ConvertTo-Json -Depth 5 -Compress
$body | Out-File -Encoding ascii .\.body.json
$url="https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$ba/enrollmentAccounts/$ea/billingRoleAssignments/${assign}?api-version=2019-10-01-preview"
az rest --method put --uri $url --headers "Content-Type=application/json" --body "@./.body.json"
Remove-Item .\.body.json
```

### DevTest entitlement (optional)

Sub-YAML's `workload` field defaults to `Production` — universally available.
Setting `workload: DevTest` opts in to the EA Dev/Test offer (`MS-AZR-0148P`),
which requires the **enrollment to be entitled** for that offer. If it isn't,
the AVM module returns:

```
RESPONSE 400: Bad Request
ERROR CODE: EntitlementNotFound
"Enrollment account does not have entitlement to create subscription for the offer type MS-AZR-0148P."
```

Have your EA Account Owner enable Dev/Test in the EA portal
(*Manage* → *Enrollment* → *Account Owners* → enable Dev/Test), or stick
with the default `Production`.

---

## Step 3 — Validate

```bash
UAMI_OID="<uami_principal_id>"
ROOT_MG="<root-mg-id>"

# UAMI exists
az identity show --ids "<uami_resource_id>" --query "{id:id, clientId:clientId, principalId:principalId}" -o table

# MG-scoped role assignments
az role assignment list --assignee "$UAMI_OID" \
  --scope "/providers/Microsoft.Management/managementGroups/$ROOT_MG" -o table

# Billing role (EA example)
az rest --method GET \
  --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/<ba>/enrollmentAccounts/<ea>/billingRoleAssignments?api-version=2019-10-01-preview" \
  --query "value[?properties.principalId=='$UAMI_OID']"

# State-container access
az role assignment list --assignee "$UAMI_OID" \
  --scope "/subscriptions/<mgmt-sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<sa>/blobServices/default/containers/subvending-tfstate" \
  -o table
```

---

## Step 4 — First vend

You're done with operator setup. Hand the new repo to your application
teams (or vend yourself) following [`first-vend.md`](first-vend.md).

---

## Updating platform inputs after bootstrap

The bootstrap is **one-shot** by design. Its Terraform state lives on the
operator workstation that ran it and is **not** maintained for day-to-day
operations. Treat the seeded vending repo as the source of truth.

Day-2 changes are made via PR to the seeded repo:

| Change | Files to edit (in the seeded vending repo) |
| --- | --- |
| Add / update a billing scope | Terraform: `terraform/terraform.auto.tfvars`; Bicep: `bicep/platform.json` |
| Change the cost-allocation tag settings | Terraform: `terraform/terraform.auto.tfvars`; Bicep: `bicep/platform.json` |
| Update platform-wide tags | Terraform: `terraform/terraform.auto.tfvars`; Bicep: `bicep/platform.json` |
| Rotate the hub VNet ID or remote-gateway setting | Terraform: `terraform/terraform.auto.tfvars`; Bicep: `bicep/platform.json` |
| Add a new archetype + MG | Selected engine rules + platform configuration + `landingzones/<arch>/` + schema enum; see [`docs/archetypes.md`](archetypes.md) |
| Add a new billing scope key | Update the selected engine configuration, then grant SubscriptionCreator on the new scope manually |
| Change branch protection / production approvers | Edit directly in GitHub (Settings → Branches / Environments) — the bootstrap configured these once but no longer manages them |
| Rotate the pipeline UAMI or recreate the repo | This is recovery, not day-2: re-run `bootstrap/` after restoring or recreating its local state. Avoid unless you have to. |

Changes to runtime engine files select all subscriptions for preview or
deployment. To re-apply *every* subscription after a platform change, use
**Actions → Apply → Run workflow → mode = all**.

---

## Iterating on the skeleton itself

The folder you ran `bootstrap/` from is the **skeleton source of truth**.
Local edits to it do *not* propagate to a seeded vending repo
automatically — `bootstrap/` only copies the skeleton during initial seed.

Two ways to push skeleton changes downstream:

1. **PR against the seeded repo** (preferred for day-2 changes). Copy the
   changed file(s) from the skeleton into the seeded repo, open a PR,
   merge. This is how every CI/Terraform/doc change reaches a deployed
   environment.
2. **Re-seed (recovery only).** Re-run `bootstrap/` with
   `copy_skeleton_files = true` and `create_github_repository = false`.
   This force-overwrites every file in the seeded repo with the skeleton
   version — only do this on a repo with no local commits worth keeping.

The skeleton folder is the template you publish (as a GitHub template
repo). The included
[`scripts/Reset-LocalState.ps1`](../scripts/Reset-LocalState.ps1) wipes
local operator state (`.bootstrap-inputs.json`, `terraform.tfvars`, `.terraform/`,
`tfstate*`) so no tenant IDs are left in your working tree.

---

## Tuning Dependabot cadence

The skeleton ships [`.github/dependabot.yml`](../.github/dependabot.yml)
with a **weekly** schedule for GitHub Actions pins and the Terraform AVM
modules. Teams with stricter change-management windows may want to
slow this down:

* Edit `.github/dependabot.yml` after seeding (it's a normal file in the
  seeded repo).
* Change `schedule.interval` to `monthly`, or group multiple updates with
  `groups:` to reduce PR noise.
* If your org runs Dependabot organisation-wide via Security settings,
  delete the per-repo file altogether — the org-level config wins.

See
[Dependabot configuration](https://docs.github.com/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
for the full schema.

---

## What if I cannot run `bootstrap/`?

The bootstrap is the **only supported** path. If you need to inspect or
reproduce its actions by hand (e.g. for an audit, or because your
environment forbids running Terraform from a workstation), see
[`bootstrap/main.tf`](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/main.tf)
names every resource explicitly. The
[bootstrap reference](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md)
describes them.
The Terraform-side resources (UAMI, FICs, role assignments, state
container) all have direct `az` / Azure REST equivalents; the GitHub-side
resources (repo variables, environment, branch protection, file seeding)
all map to GitHub REST API calls. We deliberately do **not** maintain a
parallel manual runbook because it goes out of sync the moment the
bootstrap changes.
