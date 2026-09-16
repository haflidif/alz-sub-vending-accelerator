# Repository layout

Two views of this codebase to keep straight:

1. **Skeleton repo** (this checkout) — the template you start from.
   Contains `bootstrap/`, sample `landingzones/<arch>/` YAMLs, the
   Terraform engine, docs, CI workflows, PowerShell module, and starter
   manifests. An operator
   uses this (via "Use this template", or by cloning) to stand up a new
   vending repo.
2. **Vending repo** — the GitHub repository that `bootstrap/` creates
   (or configures) in your GitHub org. Contains everything
   the runtime skeleton ships. Accelerator development assets such as
   `bootstrap/`, `powershell/`, `starters/`, `tests/`, and proposals are
   excluded. The vending repo also receives a rendered
   `terraform/terraform.auto.tfvars` carrying platform context, plus
   a generated `.github/CODEOWNERS`. This is where day-to-day vending
   happens.

For a green-field tenant you also need an MG hierarchy, a platform
subscription, and a state storage account in place before running
`bootstrap/`. Create those by any means for POC/test use; if you already
have an Azure Landing Zone, they exist already.

## Full directory tree (skeleton)

```
subscription-vending/
├── .editorconfig
├── .gitignore                       # Terraform/IDE/secret/sidecar exclusions
├── CHANGELOG.md                     # Skeleton release notes
├── CONTRIBUTING.md                  # How to vend / modify archetypes / bump AVM
├── LICENSE
├── README.md                        # ⭐ Top-level entry point — start here
│
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md     # PR description scaffold
│   ├── README.md                    # ★ CI/CD reference (workflows + scripts)
│   ├── dependabot.yml               # Weekly/monthly dependency updates
│   ├── scripts/
│   │   └── discover-subs.sh         # Matrix builder consumed by both workflows
│   └── workflows/
│       ├── apply.yml                # Push to main + dispatch → terraform apply
│       └── pr-validate.yml          # PR → schema validate + fmt + plan
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
│   └── bicep/starter.json           # Planned Bicep starter
│
├── bootstrap/                       # ★ Skeleton-only. Operator runs ONCE.
│   ├── Invoke-Bootstrap.ps1         # Terraform compatibility implementation
│   ├── README.md                    # Bootstrap module reference
│   ├── terraform.tf                 # Provider versions for the bootstrap layer
│   ├── locals.tf                    # Billing-scope path string resolution
│   ├── variables.tf                 # ~20 operator inputs (validated)
│   ├── main.tf                      # UAMI + 3 FICs + RBAC + container + GitHub
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
├── docs/                            # ★ Topic-by-topic reference
│   ├── architecture.md              # End-to-end design
│   ├── archetypes.md                # corp / online / sandbox + add new
│   ├── billing-scopes.md            # EA / MCA / MPA path formats + billing_scopes map
│   ├── bootstrap-wizard.md          # Invoke-Bootstrap.ps1 full reference
│   ├── first-vend.md                # ⭐ Vend your first subscription (consumer)
│   ├── glossary.md                  # Every term defined
│   ├── naming-convention.md         # Filename + alias + RG / VNet naming
│   ├── onboarding.md                # ⭐ One-time operator setup
│   ├── repository-layout.md         # ← you are here
│   ├── schema-validation.md         # What the schema enforces + where
│   ├── starter-contract.md          # Terraform/Bicep capability baseline
│   ├── state-storage.md             # Backend container + per-sub key
│   ├── tagging.md                   # CAF tag baseline + cost-allocation tag
│   └── teardown.md                  # Retire a vended subscription
│
├── scripts/
│   ├── README.md                    # Local-helper scripts reference
│   └── Reset-LocalState.ps1         # Wipe local operator state
│
└── tests/
    └── PowerShell/
        └── SubscriptionVending.Tests.ps1
```

⭐ = start here for each persona.
★ = aggregated reference index.

## What changes between skeleton and vending repo

| Path | Skeleton | Vending repo |
|---|---|---|
| `bootstrap/` | Present (operator runs it locally) | **Excluded** by `bootstrap/files.tf` from the seed |
| `powershell/`, `starters/`, `tests/` | Accelerator development and bootstrap assets | **Excluded** |
| `docs/proposals/`, `docs/starter-contract.md` | Accelerator design material | **Excluded** |
| `terraform/terraform.auto.tfvars` | Absent (gitignored) | **Rendered by `bootstrap/files.tf`** with platform context |
| `.github/CODEOWNERS` | Absent | **Rendered from `bootstrap/templates/CODEOWNERS.tftpl`** with operator-chosen teams |
| Runtime files (`terraform/`, `landingzones/`, operator docs, `scripts/`, `.github/`, `README.md`, etc.) | Source of truth | Verbatim copy via `github_repository_file` |

`bootstrap/files.tf` enforces these exclusions via
`skeleton_excluded_prefixes` (`bootstrap/`, `powershell/`, `starters/`,
`tests/`, `docs/proposals/`, `.git/`, `.terraform/`, `.vs/`, `.vscode/`,
`.devcontainer/`) and `skeleton_excluded_regexes`
(state files, plans, `.env`, `.DS_Store`, stray shell artefacts).

## Where to make a change

| You want to… | Edit here | Then… |
|---|---|---|
| Vend a new subscription | `landingzones/<arch>/<sub>.yaml` (in the **vending repo**) | Open a PR |
| Modify an archetype's defaults | `terraform/archetypes.tf` (in the **vending repo**) | PR + plan + apply with `mode=all` |
| Add a new archetype | `terraform/archetypes.tf` + `landingzones/<arch>/` + `landingzones/sub.schema.json` (enum) + `terraform/terraform.auto.tfvars` (`management_group_ids`) — all in the **vending repo** | See [`docs/archetypes.md`](archetypes.md) |
| Rotate platform inputs (tenant, billing scopes, MG IDs, hub VNet, tags, cost-allocation tag) | `terraform/terraform.auto.tfvars` (in the **vending repo**) | PR + apply with `mode=all` if existing subs need to pick up the new values |
| Add a new optional YAML field | `landingzones/sub.schema.json` + `terraform/locals.tf` + `terraform/README.md` + `docs/schema-validation.md` (in the **skeleton**) | New PR to the skeleton, then propagate via PR to existing vending repos |
| Bump the AVM module version | `terraform/main.tf` (in the **skeleton**, then propagate) | Test with `mode=all` in a non-prod tenant first |
| Bump GitHub Actions / Terraform provider versions | Wait for Dependabot, or edit `terraform/versions.tf` / `.github/workflows/*.yml` / `bootstrap/terraform.tf` | See [`.github/CICD.md → Dependabot cadence`](../.github/CICD.md#dependabot-cadence) |
| Tune CI behaviour (branch protection, required reviewers, env name) | `bootstrap/variables.tf` defaults — but only matters for the next bootstrap. For an existing vending repo, edit directly in GitHub Settings or via `github_branch_protection` / `github_repository_environment` in your own day-2 IaC. | See [`.github/CICD.md → Required status checks`](../.github/CICD.md#required-status-checks) |
| Skeleton iteration (this repo) | Anywhere | Verify in a throwaway tenant; ship via PR to the vending repo |
| Start a new vending repo | Use this template (or run `bootstrap/`) | See [`docs/onboarding.md`](onboarding.md) |

## See also

- [`README.md`](../README.md) — top-level entry point
- [`docs/onboarding.md`](onboarding.md) — operator setup
- [`docs/first-vend.md`](first-vend.md) — vend a subscription
- [`docs/architecture.md`](architecture.md) — design rationale
- [`docs/glossary.md`](glossary.md) — terminology
