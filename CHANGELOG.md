# Changelog

All notable changes to the Azure Subscription Vending accelerator.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/). Versions track the accelerator
template itself, not the AVM modules pinned by the engines. See
`terraform/main.tf` and `bicep/main.bicep`.

## [Unreleased]

### Added

- Bootstrap warnings for production environments with no eligible reviewers,
  one-person approval deadlocks, or reviewer teams whose membership cannot be
  verified. One-person setups now receive guidance for GitHub's audited
  administrator bypass while self-review prevention remains enabled.
- Visible Bicep deployment progress with periodic Azure provisioning-state
  updates instead of a silent long-running CLI command.
- Terraform and Bicep apply summaries containing the final subscription ID,
  deployment status, and engine-specific operational outputs.
- Bicep deployment response artifacts for successful and failed runs.
- `SubscriptionVending` PowerShell module as the accelerator entry point, with
  engine discovery, Terraform bootstrap orchestration, configuration
  validation, and starter contract validation.
- Versioned Terraform and Bicep starter manifests with a shared baseline of 26
  required vending-machine capabilities.
- Starter manifest JSON Schema and tests that prevent an engine from becoming
  available while required capabilities remain planned or unsupported.
- Product direction and delivery proposal documents for the dual-engine
  accelerator.
- Accelerator CI checks for the PowerShell module, starter manifests,
  discovery behavior, and bootstrap Terraform configuration.
- Engine package roots and manifest-driven starter package declarations.
- Initial Bicep runtime package with an Azure Verified Modules sub-vending
  wrapper, platform schema, and deterministic request compiler.
- Bicep subnet normalization for service endpoints, delegation, private
  endpoint policies, outbound settings, IPAM allocations, and custom network
  security groups.
- Bicep role-assignment normalization for resource-group scope, principal
  type, description, and supported conditional assignment templates.

### Changed

- Clarified that bootstrap is resumable only until the initial repository
  handoff completes. Generated repositories own their source files afterward,
  and future starter upgrades are delivered separately from bootstrap.
- Updated the bootstrap AzureRM provider to `5.6.0` after validating the
  bootstrap configuration and provider schema with the new version.
- Updated the Terraform subscription-vending AVM module to `0.3.2` and AzAPI
  to `2.12.0`. Accelerator CI now initializes and validates the runtime
  Terraform dependency graph so incompatible transitive constraints fail
  before merge.
- Made the PowerShell module the preferred bootstrap interface while retaining
  `bootstrap/Invoke-Bootstrap.ps1` as the current Terraform implementation.
- Excluded accelerator development assets, tests, starter metadata, and
  proposals from generated vending repositories.
- Updated bootstrap and repository documentation for the module and starter
  contract.
- Updated GitHub Actions checkout from version 6 to 7.
- Updated bootstrap providers to AzureRM 5.0.0, AzureAD 3.9.0, and GitHub
  6.13.0.
- Updated the Terraform subscription-vending AVM module from 0.2.1 to 0.3.1.
- Relaxed Terraform Core constraints to `>= 1.10.0, < 2.0.0`, matching the
  minimum required by the Terraform subscription-vending AVM module while
  allowing newer Terraform 1.x releases.
- Kept GitHub Actions pinned to Terraform 1.15.5 for reproducible CI runs
  without imposing that exact version on operators.
- Prevented the accelerator source repository from running sample subscription
  previews or applies while preserving those jobs in generated vending
  repositories.
- Made repository seeding select common runtime files plus only the package
  declared by the selected starter. Terraform selection preserves the version
  0.1 generated repository contents.
- Forwarded engine selection through the PowerShell module and legacy
  bootstrap, persisted `starter_name`, and exposed it as a Terraform output.
- Updated operator, architecture, CI/CD, tagging, billing, schema, repository,
  and teardown documentation for the available Terraform and Bicep engines.
- Completed a repository-wide documentation audit, corrected remaining
  Terraform-only wording in shared guidance, and clearly labeled
  engine-specific state and bootstrap instructions.

### Fixed

- Preserved single production reviewer IDs as arrays in rendered bootstrap
  inputs.
- Kept mutable bootstrap input state attached across typed PowerShell function
  boundaries.
- Isolated the legacy bootstrap script from the module's strict-mode scope.
- Included the underlying Azure CLI error when bootstrap preflight cannot read
  the active account.
- Ignored the extensionless `tfplan` artifact written by the bootstrap wizard.
- Made Bicep management-group deployment names stable per subscription so AVM
  deployment-script support resources remain idempotent across workflow runs.
- Made Bicep PR validation and what-if use the same deployment name as apply so
  previews evaluate the resource identities that apply will use.
- Stopped Bicep bootstraps from requiring or creating Terraform runtime state
  storage, blob RBAC, or backend GitHub variables.
- Fixed bootstrap plan-file argument handling so Terraform writes and applies
  the intended `tfplan` file on PowerShell 7.
- Stabilized repository seeding so local bootstrap state created during apply
  cannot change the package file set.
- Granted production reviewer teams repository access before configuring the
  GitHub environment protection rule.
- Rendered CODEOWNERS for only the runtime engine included in the generated
  repository.
- Excluded the local compiled `bicep/main.json` build artifact from generated
  repositories.
- Added support for GitHub immutable OIDC subjects containing numeric owner
  and repository IDs.
- Made the generated repository description identify the selected runtime
  engine instead of referring only to Terraform.
- Replaced `Management Group Contributor` with `Contributor` at the ALZ root
  management group so the pipeline can validate and run Bicep deployments.
- Made Bicep platform configuration and default resource-provider changes
  select every subscription in PR validation and apply workflows.
- Added discovery regression coverage for Bicep platform-wide files and
  invalid `VENDING_ENGINE` values.
- Propagated legacy bootstrap exit codes through the PowerShell module.
- Removed unsafe `-WhatIf` behavior from module initialization and reject it in
  legacy bootstrap mode. `-PlanOnly` remains the supported preview path.
- Validated starter contract versions and required file and directory paths.
- Made shared changes under `terraform/` select every subscription for preview
  and deployment.
- Made discovery failures and cancellations fail the final PR validation gate.
- Rejected attempts to change the starter bound to an existing bootstrap
  sidecar.
- Added CI validation for the Bicep template, platform configuration example,
  and request compiler.
- Made subscription discovery and shared GitHub Actions route preview and
  deployment through the repository's selected engine.
- Added bootstrap rendering for Bicep platform configuration and engine
  metadata repository variables.
- Added a non-creating existing-subscription input to the Bicep wrapper for
  cloud validation and future adoption scenarios.
- Avoided passing an invalid empty virtual-network name to the upstream Bicep
  AVM when networking is disabled.
- Normalized full management-group resource IDs to the bare identifier
  required by the Bicep AVM association implementation.
- Made Bicep resource-provider registration configurable after cloud what-if
  confirmed the AVM default deployment-script support footprint.
- Completed non-creating management-group validation and what-if against an
  existing subscription in an ALZ hierarchy.
- Added a Bicep subscription budget module that preserves separate actual and
  forecast notification thresholds in one budget resource.
- Rejected subnet and role-assignment properties that the pinned Bicep AVM
  cannot preserve instead of silently discarding them.
- Rejected multiple subnet prefixes because the Bicep AVM 0.8.0 sub-vending
  wrapper declares but does not forward them to its VNet module.
- Completed non-creating networking and RBAC validation and what-if against an
  existing subscription, including hub peering and a custom NSG rule.
- Preserved a single budget contact as an array in generated Bicep parameters
  so owner-only budget requests pass ARM template validation.
- Defaulted Bicep spoke peerings to not use remote gateways, with an explicit
  platform opt-in for hubs configured with gateway transit.
- Made the Bicep starter available after real Azure verification of
  subscription creation, management-group placement, tags, budgets,
  networking, hub peering, and role assignments.

## [0.1.0] - 2026-06-01

A GitHub **template** for Azure Subscription Vending
built on [`Azure/avm-ptn-alz-sub-vending/azure`](https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest),
with per-subscription Terraform state and YAML-driven subscription contracts.

### Vending engine (`terraform/`)
- Single-folder Terraform engine (no submodules) that vends one subscription
  per run via one call to the AVM ALZ sub-vending module.
- **YAML-driven contracts** — one `landingzones/<archetype>/<sub>.yaml` file per
  subscription, validated against `landingzones/sub.schema.json`.
- **Archetype guardrails** — `corp`, `online`, and `sandbox` archetypes with
  declarative defaults and constraints in `terraform/archetypes.tf`.
- **Per-subscription state isolation** — each subscription gets its own state
  blob (`<archetype>/<sub-name>.tfstate`) so one change can't churn unrelated
  subscriptions.
- **Tag layering + cost allocation** — CAF tag baseline plus an
  operator-configurable cost-allocation tag (optional, with plan-time pattern
  validation).

### Bootstrap (`bootstrap/`)
- One-time, interactive PowerShell wizard (`Invoke-Bootstrap.ps1`) that
  provisions the pipeline managed identity, GitHub OIDC federation, MG-scoped
  RBAC, the state container, and a new vending repository with branch
  protection and a `production` environment.
- Seeds the vending repository with everything except `bootstrap/`, and renders
  `terraform/terraform.auto.tfvars` (tenant / billing / MGs / hub / tags) and a
  `.github/CODEOWNERS`.
- **Destroy mode** (`-Destroy`) to cleanly undo a bootstrap.

### CI/CD (`.github/`)
- `pr-validate.yml` — `terraform fmt -check`, `validate`, schema validation, and
  `terraform plan` for changed subscriptions, posted as a PR comment.
- `apply.yml` — `terraform apply` on merge to `main` after `production`
  environment approval; supports `changed`, `single`, and `all` modes.
- OIDC-based auth (no stored secrets); weekly Dependabot for Actions and
  Terraform providers.

### Tooling
- `scripts/Reset-LocalState.ps1` — wipes local operator state (tfvars, state,
  caches) from the working tree.

### Conventions
- **All Terraform and provider versions pinned exactly** (no `~>`), to the
  latest stable releases as of 2026-06-01: `terraform 1.15.5`, `azurerm 4.74.0`,
  `azapi 2.10.0`, `random 3.9.0`, `azuread 3.8.0`, `github 6.12.1`, AVM module
  `0.2.1`; CI `check-jsonschema 0.37.2`.

### Documentation
- Quick start (`QUICKSTART.md`), end-to-end architecture, onboarding,
  archetypes, billing scopes, tagging, naming convention, schema validation,
  state storage, teardown, and a glossary under `docs/`.

[Unreleased]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/releases/tag/v0.1.0
