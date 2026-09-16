# Bootstrap

One-shot Terraform module that prepares the platform tenant + GitHub repo
to run the sub-vending pipeline. Inspired by the
[ALZ accelerator GitHub bootstrap](https://github.com/Azure/accelerator-bootstrap-modules/tree/main/alz/github),
trimmed down to **only what this repo needs**.

> ⚡ **Prefer the SubscriptionVending PowerShell module.** This README
> documents the manual Terraform flow. For day-to-day use, import
> [`SubscriptionVending.psd1`](../powershell/SubscriptionVending/SubscriptionVending.psd1)
> and run `Initialize-SubscriptionVending -Engine Terraform`. The module
> currently delegates to [`Invoke-Bootstrap.ps1`](Invoke-Bootstrap.ps1), which
> prompts for every input, validates against Azure + GitHub APIs, persists
> answers between runs, and is resumable from failure. Full reference:
> [`docs/bootstrap-wizard.md`](../docs/bootstrap-wizard.md).

## Three ways to drive bootstrap

| You want… | Entry point |
|---|---|
| Guided UX, engine selection, input validation, resumability, and drift detection | **Module:** `Initialize-SubscriptionVending -Engine Terraform` |
| Terraform compatibility or built-in destroy mode | **Legacy wizard:** `pwsh ./Invoke-Bootstrap.ps1`; see [`docs/bootstrap-wizard.md`](../docs/bootstrap-wizard.md) |
| Direct Terraform invocation (e.g. inside a non-PowerShell CI runner) | **Manual:** `terraform init / plan / apply`; see [Usage](#usage) below |

All three leave **identical Terraform state** behind.

> 🧹 **Need to undo a bootstrap?** The same wizard also tears down what
> it created — `pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf` for a
> dry-run, then drop `-WhatIf`. See
> [`docs/bootstrap-wizard.md` → "Destroying / undoing a bootstrap"](../docs/bootstrap-wizard.md#destroying--undoing-a-bootstrap).

## What it creates

**Azure** (in the platform subscription):
- User-Assigned Managed Identity for the pipeline
- 3 Federated Identity Credentials on the UAMI:
  - `repo:<owner>/<repo>:ref:refs/heads/main`
  - `repo:<owner>/<repo>:pull_request`
  - `repo:<owner>/<repo>:environment:production`
- `subvending-tfstate` container in the **existing** platform state SA
- Role assignments for the UAMI:
  - `Storage Blob Data Contributor` on the container (least privilege)
  - `Management Group Contributor` on the ALZ root MG
  - `User Access Administrator` on the ALZ root MG (toggleable)
  - `Network Contributor` on the **hub VNet's resource group** (RG-scoped, not subscription-wide). Skipped entirely if `hub_virtual_network_resource_id` is not set.
- `github_branch_protection` on `main` (toggleable via `enforce_branch_protection`):
  required PR + status checks (`PR Validate / *` jobs), required approving reviews,
  linear history, blocks force-pushes and deletions.

**GitHub**:
- Repository (optional — set `create_github_repository = true`)
- Repository **variables** consumed by `.github/workflows/*.yml`:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
  - `VENDING_ENGINE`, `ALZ_ROOT_MANAGEMENT_GROUP_ID`,
    `AZURE_DEPLOYMENT_LOCATION`
  - `BACKEND_RESOURCE_GROUP_NAME`, `BACKEND_STORAGE_ACCOUNT_NAME`, `BACKEND_CONTAINER_NAME`
- `production` Environment with required reviewers and `protected_branches` policy
- **Seeds the repo with the runtime skeleton**: `terraform/`, `landingzones/`
  examples, operator docs, `.github/workflows/`, `README.md`,
  `CONTRIBUTING.md`, and `.gitignore`. Accelerator development files such as
  `powershell/`, `starters/`, `tests/`, and proposals are excluded.
  Shared files are combined with the engine package selected by
  `starter_name`. The available Terraform starter includes `terraform/` and
  renders `terraform/terraform.auto.tfvars`. The planned Bicep starter is
  prepared to include `bicep/` and render `bicep/platform.json`. Every other
  declared engine package root is excluded.
  Done with `github_repository_file` per file (same pattern as the upstream
  ALZ accelerator's `alz/github` module). Only `bootstrap/` itself, ephemeral
  Terraform state, and the root `terraform.tfvars` (consumer-specific
  placeholders) are excluded.

## What it does NOT do (deliberately)

- **Does not create or mutate the platform state SA.** It only creates the
  container inside it, so you keep the SA's settings (versioning, soft-delete,
  network rules, CMK) under whatever pipeline owns it.
- **Does not grant the billing-scope `SubscriptionCreator` role.** That requires
  the upstream
  [`Grant-SubscriptionCreatorRole.ps1`][grant] from the ALZ PowerShell module
  and is documented as a manual follow-up — the UAMI object ID is in the
  Terraform output.

[grant]: https://github.com/Azure/ALZ-PowerShell-Module/blob/main/src/ALZ/Public/Grant-SubscriptionCreatorRole.ps1

## Prerequisites

- `az login --tenant <your-tenant>` with permissions to:
  - Create the UAMI in the chosen RG
  - Assign roles at MG and subscription scope (UAA or Owner)
  - Create blob containers in the platform SA
- A GitHub PAT exported as `GITHUB_TOKEN` with scopes:
  - `repo` (always)
  - `admin:org` (only if `create_github_repository = true` and the repo lives in an org)
- The platform state SA already exists and has Entra-ID auth enabled.

## Usage

```powershell
cd bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars   # fill in the placeholders

az login --tenant <your-tenant-id>
$env:GITHUB_TOKEN = "<your PAT>"

terraform init
terraform plan
terraform apply
```

State for the bootstrap itself is local by default. Either commit the state
to a separately backed location, or migrate it once after the first apply by
adding a `backend "azurerm"` block.

## After bootstrap

The bootstrap renders **`terraform/terraform.auto.tfvars`** directly into
the seeded repo with all platform context (tenant/billing/MGs/hub VNet/tags),
so workflows can `terraform plan` without any operator post-processing.

You only need to do **one** thing manually:

1. Run the manual `Grant-SubscriptionCreatorRole` step (see the
   `next_step_billing_role` Terraform output — the UAMI principal ID is
   pre-filled).

That's it — open a PR against an example YAML in `landingzones/` to verify
the pipeline end-to-end. See [`docs/first-vend.md`](../docs/first-vend.md).

> **Day-2 changes go to the seeded repo, not back here.** The bootstrap is
> one-shot — its Terraform state lives on the operator workstation that ran it
> and is **not** reapplied to rotate values. Anything in
> `terraform/terraform.auto.tfvars` in the seeded repo (tenant ID, MG IDs,
> hub VNet, billing scopes, mandatory tags, cost-allocation tag config) is
> changed by editing that file directly via PR. See
> [`docs/onboarding.md` → "Updating platform inputs after bootstrap"](../docs/onboarding.md#updating-platform-inputs-after-bootstrap)
> for the full table. Re-running `bootstrap/` is reserved for recovery
> (rebuilding the UAMI / repo).

## Stop managing the seeded files (recommended)

The skeleton files are pushed via `github_repository_file`. By default this
means subsequent `terraform apply` runs will revert any manual edits to
those files — useful while iterating on the bootstrap, painful during normal
operation.

After the first successful seed, do **one** of the following:

```powershell
# Option A — toggle off, keep the resources in state for safety
# (terraform.tfvars):
copy_skeleton_files = false
terraform apply

# Option B — drop them from state entirely, free-form from now on
terraform state rm 'github_repository_file.skeleton'
```

## Why a UAMI instead of an app registration?

- No client secret to rotate.
- Lifecycle managed by ARM RBAC (deleting the RG removes the identity).
- Same approach as the upstream ALZ accelerator — see [its bootstrap module][alzgh].

[alzgh]: https://github.com/Azure/accelerator-bootstrap-modules/tree/main/alz/github

## Internals

Source layout under `bootstrap/`:

| File | Purpose |
|---|---|
| [`terraform.tf`](terraform.tf) | Bootstrap provider pins: `azurerm 5.0.0`, `azuread 3.9.0`, and `github 6.13.0`. Terraform Core uses the compatible patch constraint `~> 1.15.5`. Configures `azurerm` against `platform_subscription_id` with `storage_use_azuread`, pins `azuread` to `tenant_id`, and reads `GITHUB_TOKEN` from the environment. |
| [`variables.tf`](variables.tf) | ~20 inputs across identity/location, state, RBAC, GitHub repo, branch protection, production env, billing scopes (map with EA/MCA/MPA per entry), MG IDs, cost allocation, mandatory tags, CODEOWNERS, skeleton seeding. Validation rules enforce billing-scope structure, MG ID format, GitHub handles, tag-key naming. |
| [`locals.tf`](locals.tf) | Resolves each `billing_scopes` entry into the full Azure billing scope path string. EA → `enrollmentAccounts/...`, MCA → `billingProfiles/.../invoiceSections/...`, MPA → `customers/...`. |
| [`main.tf`](main.tf) | UAMI + 3 FICs (branch / PR / production env) + state container + 4 role assignments (Storage Blob Data Contributor on the container, MG Contributor + optional UAA on the ALZ root MG, Network Contributor RG-scoped on the hub VNet's RG) + optional `github_repository` create + Actions variables + `production` environment + branch protection. |
| [`files.tf`](files.tf) | Three `github_repository_file` resources: (a) shared skeleton files plus only the selected starter package; (b) `terraform/terraform.auto.tfvars` rendered with platform context; (c) `.github/CODEOWNERS` rendered from `templates/CODEOWNERS.tftpl`. |
| [`outputs.tf`](outputs.tf) | Selected starter, UAMI identifiers, state container, GitHub repository, and `next_step_billing_role` (a pre-filled `Grant-SubscriptionCreatorRole` snippet per billing scope). |
| [`templates/CODEOWNERS.tftpl`](templates/CODEOWNERS.tftpl) | Single template rendered with the operator's `codeowners_default_team` + `codeowners_archetype_teams`. Only the **rendered** file lands in the seeded repo. |
| [`Invoke-Bootstrap.ps1`](Invoke-Bootstrap.ps1) | The interactive wizard. Handles both **create** (bootstrap; default) and **destroy** (`-Destroy`; with optional `-IncludeStateContainer`, `-IncludeGitHubRepo`, `-CleanBootstrapFolder`, standard `-WhatIf`). 9 + 1 sections; see [`docs/bootstrap-wizard.md → Implementation notes`](../docs/bootstrap-wizard.md#implementation-notes) and [`docs/bootstrap-wizard.md → Destroying / undoing a bootstrap`](../docs/bootstrap-wizard.md#destroying--undoing-a-bootstrap). |
| [`terraform.tfvars.example`](terraform.tfvars.example) | Schema-correct example — copy to `terraform.tfvars` for the manual flow, or use the wizard which writes a JSON sidecar instead. |
