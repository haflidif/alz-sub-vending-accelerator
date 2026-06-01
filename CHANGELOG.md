# Changelog

All notable changes to the Azure Subscription Vending accelerator.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/). Versions track the accelerator
template itself, not the AVM module pinned by the engine (see
`terraform/main.tf` for the AVM module pin).

## [Unreleased]

## [0.1.0] - 2026-06-01

Initial public release — a GitHub **template** for Azure Subscription Vending
built on [`Azure/avm-ptn-alz-sub-vending/azure`](https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest),
with per-subscription Terraform state and YAML-driven subscription contracts.
GitHub Actions only — no Terragrunt.

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
