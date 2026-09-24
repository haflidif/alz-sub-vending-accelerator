# Repository layout

Two views of this codebase to keep straight:

1. **Skeleton repo** (this checkout) — the template you start from.
   Contains `bootstrap/`, sample `landingzones/<arch>/` YAMLs, the
   Terraform and Bicep engines, docs, CI workflows, PowerShell module, and starter
   manifests. An operator
   uses this (via "Use this template", or by cloning) to stand up a new
   vending repo.
2. **Vending repo** — the GitHub repository that `bootstrap/` creates
   (or configures) in your GitHub org. Contains everything
   the runtime skeleton ships. Accelerator development assets such as
   `bootstrap/`, `powershell/`, `starters/`, `tests/`, and proposals are
   excluded. The vending repo receives only the selected engine package and
   its rendered platform configuration, plus a generated
   `.github/CODEOWNERS`. This is where day-to-day vending happens.

For a green-field tenant you also need an MG hierarchy and a platform
subscription before running `bootstrap/`. The Terraform starter additionally
needs a state storage account. Create those by any means for POC/test use; if
you already have an Azure Landing Zone, they usually exist already.

<a name="full-directory-tree-skeleton"></a>

## Directory tree (accelerator source)

This is the canonical documentation tree. Parenthesized configuration files
are rendered into the generated repository, not committed to the source.

```
subscription-vending/
├── .editorconfig
├── .gitignore                       # Terraform/IDE/secret/sidecar exclusions
├── accelerator.json                 # Release identity and source repository
├── CHANGELOG.md                     # Skeleton release notes
├── CODEOWNERS                       # Upstream accelerator owners (not seeded)
├── CONTRIBUTING.md                  # How to vend / modify archetypes / bump AVM
├── LICENSE
├── QUICKSTART.md                    # Short operator journey
├── README.md                        # ⭐ Top-level entry point — start here
├── SECURITY.md                      # Source-only security policy
├── SUPPORT.md                       # Source-only support guide
├── upgrade-manifest.json            # Managed-file ownership for upgrades
│
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md     # PR description scaffold
│   ├── CICD.md                      # ★ CI/CD reference (workflows + scripts)
│   ├── dependabot.yml               # Weekly/monthly dependency updates
│   ├── scripts/
│   │   └── discover-subs.sh         # Matrix builder consumed by both workflows
│   └── workflows/
│       ├── apply.yml                # Push to main + dispatch → selected engine deploy
│       └── pr-validate.yml          # PR → schema + contract + engine preview
│
├── powershell/                      # Accelerator bootstrap interface
│   └── SubscriptionVending/
│       ├── SubscriptionVending.psd1 # Module manifest
│       ├── SubscriptionVending.psm1 # Engine discovery + bootstrap commands
│       └── README.md                # Module usage
│
├── starters/                        # Engine contract and declarations
│   ├── starter-contract.json        # Required capabilities
│   ├── starter.schema.json          # Starter manifest schema
│   ├── terraform/starter.json       # Available Terraform starter
│   └── bicep/starter.json           # Available Bicep starter
│
├── bootstrap/                       # ★ Skeleton-only. Operator runs ONCE.
│   ├── Invoke-Bootstrap.ps1         # Shared bootstrap implementation
│   ├── README.md                    # Bootstrap module reference
│   ├── terraform.tf                 # Provider versions for the bootstrap layer
│   ├── locals.tf                    # Billing-scope path string resolution
│   ├── variables.tf                 # ~20 operator inputs (validated)
│   ├── main.tf                      # UAMI + 3 FICs + RBAC + container + GitHub
│   ├── migrations.tf                # Bootstrap state-address migrations
│   ├── files.tf                     # Skeleton seeder + auto.tfvars renderer + CODEOWNERS
│   ├── outputs.tf                   # UAMI principal_id, billing-role reminder
│   ├── terraform.tfvars.example     # Schema-correct example — copy + edit (or use wizard)
│   └── templates/
│       └── CODEOWNERS.tftpl         # Rendered into the seeded repo
│
├── terraform/                       # ★ The vending engine. ONE folder, no submodules.
│   ├── README.md                    # File-by-file engine reference
│   ├── versions.tf                  # Terraform + provider versions
│   ├── providers.tf                 # azurerm (platform-pinned) + azapi
│   ├── backend.tf                   # Partial azurerm backend (key set per-sub)
│   ├── variables.tf                 # Platform inputs (tenant, billing, MGs, tags)
│   ├── archetypes.tf                # Declarative archetype defaults + guardrails
│   ├── locals.tf                    # Parses sub.yaml + computes module inputs
│   ├── main.tf                      # ONE call to Azure/avm-ptn-alz-sub-vending/azure
│   ├── outputs.tf                   # Subscription ID + effective tags
│   └── (terraform.auto.tfvars)      # Rendered by bootstrap, only in vending repo
│
├── bicep/                           # ★ Bicep vending engine
│   ├── README.md                    # Bicep reference
│   ├── main.bicep                   # Pinned AVM wrapper
│   ├── SubscriptionVending.Bicep.psm1 # YAML request compiler
│   ├── modules/                     # Budget deployment helpers
│   ├── default-resource-providers.json
│   ├── platform.schema.json
│   ├── platform.example.json
│   └── (platform.json)              # Rendered by bootstrap, only in vending repo
│
├── landingzones/                    # ★ One file = one subscription
│   ├── README.md                    # Consumer-facing reference
│   ├── sub.schema.json              # JSON Schema for sub.yaml validation
│   ├── corp/
│   │   └── prod-corp-erp-001.yaml
│   ├── online/
│   │   └── prod-online-web-001.yaml
│   └── sandbox/
│       └── dev-sandbox-platform-001.yaml
│
├── docs/
│   ├── README.md                    # Audience routes and reference catalog
│   ├── operators/
│   │   ├── planning.md              # Decisions before setup
│   │   ├── prerequisites.md         # Tools, resources, permissions
│   │   ├── bootstrap.md             # Initial setup and repository handoff
│   │   ├── run.md                   # First run and service operation
│   │   ├── upgrade.md               # Versioned managed-file upgrades
│   │   └── retire-subscription.md   # Advanced operator lifecycle guidance
│   ├── consumers/
│   │   └── first-subscription.md    # YAML-and-PR walkthrough
│   ├── proposals/                  # Source-only design material
│   │   ├── README.md                # Proposal status index
│   │   ├── subscription-vending-accelerator.md
│   │   └── subscription-vending-delivery-plan.md
│   ├── architecture.md              # End-to-end design
│   ├── archetypes.md                # corp / online / sandbox + add new
│   ├── billing-scopes.md            # EA / MCA / MPA paths and engine configuration
│   ├── bootstrap-wizard.md          # Invoke-Bootstrap.ps1 full reference
│   ├── first-vend.md                # Legacy URL and section compatibility
│   ├── glossary.md                  # Every term defined
│   ├── naming-convention.md         # Filename + alias + RG / VNet naming
│   ├── onboarding.md                # Legacy URL and section compatibility
│   ├── repository-layout.md         # ← you are here
│   ├── schema-validation.md         # What the schema enforces + where
│   ├── starter-contract.md          # Terraform/Bicep capability baseline
│   ├── state-storage.md             # Backend container + per-sub key
│   ├── tagging.md                   # CAF tag baseline + cost-allocation tag
│   └── teardown.md                  # Legacy URL and section compatibility
│
├── scripts/
│   ├── README.md                    # Local-helper scripts reference
│   ├── Update-SubscriptionVending.ps1 # Tagged generated-repository upgrades
│   ├── Grant-SubscriptionCreatorRole.ps1 # Approval-gated billing role helper
│   └── Reset-LocalState.ps1         # Wipe local operator state
│
└── tests/
    ├── PowerShell/
    │   ├── SubscriptionVending.Tests.ps1
    │   ├── BillingRole.Tests.ps1
    │   └── BicepStarter.Tests.ps1
    └── scripts/
        └── discover-subs.Tests.sh
```

The generated repository also receives `.accelerator/metadata.json`, rendered
by bootstrap with its selected starter, accelerator version, and managed-file
hashes. The file is updated only when a versioned upgrade changes managed
content.

⭐ = start here for each persona.
★ = aggregated reference index.

## What changes between skeleton and vending repo

| Path | Skeleton | Vending repo |
|---|---|---|
| `bootstrap/` | Present (operator runs it locally) | **Excluded** by `bootstrap/files.tf` from the seed |
| `powershell/`, `starters/`, `tests/` | Accelerator development and bootstrap assets | **Excluded** |
| `docs/proposals/` | Extended and historical design, including its index | **Excluded** |
| `docs/starter-contract.md` | Implemented contributor contract | **Excluded** |
| `SECURITY.md`, `SUPPORT.md`, root `CODEOWNERS` | Accelerator policies and owners | **Excluded** |
| `docs/README.md`, `docs/operators/`, `docs/consumers/`, legacy compatibility pages | Shared operating documentation | **Included** |
| Selected engine configuration | Absent (`terraform/terraform.auto.tfvars` or `bicep/platform.json`) | **Rendered by `bootstrap/files.tf`** with platform context |
| Unselected engine package | Present in the accelerator skeleton | **Excluded** |
| `.github/CODEOWNERS` | Absent | **Rendered from `bootstrap/templates/CODEOWNERS.tftpl`** with operator-chosen teams |
| Runtime files (`terraform/`, `landingzones/`, operator docs, `scripts/`, `.github/`, `README.md`, etc.) | Source of truth | Verbatim copy via `github_repository_file` |

`bootstrap/files.tf` enforces these exclusions via
`skeleton_excluded_prefixes` (`bootstrap/`, `powershell/`, `starters/`,
`tests/`, `docs/proposals/`, `.git/`, `.terraform/`, `.vs/`, `.vscode/`,
`.devcontainer/`) and `skeleton_excluded_regexes`
(state files, plans, `.env`, `.DS_Store`, stray shell artefacts).

Shared documentation uses relative links for shipped pages and explicit
accelerator-source links for excluded files, including proposals and the
unselected engine. Bootstrap pages explain which commands require the source
checkout. Existing vending repositories receive documentation updates through
reviewed PRs, not another bootstrap apply.

## Where to make a change

| You want to… | Edit here | Then… |
|---|---|---|
| Vend a new subscription | `landingzones/<arch>/<sub>.yaml` (in the **vending repo**) | Open a PR |
| Modify archetype defaults | Terraform: `terraform/archetypes.tf`; Bicep: `bicep/SubscriptionVending.Bicep.psm1` | PR previews all requests; after merge, explicitly run Apply with `mode=all` |
| Add a new archetype | Engine rules + `landingzones/<arch>/` + schema enum + selected engine configuration | See [`docs/archetypes.md`](archetypes.md) |
| Rotate platform inputs | `terraform/terraform.auto.tfvars` or `bicep/platform.json` in the vending repo | PR previews all requests; after merge, explicitly run Apply with `mode=all` if existing subscriptions need the new values |
| Add a new optional YAML field | Schema + both engine adapters + engine docs + tests | New PR to the accelerator, then propagate via PR to existing vending repos |
| Bump the AVM module version | `terraform/main.tf` or `bicep/main.bicep` | PR previews all requests; test and explicitly deploy with `mode=all` in a non-production tenant first |
| Bump GitHub Actions / Terraform provider versions | Wait for Dependabot, or edit `terraform/versions.tf` / `.github/workflows/*.yml` / `bootstrap/terraform.tf` | See [`.github/CICD.md → Dependabot cadence`](../.github/CICD.md#dependabot-cadence) |
| Tune CI behaviour (branch protection, required reviewers, env name) | `bootstrap/variables.tf` defaults — but only matters for the next bootstrap. For an existing vending repo, edit directly in GitHub Settings or via `github_branch_protection` / `github_repository_environment` in your own day-2 IaC. | See [`.github/CICD.md → Required status checks`](../.github/CICD.md#required-status-checks) |
| Skeleton iteration (this repo) | Anywhere | Verify in a throwaway tenant; ship via PR to the vending repo |
| Start a new vending repo | Use the accelerator source checkout | Follow [Planning](operators/planning.md), Prerequisites, Bootstrap, and Run |

## See also

- [`README.md`](../README.md) — top-level entry point
- [Documentation index](README.md)
- [Planning](operators/planning.md), [Prerequisites](operators/prerequisites.md), [Bootstrap](operators/bootstrap.md), [Run](operators/run.md), and [Upgrade](operators/upgrade.md)
- [Consumer walkthrough](consumers/first-subscription.md) for requesting a subscription
- [`docs/architecture.md`](architecture.md) — design rationale
- [`docs/glossary.md`](glossary.md) — terminology
