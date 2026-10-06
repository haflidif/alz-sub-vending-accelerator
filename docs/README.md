# Documentation

Choose the path for your role. The accelerator source is used to establish
the service; the generated vending repository is where operators and workload
teams manage subscription requests.

The [product mandate](product-mandate.md) defines the permanent boundary: the
official ALZ Accelerator establishes the platform landing zone, then this
accelerator provides governed application landing-zone subscription vending.

## Platform operators

| Phase | Outcome |
|---|---|
| [Planning](operators/planning.md) | Choose the engine, platform integrations, billing scopes, governance, and reviewers |
| [Prerequisites](operators/prerequisites.md) | Verify tools, existing Azure resources, and Azure, billing, and GitHub access |
| [Bootstrap](operators/bootstrap.md) | Create the delivery environment, complete the billing-role grant, and hand off the repository |
| [Run](operators/run.md) | Verify the first request, maintain configuration, review deployments, and find recovery guidance |
| [Upgrade](operators/upgrade.md) | Preview and apply a tagged accelerator release without overwriting repository-owned content |

Already operating a service? Start at [Run](operators/run.md).

## Workload teams and reviewers

Start with [your first subscription](consumers/first-subscription.md).
You work in the repository provided by the platform team and do not run
bootstrap. Use the [request contract](../landingzones/README.md) when authoring
YAML and the references below when reviewing placement, ownership, and cost.

## Reference

| Topic | Reference |
|---|---|
| Mission, required ALZ foundation, and scope boundary | [Product mandate](product-mandate.md) |
| Concepts and deployment flow | [Architecture](architecture.md) and [glossary](glossary.md) |
| Source versus generated files | [Repository layout](repository-layout.md) |
| Request fields | [Subscription contract](../landingzones/README.md) and [schema validation](schema-validation.md) |
| Placement and guardrails | [Archetypes](archetypes.md) |
| Names and aliases | [Naming convention](naming-convention.md) |
| Billing agreements and scope selection | [Billing scopes](billing-scopes.md) |
| Governed tags and cost allocation | [Tagging](tagging.md) |
| Terraform state | [State storage](state-storage.md) |
| Delivery, approvals, and troubleshooting | [CI/CD reference](../.github/CICD.md) |
| Bootstrap flags, resumability, and undo | [Wizard reference](bootstrap-wizard.md) |
| Manual bootstrap and resource inventory | [Bootstrap reference][bootstrap] (accelerator source) |
| Bootstrap module interface | [PowerShell module][powershell] (accelerator source) |
| Runtime engine details | [Terraform][terraform] or [Bicep][bicep] (accelerator source; only the selected engine folder exists in a generated repository) |
| Local helper scripts | [Scripts](../scripts/README.md) |
| Versioned starter upgrades | [Upgrade runbook](operators/upgrade.md) |
| Subscription retirement | [Advanced operator runbook](operators/retire-subscription.md), with review warnings |

## Contributing to the accelerator

For upstream development, use [CONTRIBUTING][contributing] and the
[implemented starter contract][contract]. These describe contribution and
implementation boundaries, not extra steps for consumers.

### Proposals and historical design

The [proposal index][proposals] contains extended product vision and a
historical delivery roadmap. These are not current operating instructions or
promises of supported features. Proposal files and the contributor contract
are excluded from generated vending repositories; these links open the
accelerator source.

## Documentation compatibility

The former onboarding, first-vend, and teardown URLs remain as section-aware
compatibility pages. New links should target the canonical pages above.
Documentation updates to existing vending repositories are reviewed PRs,
not bootstrap reruns.

[bootstrap]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md
[powershell]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/powershell/SubscriptionVending/README.md
[terraform]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/terraform/README.md
[bicep]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bicep/README.md
[contributing]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/CONTRIBUTING.md
[contract]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/starter-contract.md
[proposals]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/docs/proposals/README.md
