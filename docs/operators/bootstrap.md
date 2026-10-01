# Bootstrap

[Documentation](../README.md) | Previous: [Prerequisites](prerequisites.md) | Next: [Run](run.md)

**Audience:** platform operators establishing the vending service.
Complete [Prerequisites](prerequisites.md) before running these steps.

**Run from the accelerator source checkout**, not the generated vending
repository. The generated repository excludes `bootstrap/`, `powershell/`,
and the source starter manifests. It receives only the small
`.accelerator/metadata.json` record needed for later upgrades, including the
selected starter, source version, and hashes of the managed files seeded at
handoff. If you are reading this in a generated repository, use the
[accelerator source][source] for initial setup or reviewed recovery.

## One shared Terraform bootstrap layer

Both runtime engines use the same Terraform bootstrap to create the pipeline
identity, OIDC federation, management-group permissions, GitHub repository,
branch protection, production environment, and initial files. State storage
inputs for the vending runtime are collected only for Terraform.

A partial bootstrap is resumable. After a successful wizard apply, the
bootstrap automatically removes seeded source files from Terraform state and
records the completed handoff in its local inputs. Later plans can manage
control-plane resources without reconciling repository-owned source. Do not
rerun bootstrap to deliver engine updates. Use the generated repository's
versioned upgrade command for source updates.

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

The wizard checks tools and authentication, collects and validates inputs,
then runs Terraform init, plan, and apply. Review the plan before approving.
Its [execution phases](../bootstrap-wizard.md#phases) are distinct from the
four documentation phases.

Use the decisions from [Planning](planning.md), especially your
[billing scopes](../billing-scopes.md) and [tag settings](../tagging.md).

When the wizard finishes, capture these outputs from
`terraform -chdir=bootstrap output`:

| Output | Used by |
|---|---|
| `uami_principal_id` | The next step (billing-role grant) |
| `github_repository_full_name` | Your new vending repo |
| `next_step_billing_role` | A copy-paste reminder of step 2 |

The [bootstrap reference](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md)
describes every resource the bootstrap creates.

For preview and unattended options, use the [wizard parameter reference](../bootstrap-wizard.md#parameters).
For direct Terraform invocation, use the [manual bootstrap flow][manual].
Direct Terraform does not run the wizard's automatic handoff. Before setting
`repository_source_handoff_complete = true`, remove every
`github_repository_file` resource declared in `bootstrap/files.tf` from state.
Never enable the flag while those resources remain managed because Terraform
would plan to delete the repository files.

---

## Step 2: Grant SubscriptionCreator on the billing scope

The bootstrap deliberately leaves billing-role assignments as an explicit
operator action because they live outside the normal ARM RBAC control plane.
The accelerator helper validates the billing scope and principal, detects an
existing assignment, and assigns role definition
`a0bcee42-bf30-4d1b-926a-48d21664ef71` through the Azure Billing API.

Use `-WhatIf` first when reviewing a new billing scope.

### EA (Enterprise Agreement)

```powershell
pwsh ./scripts/Grant-SubscriptionCreatorRole.ps1 `
  -servicePrincipalObjectId "<uami_principal_id from step 1>" `
  -billingAccountID "<ea-billing-account-id>" `
  -enrollmentAccountID "<enrollment-account-id>"
```

### MCA (Microsoft Customer Agreement)

```powershell
pwsh ./scripts/Grant-SubscriptionCreatorRole.ps1 `
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

### Direct REST fallback

The helper uses a temporary UTF-8 JSON file to avoid PowerShell native
argument corruption. If it cannot run in your environment, the equivalent
EA request is:

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
$body | Set-Content -Encoding utf8NoBOM .\.body.json
$url="https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$ba/enrollmentAccounts/$ea/billingRoleAssignments/${assign}?api-version=2024-04-01"
az rest --method put --uri $url --headers "Content-Type=application/json" --body "@./.body.json"
Remove-Item .\.body.json
```

For MCA, replace the EA scope with:

```text
/providers/Microsoft.Billing/billingAccounts/<account>/billingProfiles/<profile>/invoiceSections/<section>
```

The direct REST fallback is intentionally not part of bootstrap automation.

### DevTest entitlement (optional)

Sub-YAML's `workload` field defaults to `Production`, which does not require
the optional DevTest entitlement.
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

## Step 3: Validate

Verify the identity and roles before handing the repository to consumers.
The state-container check at the end applies only to the Terraform runtime.

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
  --url "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/<ba>/enrollmentAccounts/<ea>/billingRoleAssignments?api-version=2024-04-01" \
  --query "value[?properties.principalId=='$UAMI_OID']"

# State-container access
az role assignment list --assignee "$UAMI_OID" \
  --scope "/subscriptions/<mgmt-sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<sa>/blobServices/default/containers/subvending-tfstate" \
  -o table
```

---

## Step 4: First vend

Confirm that the generated repository has its selected engine configuration
(`terraform/terraform.auto.tfvars` or `bicep/platform.json`), Actions variables,
and production reviewers. Continue to [Run](run.md) to verify the first
request and hand the repository to your application teams.

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

---

Previous: [Prerequisites](prerequisites.md) | Next: [Run](run.md) | [Documentation](../README.md)

[source]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator
[manual]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md#usage
