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
issues follow the [security policy][security]; for support options see the
[support guide][support]. These links open the accelerator source because
the policies are not copied into generated vending repositories.

## Vending a new subscription

Use the [consumer walkthrough](docs/consumers/first-subscription.md) and
[request contract](landingzones/README.md) in the generated vending repository.
Subscription requests are not contributions to the upstream accelerator.

## Modifying an archetype default

Follow [Archetypes](docs/archetypes.md#modifying-an-existing-archetype) for
the change and review requirements. Operators use the
[Run guide](docs/operators/run.md) for platform configuration and deployment.

## Bumping an AVM module version

Each engine has an exact AVM pin:

```hcl
module "subscription" {
  source  = "Azure/avm-ptn-alz-sub-vending/azure"
  version = "0.3.2"
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

## Preparing an accelerator release

Before tagging a release, update `accelerator.json` so `version` exactly
matches the planned Git tag, including the leading `v`. Generated repositories
record this value with the managed-file hashes used by later upgrades. Keep
`upgrade-manifest.json` aligned with any new seeded paths or ownership changes.

## Product mandate

All contributions must preserve this accelerator's complementary role after
the official ALZ Accelerator has established the platform landing zone.

Changes may integrate subscription vending with ALZ platform management
groups, policies, connectivity, AVNM, IPAM, monitoring, security, identities,
and shared services. They must consume those platform capabilities rather than
recreate or replace them.

Do not add features that turn this repository into a competing platform
landing-zone accelerator or a workload deployment framework. Review
[`docs/product-mandate.md`](docs/product-mandate.md) before proposing a new
product capability.

## Commit messages

Conventional Commits:

- `feat(corp): vend prod-corp-erp-001`
- `fix(online): correct address space for prod-online-web-001`
- `chore(archetypes): bump AVM module to 0.3.2`
- `chore(bicep): bump sub-vending AVM to 0.9.0`
- `docs(onboarding): clarify MCA invoice section lookup`

## Tests / pre-commit

Run the smallest relevant checks before you open a PR:

- `tests/PowerShell/SubscriptionVending.Tests.ps1`
- `tests/PowerShell/BicepStarter.Tests.ps1`
- `tests/PowerShell/Upgrade.Tests.ps1`
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

## Documentation changes

Start at the [documentation index](docs/README.md). Keep operator procedures,
consumer instructions, component references, and [proposals][proposals]
separate. The [starter contract][contract] documents current implementation,
not future product direction.

When moving a page, preserve its former path and heading anchors with a
section-aware compatibility page. Update maintained Markdown links and check
the source repository plus both generated engine packages. Source-only files
need explicit upstream links from shared documentation. Do not edit request
YAML or runtime Terraform comments just to update a link if that would trigger
an unrelated deployment; a compatibility page keeps the old reference valid.

[security]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/SECURITY.md
[support]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/SUPPORT.md
[proposals]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/proposals/README.md
[contract]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/starter-contract.md
