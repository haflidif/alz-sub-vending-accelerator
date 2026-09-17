# Azure Subscription Vending

Azure subscription-vending accelerator with **Terraform and Bicep engines**,
one shared YAML request contract, and GitHub Actions delivery. Terraform uses
[`Azure/avm-ptn-alz-sub-vending/azure`][avm] with isolated per-subscription
state. Bicep uses the Azure Verified Modules subscription-vending pattern with
management-group deployments through
[`br/public:avm/ptn/lz/sub-vending:0.8.0`][bicep-avm].

[avm]: https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest
[bicep-avm]: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/lz/sub-vending

---

## Two audiences, two paths

| You are... | Start here |
|---|---|
| **New here** and want the shortest path to a working vend | → [`QUICKSTART.md`](QUICKSTART.md) (day 1 / day 7 / day 30 quick-start) |
| **Platform operator** standing this up for the first time | See [`docs/onboarding.md`](docs/onboarding.md), then the [bootstrap reference][bootstrap-reference] |
| **App / workload team** who has been told "vend yourself a subscription" | → [`docs/first-vend.md`](docs/first-vend.md) (open a PR with one YAML file) |
| **Curious: how does this thing work?** | → [`docs/architecture.md`](docs/architecture.md) |

---

## TL;DR — request a new subscription

1. Pick the archetype: `corp`, `online`, or `sandbox`
   (see [docs/archetypes.md](docs/archetypes.md))
2. Create a YAML file under `landingzones/<archetype>/` named per the
   [naming convention](docs/naming-convention.md):
   `<env>-<archetype>-<workload>[-<seq>].yaml`, e.g. `prod-corp-erp-001.yaml`
3. Fill in the contract — see any example file for the schema
4. Open a PR. CI runs Terraform plan or Bicep what-if for your sub and posts the preview as a comment
5. Get review from CODEOWNERS + the workload owner
6. Merge → `Apply` runs the selected engine after approval in the `production`
   GitHub Environment

---

## Repository layout

> 📌 **Two views to keep separate:**
> - **Template repo** (this one) — what operators start from. Contains
>   `bootstrap/` for one-time platform setup.
> - **Vending repo** — created by `bootstrap/` in your GitHub org. Contains
>   everything below **except** accelerator development assets, plus the
>   selected engine configuration: `terraform/terraform.auto.tfvars` or
>   `bicep/platform.json`.

```text
sub-vending/
├── README.md
├── CONTRIBUTING.md
├── CHANGELOG.md
│
├── powershell/
│   └── SubscriptionVending/
│       ├── SubscriptionVending.psd1 # accelerator module manifest
│       └── SubscriptionVending.psm1 # engine selection + bootstrap commands
│
├── starters/
│   ├── starter-contract.json       # capabilities every available starter needs
│   ├── starter.schema.json         # versioned starter manifest schema
│   ├── terraform/starter.json      # current Terraform starter declaration
│   └── bicep/starter.json          # available Bicep starter declaration
│
├── bootstrap/                     # ← skeleton-only. Operator runs ONCE.
│   ├── Invoke-Bootstrap.ps1       # Terraform compatibility implementation
│   ├── terraform.tf, variables.tf
│   ├── main.tf                    # UAMI + OIDC + RBAC + optional Terraform state + GitHub
│   ├── files.tf                   # seeds selected engine + renders platform config
│   ├── outputs.tf
│   ├── templates/CODEOWNERS.tftpl
│   ├── terraform.tfvars.example
│   └── README.md
│
├── terraform/                     # ← engine: ONE folder, no submodules (DRY)
│   ├── archetypes.tf              # declarative archetype defaults & guardrails
│   ├── backend.tf                 # azurerm partial backend (key set per-sub at init)
│   ├── locals.tf                  # parses the sub YAML + applies guardrails
│   ├── main.tf                    # ONE call to Azure/avm-ptn-alz-sub-vending/azure
│   ├── outputs.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── versions.tf
│   ├── README.md
│   └── terraform.auto.tfvars      # ← RENDERED by bootstrap (NOT in the skeleton).
│                                  #   Holds tenant/billing/MGs/hub/tags.
│
├── bicep/                         # ← available Bicep engine package
│   ├── main.bicep                 # pinned AVM sub-vending wrapper
│   ├── SubscriptionVending.Bicep.psm1
│   ├── default-resource-providers.json
│   ├── platform.schema.json
│   ├── platform.example.json
│   └── README.md
│
├── landingzones/                  # ← consumers add one YAML file per sub here
│   ├── sub.schema.json
│   ├── README.md
│   ├── corp/
│   │   └── prod-corp-erp-001.yaml
│   ├── online/
│   │   └── prod-online-web-001.yaml
│   └── sandbox/
│       └── dev-sandbox-platform-001.yaml
│
├── docs/                          # ← topic-by-topic reference
│   ├── onboarding.md              # ★ one-time operator setup (READ FIRST)
│   ├── first-vend.md              # ★ vend your first subscription
│   ├── architecture.md            # how vending works end-to-end
│   ├── repository-layout.md       # full directory tree + skeleton vs vending repo
│   ├── bootstrap-wizard.md        # Invoke-Bootstrap.ps1 reference
│   ├── archetypes.md              # corp / online / sandbox + how to add more
│   ├── billing-scopes.md          # EA / MCA / MPA paths and engine configuration
│   ├── tagging.md                 # CAF tag baseline + cost-allocation tag
│   ├── naming-convention.md
│   ├── schema-validation.md
│   ├── state-storage.md
│   ├── teardown.md                # retire a vended subscription
│   └── glossary.md
│
├── scripts/
│   ├── Reset-LocalState.ps1       # wipe local operator state (tfvars/state/caches)
│   └── README.md
│
└── .github/
    ├── CODEOWNERS                 # ← rendered by bootstrap (NOT in the skeleton)
    ├── PULL_REQUEST_TEMPLATE.md
    ├── dependabot.yml
    ├── CICD.md                    # CI/CD reference
    ├── scripts/
    │   └── discover-subs.sh       # produces the matrix used by both workflows
    └── workflows/
        ├── pr-validate.yml        # plan changed subs (PR)
        └── apply.yml              # apply on push to main + manual triggers
```

---

## How CI selects what to operate on

Both workflows use [`.github/scripts/discover-subs.sh`](.github/scripts/discover-subs.sh)
to build the per-subscription job matrix. Three modes:

| Mode | Trigger | Behaviour |
|---|---|---|
| **`changed`** | `pull_request`, `push` to `main`, or manual default | Operates only on YAML files added/modified under `landingzones/` vs the base ref |
| **`single`** | `workflow_dispatch` with `mode=single` + `sub_path=landingzones/corp/prod-corp-erp-001.yaml` (the `.yaml` suffix is optional) | Operates on exactly one subscription |
| **`all`** | `workflow_dispatch` with `mode=all` | Iterates every `landingzones/*/*.yaml` — use for wide upgrades (e.g. AVM module bump, archetype default change) |

Terraform repositories give each subscription its **own state file** at
`<container>/<archetype>/<sub-name>.tfstate`, set via
`terraform init -backend-config="key=..."`. Bicep repositories use
management-group deployments and do not maintain Terraform state. In both
engines, the workflow matrix isolates each request.

---

## Operator setup (one-time)

> 🧪 **Testing in a fresh / green-field tenant?** You'll need an MG hierarchy,
> a platform/management subscription and, for Terraform, a state storage account
> in place before running `bootstrap/`. If you don't yet have those — e.g.
> you're standing this up in a throwaway POC tenant — create a minimal MG
> hierarchy and platform subscription by any means. Terraform also requires
> a state storage account. **If you already have an Azure Landing Zone, skip
> this entirely.**

**Read [`docs/onboarding.md`](docs/onboarding.md) first** — it lists the 6
prerequisites and walks through the 3-step setup.

The shared [`bootstrap/` layer](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/tree/main/bootstrap)
uses one Terraform apply to
prepare either runtime engine:

- Pipeline UAMI + 3 GitHub OIDC federated credentials (branch / PR / environment)
- Terraform only: `subvending-tfstate` container and container-scoped
  Storage Blob Data Contributor
- Contributor + User Access Administrator on the ALZ root MG,
  Network Contributor on the **hub VNet's resource group** (not subscription-wide)
- GitHub repo + Actions variables + `production` environment with required reviewers
- Branch protection on `main` (PR + status checks + linear history)
- Seeds the selected engine package and renders its platform configuration:
  `terraform/terraform.auto.tfvars` or `bicep/platform.json`

The only step it **cannot** do is grant `SubscriptionCreator` on the
billing scope — run the upstream
[`Grant-SubscriptionCreatorRole.ps1`][grant] for that. The bootstrap output
prints the exact command with the UAMI principal ID pre-filled.

[grant]: https://github.com/Azure/ALZ-PowerShell-Module/blob/main/src/ALZ/Public/Grant-SubscriptionCreatorRole.ps1

---

## Local usage (developing the skeleton, or break-glass plan)

CI handles routine previews and deployments. You normally do not need to run
an engine locally. For Terraform break-glass planning, run from inside the
**vending repo** that bootstrap created:

```powershell
# Prerequisites
winget install Hashicorp.Terraform
winget install Microsoft.AzureCLI

# Auth as yourself (you'll need MG read + state container blob read)
az login --tenant <your-tenant-id>

# Plan a single subscription against its own state
cd terraform
terraform init `
  -backend-config="resource_group_name=<BACKEND_RESOURCE_GROUP_NAME>" `
  -backend-config="storage_account_name=<BACKEND_STORAGE_ACCOUNT_NAME>" `
  -backend-config="container_name=subvending-tfstate" `
  -backend-config="key=corp/prod-corp-erp-001.tfstate"

# terraform.auto.tfvars is auto-loaded — it carries platform context
terraform plan -var="sub_yaml_path=../landingzones/corp/prod-corp-erp-001.yaml"
```

To work on this template itself, use a throwaway tenant and platform
subscription. Add state storage when testing the Terraform starter.

---

## Adding a new archetype

The vending repo is the source of truth — the bootstrap is one-shot and is
**not** re-run for day-2 changes. Open a PR against the seeded vending repo
that updates the engine rules and shared contract:

1. Add the archetype rules to `terraform/archetypes.tf` or
   `bicep/SubscriptionVending.Bicep.psm1`, depending on the selected engine.
2. Add the matching MG ID to the selected engine configuration:
   `terraform/terraform.auto.tfvars` or `bicep/platform.json`.
3. Create `landingzones/<archetype>/` and add at least one example `<sub-name>.yaml`
4. Add the new archetype to the `enum` in
   [`landingzones/sub.schema.json`](landingzones/sub.schema.json)

See [docs/archetypes.md](docs/archetypes.md) for the full walkthrough,
and [docs/schema-validation.md](docs/schema-validation.md) for how YAML
files are validated in your editor, in CI, and by the selected engine.

---

## Wide upgrades

To re-apply every subscription (e.g. after bumping the AVM module version
or changing an archetype default):

1. **Actions → Apply → Run workflow**
2. `mode = all`
3. Approve in the `production` environment
4. Subscriptions are processed in parallel (capped at 5 concurrent jobs)

---

## Documentation index

Per-layer references (each folder has its own README):

| Folder | Reference |
|---|---|
| `bootstrap/` | [Bootstrap reference][bootstrap-reference] |
| Selected engine | Read `terraform/README.md` or `bicep/README.md`, whichever exists in the vending repository |
| `landingzones/` | [`landingzones/README.md`](landingzones/README.md) — consumer reference for `sub.yaml` |
| `.github/` | [`.github/CICD.md`](.github/CICD.md) — CI/CD workflows, OIDC, Dependabot |
| `scripts/` | [`scripts/README.md`](scripts/README.md) — local helper scripts |

Topic-by-topic docs in `docs/`:

| Topic | Doc |
|---|---|
| ⭐ One-time operator setup | [`docs/onboarding.md`](docs/onboarding.md) |
| ⭐ Vend your first subscription | [`docs/first-vend.md`](docs/first-vend.md) |
| ⭐ Bootstrap wizard reference (create + destroy + local cleanup) | [`docs/bootstrap-wizard.md`](docs/bootstrap-wizard.md) |
| End-to-end architecture | [`docs/architecture.md`](docs/architecture.md) |
| Full directory tree + skeleton vs vending repo | [`docs/repository-layout.md`](docs/repository-layout.md) |
| Archetypes (`corp` / `online` / `sandbox` + add new) | [`docs/archetypes.md`](docs/archetypes.md) |
| Naming convention (files, aliases, RGs, VNets) | [`docs/naming-convention.md`](docs/naming-convention.md) |
| JSON Schema validation rules | [`docs/schema-validation.md`](docs/schema-validation.md) |
| Tag layering + cost-allocation tag | [`docs/tagging.md`](docs/tagging.md) |
| Billing scopes (EA / MCA / MPA + per-sub `billingScopeKey`) | [`docs/billing-scopes.md`](docs/billing-scopes.md) |
| Terraform backend container + per-sub state key | [`docs/state-storage.md`](docs/state-storage.md) |
| Retire a single vended subscription | [`docs/teardown.md`](docs/teardown.md) |
| Undo a botched bootstrap (different from above) | [`docs/bootstrap-wizard.md#destroying--undoing-a-bootstrap`](docs/bootstrap-wizard.md#destroying--undoing-a-bootstrap) |
| Every term defined in one place | [`docs/glossary.md`](docs/glossary.md) |
| Terraform and Bicep starter capability contract | [Starter contract][starter-contract] |
| Extended product vision and scope decisions | [Product vision][product-vision] |
| Historical delivery roadmap | [Delivery roadmap][delivery-roadmap] |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

[bootstrap-reference]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md
[starter-contract]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/starter-contract.md
[product-vision]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/proposals/subscription-vending-accelerator.md
[delivery-roadmap]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/proposals/subscription-vending-delivery-plan.md
