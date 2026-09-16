# Quick start

You've created a repository from the **Azure Subscription Vending** template.
This page gives you the short path from "fresh repo" to "I vended my first
subscription." For full details, follow the linked docs.

---

## Prerequisites (5 min read)

Before anything else, confirm the items in the
[prerequisite table](docs/onboarding.md#prerequisites--confirm-you-have-these):

- Azure Landing Zones deployed (root MG + child MGs for your archetypes)
- Platform / management subscription with a Terraform state storage account
- Billing scope ID(s) (EA, MCA, or MPA)
- GitHub org + a PAT (`repo` scope, `admin:org` if creating a new repo)
- Az CLI + `gh` CLI installed, logged in to your tenant

If any of those are missing, the bootstrap wizard will tell you exactly
which one on the first run.

---

## Day 1: bootstrap (15 min)

```powershell
az login --tenant <your-tenant-id>
$env:GITHUB_TOKEN = "<your PAT>"   # or rely on `gh auth login`

Import-Module ./powershell/SubscriptionVending/SubscriptionVending.psd1
Get-SubscriptionVendingEngine
Initialize-SubscriptionVending -Engine Terraform # or Bicep
```

The PowerShell module is the accelerator entry point. Both available starters
delegate repository and identity setup to the shared
`bootstrap/Invoke-Bootstrap.ps1` workflow. It prompts for every input,
validates values against Azure and GitHub APIs, and uses Terraform for the
one-time bootstrap. When it finishes, it prints:

- `uami_principal_id` (needed for the billing-role grant below)
- `github_repository_full_name` (your new vending repo)

**Immediately after bootstrap**, grant the billing-scope role following
[Step 2 in the onboarding doc](docs/onboarding.md#step-2--grant-subscriptioncreator-on-the-billing-scope).

Full bootstrap reference: [`docs/bootstrap-wizard.md`](docs/bootstrap-wizard.md)

The selected engine is persisted for the generated repository and cannot be
switched in place.

---

## Day 1: vend your first subscription (5 min)

In the newly created GitHub repo:

1. Copy an example YAML from `landingzones/<archetype>/`
2. Fill in the contract fields (see [`docs/first-vend.md`](docs/first-vend.md))
3. Open a PR, review the plan output, merge
4. Approve the `production` environment gate in GitHub Actions
5. Subscription appears in Azure within ~5 minutes

---

## Day 7: settle in

- Add team members as CODEOWNERS per archetype
  ([`CONTRIBUTING.md`](CONTRIBUTING.md))
- Review tagging and cost-allocation settings
  ([`docs/tagging.md`](docs/tagging.md))
- Enable Azure Policy tag inheritance at the MG scope
  (recommended in [`docs/tagging.md`](docs/tagging.md#azure-policy-tag-inheritance-recommended))
- Familiarize with the PR validation + apply workflow
  ([`.github/CICD.md`](.github/CICD.md))

---

## Day 30: operationalize

- Review Dependabot PRs for GitHub Actions and Terraform dependencies
- Review and bump the selected engine's AVM pin when a new version ships
  ([`CONTRIBUTING.md`](CONTRIBUTING.md#bumping-the-avm-module-pin))
- Add new archetypes if your MG hierarchy needs them
  ([`CONTRIBUTING.md`](CONTRIBUTING.md#adding-a-new-archetype))
- Review budget and cost-allocation tags across vended subscriptions

---

## Key documentation

| Doc | What it covers |
|-----|----------------|
| [`docs/onboarding.md`](docs/onboarding.md) | Full prerequisite list + bootstrap walkthrough |
| [`docs/first-vend.md`](docs/first-vend.md) | Step-by-step first subscription vend |
| [`docs/architecture.md`](docs/architecture.md) | How the skeleton works under the hood |
| [`docs/archetypes.md`](docs/archetypes.md) | Corp / online / sandbox rules and defaults |
| [`docs/billing-scopes.md`](docs/billing-scopes.md) | Billing scope formats + CLI discovery commands |
| [`docs/tagging.md`](docs/tagging.md) | Tag strategy, cost allocation, Policy inheritance |
| [`docs/teardown.md`](docs/teardown.md) | Decommissioning a vended subscription |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to modify archetypes, bump pins, add features |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes |

---

## Need help?

If something goes wrong during bootstrap, the wizard is resumable. Re-run
`Initialize-SubscriptionVending` with the same engine and it picks up where
it left off.

To undo a bootstrap that went sideways, use destroy mode:

```powershell
# The legacy script remains the Terraform lifecycle implementation for now.
cd bootstrap
pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf   # preview what would be removed
pwsh ./Invoke-Bootstrap.ps1 -Destroy            # tear it down
```

See [`docs/bootstrap-wizard.md`](docs/bootstrap-wizard.md#destroying--undoing-a-bootstrap)
for the full destroy reference.
