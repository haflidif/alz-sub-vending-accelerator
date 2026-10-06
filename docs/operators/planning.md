# Planning

[Documentation](../README.md) | Next: [Prerequisites](prerequisites.md)

**Audience:** platform operators establishing subscription vending.
Decide how the service fits your existing Azure platform before running
bootstrap. If these decisions are already agreed, continue to Prerequisites.

Run the official ALZ Accelerator before adopting this accelerator. The ALZ
Accelerator establishes the platform landing zone; this accelerator prepares
the complementary GitHub delivery repository for governed application
landing-zone subscription requests.

It does not deploy the platform landing zone or workload applications. It
consumes the existing management groups, governance, connectivity, management,
security, identity, and shared resources. Review the
[product mandate](../product-mandate.md) before recording implementation
decisions.

## Decisions to record

| Decision | Record before bootstrap | Reference |
|---|---|---|
| Runtime engine | Terraform or Bicep; a generated repository uses one engine and cannot switch in place | [Architecture](../architecture.md) |
| ALZ platform ownership | Tenant, platform subscriptions, ALZ root management group, and responsible platform team | [Product mandate](../product-mandate.md) |
| Placement | Management-group IDs for each supported archetype | [Archetypes](../archetypes.md) |
| Billing | Agreement type, scope IDs, named scope keys including `default`, and the person authorized to grant billing roles | [Billing scopes](../billing-scopes.md) |
| Networking | Whether requests need a spoke network or hub peering, and the existing hub VNet resource ID when used | [Archetypes](../archetypes.md) |
| Governance | Mandatory tags, cost-allocation tag key and validation, budgets, and ownership fields | [Tagging](../tagging.md) |
| GitHub delivery | Owner, repository name, visibility, CODEOWNERS, and production reviewers | [CI/CD reference](../../.github/CICD.md) |
| Runtime state | For Terraform, the existing storage account and dedicated vending container; Bicep runtime has no Terraform state | [State storage](../state-storage.md) |
| Recovery ownership | Who retains bootstrap state and reviews control-plane recovery after the initial handoff | [Bootstrap ownership][ownership] |

Both engines currently use Terraform for bootstrap. Choosing Bicep removes
the Terraform state requirement for routine vending, not the bootstrap's
Terraform dependency or recovery state.

## Understand the handoff

The accelerator source provides bootstrap tooling and both engine packages.
Bootstrap creates a vending repository containing the selected engine,
platform configuration, request examples, workflows, and operating docs.

After successful bootstrap, the generated repository owns its source.
Consumers submit YAML requests there; operators update platform configuration
through PRs. Bootstrap is not a source synchronization or upgrade tool.

Use [the glossary](../glossary.md) for terminology and
[the consumer walkthrough](../consumers/first-subscription.md) to see the
experience your platform team will provide.

## Ready to continue

You have selected an engine, identified platform and billing owners, and
recorded the required configuration decisions. Now verify resources, tools,
and access in [Prerequisites](prerequisites.md).

This journey follows the structure of the official
[ALZ accelerator planning guidance](https://azure.github.io/Azure-Landing-Zones/accelerator/0_planning/),
adapted to subscription vending. Upstream platform deployment options are
not a statement of this project's supported features.

[ownership]: https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/bootstrap/README.md#repository-ownership-after-bootstrap
