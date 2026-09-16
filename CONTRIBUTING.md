# Contributing

## Contributing to the upstream accelerator

> This section applies to contributions to the **accelerator project itself**
> (the open-source `alz-sub-vending-terraform-accelerator`). If you are an
> operator running a copy created from this template, skip to the operational
> sections below.

Contributions and suggestions are welcome. By submitting a pull request you
certify that you wrote the contribution, or otherwise have the right to submit
it under the project's [MIT License](LICENSE) (the
[Developer Certificate of Origin](https://developercertificate.org/) is a good
summary of this expectation).

Please be respectful and constructive in issues and pull requests. Security
issues are handled per the project's security policy (`SECURITY.md`); for
support options see the support guide (`SUPPORT.md`).

## Vending a new subscription

1. **Pick an archetype** (`corp`, `online`, `sandbox`).
   See [`docs/archetypes.md`](docs/archetypes.md).
2. **Create a YAML file** under `landingzones/<archetype>/` named per the
   [naming convention](docs/naming-convention.md), e.g.
   `landingzones/corp/prod-corp-erp-001.yaml`.
3. **Author the contract.** This is the only file you need. The schema is
   documented in [`docs/architecture.md`](docs/architecture.md#sub-yaml-schema).
   Required fields: `archetype`, `location`, `owner`.
4. **Open a PR.** CI will:
   - Detect that you changed `landingzones/<archetype>/<your-sub>.yaml`
   - Validate the shared YAML schema
   - Run Terraform plan or Bicep validate and what-if for your request
   - Post the engine preview as a PR comment
5. **Review** requires the archetype CODEOWNER. Follow your organization's
   process for confirming the request with the subscription owner listed in
   the YAML.
6. **Merge to `main`** triggers the `Apply` workflow. After approval in the
   `production` GitHub Environment, your sub is applied.

## Modifying an archetype default

Archetype rules live in `terraform/archetypes.tf` and the `$archetypes` map in
`bicep/SubscriptionVending.Bicep.psm1`. Change the adapter for the engine you
support. Treat the change as repository-wide because runtime engine changes
select every existing request:

1. Open an RFC issue describing the change and the blast radius.
2. Include a `mode=all` result from a non-production tenant, or attach
   Terraform plan or Bicep what-if output for representative requests.
3. Requires sign-off from the platform lead.

## Bumping an AVM module version

Each engine has an exact AVM pin:

```hcl
module "subscription" {
  source  = "Azure/avm-ptn-alz-sub-vending/azure"
  version = "0.3.1"
  ...
}
```

```bicep
module subscription 'br/public:avm/ptn/lz/sub-vending:0.8.0' = {
  // ...
}
```

The Terraform pin lives in `terraform/main.tf`. The Bicep pin lives in
`bicep/main.bicep`. Both are exact
because the upstream input contracts are pre-1.0 and can change between minor
versions.

Process:
1. Read the upstream changelog and its README diff.
2. Update one engine pin.
3. Update that engine's adapter and tests for any contract changes.
4. Open a PR. CI selects every subscription for the changed engine.
5. After merge, run `Apply` with `mode=all` to roll out across every sub.

## Code style

- Terraform: `terraform fmt -recursive` (CI enforces).
- Bicep: `az bicep build --file bicep/main.bicep`.
- YAML: 2-space indent, keys in `lowerCamelCase`.
- PowerShell helpers: PascalCase function names, `[CmdletBinding()]`,
  `$ErrorActionPreference = 'Stop'`.

## Commit messages

Conventional Commits:

- `feat(corp): vend prod-corp-erp-001`
- `fix(online): correct address space for prod-online-web-001`
- `chore(archetypes): bump AVM module to 0.3.1`
- `chore(bicep): bump sub-vending AVM to 0.9.0`
- `docs(onboarding): clarify MCA invoice section lookup`

## Tests / pre-commit

Run the smallest relevant checks before you open a PR:

- `tests/PowerShell/SubscriptionVending.Tests.ps1`
- `tests/PowerShell/BicepStarter.Tests.ps1`
- `tests/scripts/discover-subs.Tests.sh`
- JSON Schema validation for subscription requests and Bicep platform config
- `terraform fmt -check` and `terraform validate`
- `az bicep build --file bicep/main.bicep`
- Terraform plan or Bicep what-if per changed request in CI
- Required reviews via CODEOWNERS
- Required environment approval for `apply.yml`

If you want a local pre-commit hook, the simplest is:

```powershell
# .git/hooks/pre-commit (PowerShell)
terraform -chdir=terraform fmt -check -recursive
az bicep build --file bicep/main.bicep
pwsh -File tests/PowerShell/SubscriptionVending.Tests.ps1
pwsh -File tests/PowerShell/BicepStarter.Tests.ps1
```
