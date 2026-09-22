# Quick start

This is the short operator path to a working subscription-vending service.
If your platform team has already provided a vending repository, skip setup
and follow [Your first subscription](docs/consumers/first-subscription.md).

## Planning

Choose Terraform or Bicep, identify your existing platform and billing scopes,
and agree on archetypes, networking, tags, and reviewers.
Record these decisions using [Planning](docs/operators/planning.md).
An established repository cannot switch engines in place.

<a name="prerequisites-5-min-read"></a>

## Prerequisites

Verify [Prerequisites](docs/operators/prerequisites.md) before running commands.
Both engines require Terraform for bootstrap. Only the Terraform runtime
requires the vending state storage account and container.

Use an **accelerator source checkout** containing `powershell/`, `starters/`,
and `bootstrap/`. These directories do not exist in generated vending
repositories.

<a name="day-1-bootstrap-15-min"></a>

## Bootstrap

From the accelerator source root:

```powershell
az login --tenant <your-tenant-id>
gh auth login

Import-Module ./powershell/SubscriptionVending/SubscriptionVending.psd1
Get-SubscriptionVendingEngine
Initialize-SubscriptionVending -Engine Terraform # or Bicep
```

Review the configuration and Terraform plan before applying. Follow
[Bootstrap](docs/operators/bootstrap.md) to capture the outputs, grant
SubscriptionCreator on the billing scope, and validate readiness.
Repository creation alone does not complete the billing-role step.

The wizard can resume an incomplete initial bootstrap. Once the handoff
succeeds, make changes through PRs in the generated repository.
Do not rerun bootstrap to synchronize files or update the engine.

<a name="day-1-vend-your-first-subscription-5-min"></a>

## Run

Switch to the **generated vending repository**. Follow
[Run](docs/operators/run.md) to verify a first request through schema
validation, preview, review, merge, production approval, and deployment output.
Give workload teams the [consumer walkthrough](docs/consumers/first-subscription.md).

<a name="day-7-settle-in"></a>
<a name="day-30-operationalize"></a>

Use Run for [platform changes](docs/operators/run.md#updating-platform-inputs-after-bootstrap),
[wider deployments](docs/operators/run.md#reruns-and-wider-changes), and
[starter updates](docs/operators/run.md#updating-the-starter-itself).

## Need help?

Use the [wizard reference](docs/bootstrap-wizard.md) for initial bootstrap
errors and [CI/CD troubleshooting](.github/CICD.md#troubleshooting) for
delivery problems. Undoing bootstrap and retiring a single subscription are
different privileged operations; start with [recovery guidance](docs/operators/run.md#retirement-and-recovery).

<a name="key-documentation"></a>

[Documentation index](docs/README.md) | [Architecture](docs/architecture.md) | [Changelog](CHANGELOG.md)
