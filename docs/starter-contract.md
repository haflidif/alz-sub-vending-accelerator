# Starter contract

The accelerator supports multiple subscription-vending engines through a
versioned starter manifest. A starter is selectable only when it implements the
required operator capabilities in `starters/starter-contract.json`.

## Contract files

| Path | Purpose |
|---|---|
| `starters/starter-contract.json` | Contract version and required capabilities |
| `starters/starter.schema.json` | JSON Schema for starter manifests |
| `starters/<engine>/starter.json` | Engine availability, runtime model, and capability declaration |

## Required capabilities

The baseline covers the complete vending-machine experience rather than only
the infrastructure engine:

- Prerequisite checks, configuration validation, resumability, and destroy
- GitHub repository bootstrap, file seeding, branch protection, Actions,
  environments, and approval gates
- Azure managed identity and GitHub OIDC federation
- YAML subscription requests and schema validation
- Changed-request discovery and per-subscription isolation
- A reviewable deployment preview
- Governed deployment using the selected engine
- Billing, management-group placement, providers, tags, and budgets
- Role assignments, requested managed identities, and optional spoke networking

An `Available` starter must list every required capability as `implemented`.
Capabilities cannot appear in more than one of `implemented`, `planned`, or
`unsupported`.

For available starters, validation also checks that the declared bootstrap
entry point, engine directory, request directory, request schema, discovery
script, preview workflow, and deployment workflow exist inside the repository.
Paths cannot escape the repository root.

## Engine-specific behavior

The contract requires equivalent operator outcomes, not identical engine
mechanics.

| Concern | Terraform starter | Bicep starter |
|---|---|---|
| Preview | Terraform plan | ARM validation and what-if |
| Deployment | Terraform apply | Azure deployment |
| Isolation | Terraform state per subscription | Deployment identity and request tracking |
| Resource implementation | Terraform AVM pattern | Bicep AVM pattern |

The Bicep manifest remains `Planned` until all baseline capabilities are
implemented and verified. Unsupported input must produce an explicit error.

Starter manifests and the accelerator PowerShell module are development and
bootstrap assets. They are not copied into generated vending repositories.
