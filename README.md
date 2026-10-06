<h1><img src="website/static/brand/subscription-vending-mark-192.png" alt="" width="52" /> Azure Subscription Vending</h1>

Azure subscription-vending accelerator with **Terraform and Bicep engines**,
one shared YAML request contract, and GitHub Actions delivery. Terraform uses
[`Azure/avm-ptn-alz-sub-vending/azure`][avm] with isolated per-subscription
state. Bicep uses the Azure Verified Modules subscription-vending pattern with
management-group deployments through
[`br/public:avm/ptn/lz/sub-vending:0.8.0`][bicep-avm].

## Product mandate

This accelerator is the **next operational step after the official Azure
Landing Zones Accelerator has built the platform landing zone**. It is a
complementary accelerator for governed application landing-zone subscription
vending.

The established ALZ platform remains authoritative for management groups,
Azure Policy, connectivity, management, monitoring, security, identity, and
shared platform resources. This accelerator consumes those foundations to
create and maintain application landing-zone subscriptions. It does not deploy
or replace the platform landing zone, and it does not deploy workload
applications.

See [Product mandate](docs/product-mandate.md) for the permanent mission,
required platform foundation, ownership boundary, and design rules.

## Project status and support

This is an independently maintained open-source project. It is not a Microsoft
product or service, and it is not part of the official Azure Landing Zones
Accelerator. The maintainer's employment by Microsoft does not create
Microsoft sponsorship, ownership, endorsement, or support for this project.

The project has no service-level agreement (SLA), guaranteed response time, or
production support commitment. It is not covered by Microsoft Support, an
Azure support plan, or another Microsoft commercial support agreement.
Maintainers and contributors may provide community assistance on a best-effort
basis, without a commitment to respond or resolve an issue.

Microsoft and Azure names, product names, and publicly permitted branding are
used only to identify the technologies that this accelerator integrates with.
See the [support policy][support] for the complete expectations and support
boundary.

## Two audiences, two paths

| Your task | Start here |
|---|---|
| Establish a vending service | [Planning](docs/operators/planning.md), [Prerequisites](docs/operators/prerequisites.md), [Bootstrap](docs/operators/bootstrap.md), then [Run](docs/operators/run.md) |
| Get a short overview of operator setup | [Quick start](QUICKSTART.md) |
| Request a subscription from an existing service | [Your first subscription](docs/consumers/first-subscription.md) |
| Maintain the service or review deployments | [Run](docs/operators/run.md) |
| Understand the design | [Architecture](docs/architecture.md) |

Use the [documentation index](docs/README.md) for the full reference catalog.
Workload teams do not run bootstrap.

<a name="tldr--request-a-new-subscription"></a>

## TL;DR: request a new subscription

In the **generated vending repository** provided by your platform team,
add one YAML file under `landingzones/<archetype>/` and open a PR.
CI validates the request and shows a Terraform plan or Bicep what-if.
After review and merge, the Apply workflow deploys behind the production
environment approval gate.

The [consumer walkthrough](docs/consumers/first-subscription.md) covers each
step. The [request contract](landingzones/README.md) describes the fields.
Deleting a YAML file does not cancel the Azure subscription.

## Repository layout

The **accelerator source** contains bootstrap tooling, both engines, starter
metadata, and tests. The **generated vending repository** contains shared
runtime files, operating docs, and only the selected engine with its rendered
platform configuration. Bootstrap and development assets are not copied.

| Area | Purpose |
|---|---|
| `landingzones/` | One YAML request per subscription and the shared schema |
| Selected `terraform/` or `bicep/` directory | Runtime engine and platform configuration |
| `.github/` | Preview and deployment workflows |
| `docs/` | Operator journey, consumer guide, and references |

See [Repository layout](docs/repository-layout.md) for the complete source
tree, generated-package boundaries, and where to make changes.

## How CI selects what to operate on

Each request is a separate workflow matrix item. Terraform isolates state
per subscription; Bicep uses management-group deployments. Shared engine
changes preview all requests, but require an explicit Apply run with
`mode=all` after merge.

The [CI/CD reference](.github/CICD.md) documents `changed`, `single`, and
`all` modes, approval gates, outputs, and troubleshooting.

<a name="operator-setup-one-time"></a>

## Operator setup

Start with [Planning](docs/operators/planning.md) and verify
[Prerequisites](docs/operators/prerequisites.md). Both engines use the
shared Terraform bootstrap to establish the repository and pipeline identity.
The operator then grants billing permissions explicitly and verifies readiness.

[Bootstrap](docs/operators/bootstrap.md) runs from the accelerator source
checkout. After a successful initial handoff, the generated repository owns
its source. Do not rerun bootstrap to synchronize files or deliver upgrades.

<a name="local-usage-developing-the-skeleton-or-break-glass-plan"></a>

## Local usage

Routine vending runs in GitHub Actions. For local engine work, use the
[Terraform][terraform] or [Bicep][bicep] component reference in the accelerator
source, then run commands from the corresponding selected-engine directory
in your vending repository.

## Adding a new archetype

Follow [Archetypes](docs/archetypes.md#adding-a-new-archetype) for coordinated
engine, configuration, schema, and CODEOWNERS changes. Use a reviewed PR in
the vending repository, not another bootstrap apply.

## Wide upgrades

Generated repositories include a local, version-aware upgrade command:

```powershell
# Preview a specific tagged release
pwsh ./scripts/Update-SubscriptionVending.ps1 -TargetVersion v0.4.0

# Create a local upgrade branch and apply the managed-file changes
pwsh ./scripts/Update-SubscriptionVending.ps1 -TargetVersion v0.4.0 -Apply
```

The command preserves requests, rendered platform configuration, CODEOWNERS,
and local additions. It stops before changing anything when an upstream change
conflicts with a locally modified managed file. See
[the upgrade runbook](docs/operators/upgrade.md) and use
[Run](docs/operators/run.md#reruns-and-wider-changes) for the explicit
`mode=all` deployment after an upgrade is reviewed and merged.

## Documentation index

The [documentation index](docs/README.md) separates operator and consumer
tasks from technical references and contributor material.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Extended product proposals and
historical plans are separate [maintainer design material][proposals],
not operating instructions or a supported-feature list.

[avm]: https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest
[bicep-avm]: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/lz/sub-vending
[terraform]: https://github.com/haflidif/alz-sub-vending-accelerator/blob/main/terraform/README.md
[bicep]: https://github.com/haflidif/alz-sub-vending-accelerator/blob/main/bicep/README.md
[proposals]: https://github.com/haflidif/alz-sub-vending-accelerator/blob/main/docs/proposals/README.md
[support]: https://github.com/haflidif/alz-sub-vending-accelerator/blob/main/SUPPORT.md
