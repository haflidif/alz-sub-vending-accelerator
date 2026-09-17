# Glossary

Terms you'll see across the skeleton, defined in one place. Acronyms
spell out the first time, then the short form is used.

## A

**Archetype**: A named template that classifies a subscription (`corp`,
`online`, or `sandbox` out of the box). Each archetype maps to a folder under
`landingzones/`, rules in the selected engine adapter, and a destination
management group in the selected platform configuration. See
[`docs/archetypes.md`](archetypes.md).

**AVM**: Azure Verified Modules. Microsoft-curated Terraform and Bicep modules
with consistent input contracts, telemetry, and tested release processes.
The accelerator wraps one subscription-vending pattern for each engine.

**AVM module pin**: The exact upstream version in `terraform/main.tf` or
`bicep/main.bicep`. Terraform uses `0.3.1`; Bicep uses `0.8.0`. Review every
bump because both input contracts are pre-1.0.

## B

**Billing scope** — A path string under
`/providers/Microsoft.Billing/billingAccounts/...` identifying where
subscriptions are billed. Format varies by agreement type: EA →
`enrollmentAccounts/<id>`, MCA →
`billingProfiles/<x>/invoiceSections/<y>`, MPA → `customers/<id>`. See
[`docs/billing-scopes.md`](billing-scopes.md).

**`billingScopeKey`**: Optional field in `sub.yaml` that selects a configured
billing scope and defaults to `default`. It lets one vending repository span
multiple billing scopes, such as MCA for production and EA for sandbox.

**Bootstrap**: One-shot Terraform module under `bootstrap/` that
creates the pipeline UAMI, federated credentials, MG-scoped RBAC,
GitHub repo / variables / environment / branch protection, and seeds
the selected Terraform or Bicep runtime into the new repo. Run by an operator
from a workstation.
Its Terraform state is **local** to the operator's machine; the
bootstrap is **not** re-run for day-2 changes. See the
[bootstrap reference](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md).

**Bootstrap wizard**: `bootstrap/Invoke-Bootstrap.ps1`. Interactive
PowerShell wrapper around the bootstrap module. It prompts, validates,
persists, runs Terraform. See
[`docs/bootstrap-wizard.md`](bootstrap-wizard.md).

## C

**CAF** — Cloud Adoption Framework. Microsoft's prescriptive guidance
for Azure adoption. The skeleton's tag baseline (lowercase keys, no
separators), naming conventions, and management-group structure derive
from CAF.

**CODEOWNERS** — GitHub file at `.github/CODEOWNERS` that auto-requests
reviews from a team/user when files under a given path change. Rendered
by `bootstrap/` from `bootstrap/templates/CODEOWNERS.tftpl` using the
operator's `codeowners_default_team` + `codeowners_archetype_teams`
inputs. Not present in the skeleton checkout itself.

**Cost-allocation tag** — Operator-configurable cost-attribution tag in
addition to the always-on `costcenter` tag. Operator sets the tag KEY
(`activitycode`, `wbselement`, `programcode`, etc.), whether it's
required, and an optional regex. See
[`docs/tagging.md`](tagging.md#cost-allocation-tag-configurable).

## D

**Dependabot**: GitHub's automated dependency updater. The skeleton
configures it for GitHub Actions pins (weekly) and the Terraform
modules in `terraform/` (weekly) and `bootstrap/` (monthly). See
[`.github/dependabot.yml`](../.github/dependabot.yml).

**DevTest** — Azure subscription offer with reduced rates for
non-production workloads. Opt-in via `workload: DevTest` in `sub.yaml`.
Requires your EA/MCA billing scope to be entitled for the
offer (`MS-AZR-0148P` on EA). Otherwise the selected AVM returns
`EntitlementNotFound`.

**Drift detection** — In the wizard, the `# SourceHash:` marker
embedded in `terraform.tfvars.json` lets the wizard detect whether the
rendered file has been hand-edited since the last wizard run. Triggers
a confirmation prompt before overwrite.

## E

**EA** — Enterprise Agreement. Microsoft's volume-licensing program for
large organisations. Billing scope path:
`/providers/Microsoft.Billing/billingAccounts/<id>/enrollmentAccounts/<id>`.

## F

**FIC** — Federated Identity Credential. Azure resource attached to a
UAMI (or app registration) that trusts a specific OIDC issuer + subject
combination. Lets GitHub Actions request an Azure access token without
any client secret. `bootstrap/` creates three FICs on the pipeline
UAMI:

```
repo:<owner>/<repo>:ref:refs/heads/main      ← apply.yml on push to main
repo:<owner>/<repo>:pull_request             ← pr-validate.yml on PR
repo:<owner>/<repo>:environment:production   ← apply.yml's apply job (gated)
```

See [`.github/CICD.md → OIDC subject claims`](../.github/CICD.md#oidc-subject-claims).

## G

**`GITHUB_TOKEN`** — PAT (Personal Access Token) or OAuth token used by
the bootstrap's `github` provider. Needs `repo` (always) and
`admin:org` (when `create_github_repository = true` against an org).
The wizard resolves this from `$env:GITHUB_TOKEN` or `gh auth token` —
**process scope only**, never persisted.

## H

**Hub VNet**: Platform team's connectivity hub virtual network.
Spoke subscriptions (typically `corp`) peer to it for shared egress,
ExpressRoute / VPN, and central firewall. Bootstrap's
`hub_virtual_network_resource_id` input flows to the selected engine
configuration; per-sub `network.hubPeering` opts in. The
pipeline UAMI receives `Network Contributor` **RG-scoped to the hub
VNet's RG** (not subscription-wide).

## I

**Identity tags** — Tag layer derived from `sub.yaml` fields
(`businessowner`, `technicalcontact`, `costcenter`, `workloadname`,
`environment`). Always wins on conflict with caller-supplied tags. See
[`docs/tagging.md`](tagging.md).

## J

**JSON Schema**: `landingzones/sub.schema.json` (Draft 2020-12).
Validates every `sub.yaml` in your editor (via `# yaml-language-server`
directive), in CI (`schema-validate` job), and again through the selected
engine's validation. See
[`docs/schema-validation.md`](schema-validation.md).

## L

**Landing zone** — Microsoft's term for a workload subscription with
its baseline networking / identity / governance plumbing pre-applied.
In this skeleton, "landing zone" = one row under `landingzones/<arch>/`.

## M

**Management Group (MG)** — Azure governance container that groups
subscriptions for inherited policy + RBAC. Archetype MGs (e.g.
`corp` / `online` / `sandbox`) descend from a common root MG (where the
pipeline UAMI receives `Management Group Contributor`).

**Mandatory tags**: Platform-wide tags applied to every vended subscription.
CAF-aligned defaults use `managedby=terraform` for Terraform repositories and
`managedby=bicep` for Bicep repositories, plus
an engine-specific `source` value and
`deployedby=subscription-vending-pipeline`. Configurable via
`bootstrap/`'s `mandatory_tags` input. See
[`docs/tagging.md`](tagging.md).

**MCA** — Microsoft Customer Agreement. Direct-to-Microsoft purchase
contract. Billing scope path:
`/providers/Microsoft.Billing/billingAccounts/<name>/billingProfiles/<id>/invoiceSections/<id>`.

**MPA** — Microsoft Partner Agreement (CSP). Partner buys for customer.
Billing scope path:
`/providers/Microsoft.Billing/billingAccounts/<name>/customers/<id>`.
Requires *Indirect Buyer* / *Indirect Provisioner* roles on the customer
scope.

## O

**OIDC** — OpenID Connect. The authentication protocol GitHub uses to
issue short-lived ID tokens to workflows, which Azure then exchanges
for ARM access tokens via the FIC. Replaces stored service-principal
secrets entirely.

**OIDC subject claim** — The string embedded in the GitHub OIDC token
that the FIC matches against (`repo:<owner>/<repo>:ref:refs/heads/main`,
`...:pull_request`, `...:environment:<name>`). Renaming `main` or the
production environment requires updating both the FIC and the workflow.

**Operator** — The platform-team person running `bootstrap/` (and
later, day-2 PRs against the seeded vending repo). Distinct from
"consumer" (the app-team person authoring `sub.yaml` files).

## P

**Platform subscription**: The subscription that owns the pipeline UAMI and,
for Terraform, the runtime state storage account. Often called the management
subscription. The bootstrap uses `platform_subscription_id` for this value.

**Pre-bootstrap** — The green-field prerequisites that must exist before
`bootstrap/` runs: a root MG hierarchy, a platform subscription, and
optionally a hub VNet. Terraform also requires a state storage account. On a
green-field POC tenant you create these by any means; if you already have an
Azure Landing Zone they usually exist.

## S

**Sidecar** — The `bootstrap/.bootstrap-inputs.json` file the wizard
writes to persist operator inputs between runs. Atomically updated
per-group with `.bak` rotation. Gitignored. The wizard re-renders
`terraform.tfvars.json` from this sidecar on every run.

**Skeleton** — This repository. The template that an operator uses (via
"Use this template" or by cloning), configures via `bootstrap/`, and
pushes to a new vending GitHub repo. Distinct from the **vending repo**
(see below).

**Terraform state key**: Per-subscription Terraform state blob name:
`<archetype>/<sub-name>.tfstate`. Set via `terraform init
-backend-config="key=..."` so each subscription has its own state file
in the shared `subvending-tfstate` container.

**`sub.yaml`** — Shorthand for `landingzones/<archetype>/<name>.yaml`.
One file = one subscription contract. Validated against
`landingzones/sub.schema.json`.

## T

**`terraform.auto.tfvars`** — Auto-loaded Terraform variable file at
`terraform/terraform.auto.tfvars`. **Rendered by `bootstrap/files.tf`**
and committed to the seeded vending repo (NOT in the skeleton). Carries
platform context: `tenant_id`, `vending_subscription_id`,
`billing_scopes`, `management_group_ids`, `hub_virtual_network_resource_id`,
`cost_allocation_tag_*`, `mandatory_tags`. Day-2 changes are made by
editing it directly via PR in the seeded repo — the bootstrap is not
re-run for value rotations.

**`platform.json`**: Bicep engine configuration at
`bicep/platform.json`. Rendered by `bootstrap/files.tf` and committed to the
seeded vending repository. Carries tenant, billing, management-group,
network, tag, and resource-provider settings.

## U

**UAMI** — User-Assigned Managed Identity. Azure RBAC identity with
no secret to rotate. Created by `bootstrap/` for the pipeline; OIDC FICs
attached so GitHub Actions can request tokens without storing
credentials.

## V

**Vending repo** — The GitHub repo that `bootstrap/` creates (or
configures) in your GitHub org. Receives the shared runtime files, one selected
engine package, and that engine's rendered platform configuration. Day-2
vending and platform changes happen via PR here, not in the skeleton.

**Vending sub**: The subscription represented by one YAML request and one
Terraform or Bicep deployment matrix item.

## W

**Workload** — Two distinct usages, watch context:
1. AVM module input — `Production` (default, always available) or
   `DevTest` (requires EA/MCA Dev/Test entitlement). Emitted as the
   `environment` tag.
2. Naming-convention segment — the application/system identifier in
   `<env>-<archetype>-<workload>[-<seq>]` (e.g. `erp`, `web`,
   `analytics`).
