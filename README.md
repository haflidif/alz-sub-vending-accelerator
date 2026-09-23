# Azure Subscription Vending

Azure subscription-vending accelerator with **Terraform and Bicep engines**,
one shared YAML request contract, and GitHub Actions delivery. Terraform uses
[`Azure/avm-ptn-alz-sub-vending/azure`][avm] with isolated per-subscription
state. Bicep uses the Azure Verified Modules subscription-vending pattern with
management-group deployments through
[`br/public:avm/ptn/lz/sub-vending:0.8.0`][bicep-avm].

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
changes can affect all requests.

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

Use [Run](docs/operators/run.md#reruns-and-wider-changes) for deliberate
repository-wide deployment and
[starter updates](docs/operators/run.md#updating-the-starter-itself) for
the distinction between runtime changes and upstream updates.

## Documentation index

The [documentation index](docs/README.md) separates operator and consumer
tasks from technical references and contributor material.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Extended product proposals and
historical plans are separate [maintainer design material][proposals],
not operating instructions or a supported-feature list.

[avm]: https://registry.terraform.io/modules/Azure/avm-ptn-alz-sub-vending/azure/latest
[bicep-avm]: https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/lz/sub-vending
[terraform]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/terraform/README.md
[bicep]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bicep/README.md
[proposals]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/proposals/README.md
