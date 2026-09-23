# Run

[Documentation](../README.md) | Previous: [Bootstrap](bootstrap.md)

**Audience:** operators of an established vending service and deployment
reviewers. Work in the **generated vending repository**, not the accelerator
source checkout. Routine vending does not require the original bootstrap
workstation.

Before the first request, complete [Bootstrap](bootstrap.md), including the
billing-role grant and readiness checks.

## Verify the first vend

Follow the [consumer walkthrough](../consumers/first-subscription.md) with
one reviewed request. Do not start by applying every example request.

Confirm that:

1. The PR validates the YAML and displays the selected engine's preview.
2. The request receives the required review before merging.
3. The Apply workflow waits for the production environment approval.
4. After approval, the job summary reports deployment status and the
   subscription ID. Inspect failure details rather than treating a partial
   deployment as a successful handoff.
5. The workload owner can find the request, deployment result, and the
   platform team's support contact.

Terraform uses a separate state key per subscription. Bicep uses
management-group deployments and has no per-subscription Terraform state.
The [CI/CD reference](../../.github/CICD.md#how-the-applyyml-matrix-runs)
describes summaries and artifacts for both engines.

Give workload teams the generated repository URL and the
[consumer walkthrough](../consumers/first-subscription.md). They do not need
bootstrap credentials or permissions.

## Updating platform inputs after bootstrap

Treat the generated repository as the source of truth. Bootstrap can resume
an incomplete initial setup, but its state is not a day-to-day source
synchronization mechanism.

| Change | Where to change it in the generated repository |
|---|---|
| Add or update a billing scope | `terraform/terraform.auto.tfvars` or `bicep/platform.json`; grant SubscriptionCreator on each new scope |
| Change cost-allocation settings or mandatory tags | Selected engine platform configuration; see [Tagging](../tagging.md) |
| Change hub VNet or remote-gateway settings | Selected engine platform configuration |
| Add an archetype and management group | Engine rules, platform configuration, schema, request folder, and CODEOWNERS; see [Archetypes](../archetypes.md#adding-a-new-archetype) |
| Change branch protection or production approvers | GitHub repository settings or your separately maintained day-2 configuration |
| Rotate the pipeline identity or recreate the repository | Separate control-plane recovery, planned from saved bootstrap state; verify that it does not reconcile seeded files |

Make runtime configuration changes through reviewed PRs. Shared engine,
platform, schema, and delivery changes select every subscription for preview,
but they do not deploy automatically after merge. If the same merge also
changes request YAML files, those requests are held for the explicit run too.

## Reruns and wider changes

After merging a shared change, review the completed Apply workflow summary.
It confirms that no subscriptions were selected automatically. Then use
**Actions > Apply > Run workflow**:

| Mode | Use |
|---|---|
| `single` | Retry one request using its `landingzones/<archetype>/<name>.yaml` path |
| `all` | Deliberately deploy all requests after reviewing a platform-wide change |
| `changed` | Re-run change discovery manually; shared files still participate in discovery |

The production environment gate still applies. See the
[CI/CD trigger and discovery reference](../../.github/CICD.md#trigger-matrix)
and [approval troubleshooting](../../.github/CICD.md#troubleshooting).

## Updating the starter itself

The accelerator repository is the starter source, but local changes to it do
not propagate to an already generated repository. Bootstrap copies the starter
only during the initial handoff.

Until the versioned upgrade mechanism in
[#34](https://github.com/haflidif/alz-sub-vending-terraform-accelerator/issues/34)
is available, move an intentional engine or workflow change into the generated
repository through a normal pull request. Do not rerun bootstrap to reseed it.
Repository-specific requests, platform values, CODEOWNERS, and customizations
must remain under the generated repository's ownership.

Documentation updates follow the same reviewed-PR path. Existing generated
repositories do not receive this documentation layout automatically.

For local accelerator cleanup, see the [helper reference](../../scripts/README.md).
Local file cleanup is not an upgrade or a resource-retirement operation.

## Tuning Dependabot cadence

The [CI/CD reference](../../.github/CICD.md#dependabot-cadence) owns the
dependency-update schedule. Edit [`.github/dependabot.yml`](../../.github/dependabot.yml)
in the generated repository through a PR when your change-management process
requires a different cadence.

## Retirement and recovery

Deleting a request YAML does not cancel the Azure subscription.
Subscription retirement is a privileged operator task, separate from routine
request changes. Review the warnings in the
[retirement runbook](retire-subscription.md) before preparing a retirement plan.

Undoing bootstrap affects the service itself, not one subscription. Use the
[bootstrap recovery reference](../bootstrap-wizard.md#destroying--undoing-a-bootstrap)
from the accelerator source only after reviewing the affected resources and
saved state.

---

Previous: [Bootstrap](bootstrap.md) | [Consumer walkthrough](../consumers/first-subscription.md) | [Documentation](../README.md)
