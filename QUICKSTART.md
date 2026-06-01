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
cd bootstrap

az login --tenant <your-tenant-id>
$env:GITHUB_TOKEN = "<your PAT>"   # or rely on `gh auth login`

pwsh ./Invoke-Bootstrap.ps1        # interactive wizard, one command
```

The wizard prompts for every input it needs, validates each value against
Azure and GitHub APIs, and runs `terraform init / plan / apply`. When it
finishes, it prints:

- `uami_principal_id` (needed for the billing-role grant below)
- `github_repository_full_name` (your new vending repo)

**Immediately after bootstrap**, grant the billing-scope role following
[Step 2 in the onboarding doc](docs/onboarding.md#step-2--grant-subscriptioncreator-on-the-billing-scope).

Full bootstrap reference: [`docs/bootstrap-wizard.md`](docs/bootstrap-wizard.md)

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
  ([`.github/README.md`](.github/README.md))

---

## Day 30: operationalize

- Review Dependabot PRs (arrives weekly for Terraform providers)
- Bump the AVM module pin when a new version ships
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

If something goes wrong during bootstrap, the wizard is resumable. Just
re-run `pwsh ./Invoke-Bootstrap.ps1` and it picks up where it left off.

To undo a bootstrap that went sideways, use destroy mode:

```powershell
pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf   # preview what would be removed
pwsh ./Invoke-Bootstrap.ps1 -Destroy            # tear it down
```

See [`docs/bootstrap-wizard.md`](docs/bootstrap-wizard.md#destroying--undoing-a-bootstrap)
for the full destroy reference.
