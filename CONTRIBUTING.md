# Contributing

## Contributing to the upstream accelerator

> This section applies to contributions to the **accelerator project itself**
> (the open-source `alz-sub-vending-terraform-accelerator`). If you are an
> operator running a vended copy, skip to the operational sections below.

This project welcomes contributions and suggestions. Most contributions require
you to agree to a Contributor License Agreement (CLA) declaring that you have the
right to, and actually do, grant us the rights to use your contribution. For
details, visit [https://cla.opensource.microsoft.com](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you
need to provide a CLA and decorate the PR appropriately (e.g., status check,
comment). Simply follow the instructions provided by the bot. You will only need to
do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the
[Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact
[opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions
or comments. Security issues are handled per the accelerator's security policy
(`SECURITY.md`); for support options see the accelerator's support guide (`SUPPORT.md`).

## Vending a new subscription

1. **Pick an archetype** (`corp`, `online`, `sandbox`).
   See [`docs/archetypes.md`](docs/archetypes.md).
2. **Create a YAML file** under `landingzones/<archetype>/` named per the
   [naming convention](docs/naming-convention.md), e.g.
   `landingzones/corp/prod-corp-erp-001.yaml`.
3. **Author the contract** — this is the only file you need. The schema is
   documented in [`docs/architecture.md`](docs/architecture.md#sub-yaml-schema).
   Required fields: `archetype`, `location`, `owner`.
4. **Open a PR.** CI will:
   - Detect that you changed `landingzones/<archetype>/<your-sub>.yaml`
   - Run `terraform fmt -check` and `terraform validate`
   - Run `terraform plan` against your new sub only
   - Post the plan as a PR comment
5. **Approval** required from:
   - Archetype CODEOWNER (platform team)
   - Subscription owner listed in the YAML
6. **Merge to `main`** triggers the `Apply` workflow. After approval in the
   `production` GitHub Environment, your sub is applied.

## Modifying an archetype default

Changes to `terraform/archetypes.tf` affect **every existing subscription** in
that archetype on next apply. Treat with care:

1. Open an RFC issue describing the change and the blast radius.
2. PR must include the output of the `Apply` workflow run with `mode=all`
   in a non-prod tenant (or an attached plan from `terraform plan` for at least
   one representative sub per affected archetype).
3. Requires sign-off from the platform lead.

## Bumping the AVM module version

The version pin lives in [`terraform/main.tf`](terraform/main.tf):

```hcl
module "subscription" {
  source  = "Azure/avm-ptn-alz-sub-vending/azure"
  version = "0.2.1"
  ...
}
```

The pin is **exact** (not pessimistic) — every AVM module bump is
explicit and reviewed, because the AVM module's input contract is still
pre-1.0 and minor versions sometimes change schema.

Process:
1. Read the upstream changelog and its README diff.
2. Update the `version` string to the new exact pin.
3. Open a PR — CI will plan against changed subs.
4. After merge, run `Apply` with `mode=all` to roll out across every sub.

## Code style

- Terraform: `terraform fmt -recursive` (CI enforces).
- YAML: 2-space indent, keys in `lowerCamelCase`.
- PowerShell helpers: PascalCase function names, `[CmdletBinding()]`,
  `$ErrorActionPreference = 'Stop'`.

## Commit messages

Conventional Commits:

- `feat(corp): vend prod-corp-erp-001`
- `fix(online): correct address space for prod-online-web-001`
- `chore(archetypes): bump AVM module to 0.3.0`
- `docs(onboarding): clarify MCA invoice section lookup`

## Tests / pre-commit

There is no test suite — the system's correctness is enforced by:

- `terraform validate` (CI)
- `terraform fmt -check` (CI)
- `terraform plan` per changed sub (CI; review in the PR comment)
- Required reviews via CODEOWNERS
- Required environment approval for `apply.yml`

If you want a local pre-commit hook, the simplest is:

```powershell
# .git/hooks/pre-commit (PowerShell)
terraform -chdir=terraform fmt -check -recursive
```
