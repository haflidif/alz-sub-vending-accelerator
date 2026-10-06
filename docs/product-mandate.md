# Product mandate

This accelerator is the operational next step after the official Azure
Landing Zones (ALZ) Accelerator has established the platform landing zone.
It complements the ALZ Accelerator by providing a governed subscription
vending service for application landing zones.

## Mission

Provide platform teams with a repeatable, reviewable, and upgradeable way to
create and maintain application landing-zone subscriptions on an established
ALZ platform.

The accelerator turns a governed subscription request into an approved Azure
subscription with the required placement, connectivity, tags, budgets, role
assignments, resource providers, and supporting resources.

## Required platform foundation

Run the official ALZ Accelerator before adopting this accelerator. The
existing platform landing zone remains authoritative for:

- Management-group hierarchy and subscription placement boundaries
- Azure Policy assignments and governance
- Platform connectivity, including hubs and future AVNM or IPAM services
- Management, monitoring, security, and identity foundations
- Platform subscriptions and shared resources
- Enterprise operating and ownership models

This accelerator consumes those platform decisions through management-group
IDs, billing scopes, connectivity resource IDs, tags, and other explicit
configuration. It does not establish an alternative platform authority.

## Product boundary

This accelerator owns the application landing-zone subscription lifecycle:

1. Capture a subscription request as reviewed YAML.
2. Validate the request against platform capabilities and guardrails.
3. Preview the selected engine deployment in a pull request.
4. Require repository and production approval.
5. Create or adopt the subscription.
6. Place and configure it against the established ALZ platform.
7. Maintain it through controlled updates, upgrades, and retirement.

It does not:

- Deploy or replace the ALZ platform landing zone
- Create a competing management-group hierarchy
- Define a parallel Azure Policy or governance baseline
- Replace platform connectivity, monitoring, security, or identity services
- Deploy workload applications into the vended subscription
- Become a general-purpose Azure platform accelerator

## Design mandate

Every feature must preserve the complementary boundary:

- Integrate with ALZ platform capabilities instead of duplicating them.
- Treat platform configuration as an external contract.
- Keep subscription requests portable across the supported Terraform and
  Bicep engines.
- Make changes reviewable, previewable, auditable, and safe to upgrade.
- Keep platform-wide effects explicit and approval-gated.
- Reject features that move platform-foundation ownership into this
  accelerator.

Future networking, AVNM, IPAM, policy, and governance integrations must
consume the services and boundaries established by the ALZ platform. They
must not create a second source of truth.

## Product sequence

```text
Official ALZ Accelerator
        |
        v
Established platform landing zone
        |
        v
Subscription Vending Accelerator
        |
        v
Governed application landing-zone subscriptions
        |
        v
Workload deployment
```

This sequence is the permanent product mandate, not a temporary implementation
limitation.
