---
title: Azure Subscription Vending Accelerator
geekdocEditPath: edit/main/website
---

# Azure Subscription Vending Accelerator

> **Independent community project:** This accelerator is maintained
> independently and is not a Microsoft product or part of the official Azure
> Landing Zones Accelerator. It has no Microsoft Support coverage, service-level
> agreement, or guaranteed response time. Review the [support policy](support/)
> before using it in production.

Build governed application landing-zone subscriptions after the official Azure
Landing Zones Accelerator has established the platform foundation.

## Start with your role

| Your role | Start here | Outcome |
|---|---|---|
| Platform operator | [Plan the service](docs/operators/planning/) | Choose the engine, billing model, ALZ integration, governance, and reviewers |
| Platform operator | [Verify prerequisites](docs/operators/prerequisites/) | Confirm Azure, billing, GitHub, and platform readiness |
| Platform operator | [Run bootstrap](docs/operators/bootstrap/) | Create and configure a generated vending repository |
| Workload team | [Request your first subscription](docs/consumers/first-subscription/) | Submit one reviewed YAML request |
| Maintainer | [Operate the service](docs/operators/run/) | Review changes, deploy requests, recover, and upgrade |

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

The established ALZ platform remains authoritative for management groups,
Azure Policy, connectivity, management, monitoring, security, identity, and
shared platform resources. This accelerator consumes those foundations. It
does not replace the platform landing zone or deploy workload applications.

## Explore the documentation

- [Product mandate](docs/product-mandate/)
- [Architecture](docs/architecture/)
- [Operator journey](docs/operators/)
- [Consumer journey](docs/consumers/)
- [Subscription request contract](landingzones/)
- [Upgrade runbook](docs/operators/upgrade/)
- [Support expectations](support/)
- [Security reporting](security/)
- [Contributing](contributing/)

## Current maturity

The accelerator is a pre-1.0 project with Terraform and Bicep engines, a shared
YAML request contract, GitHub Actions delivery, controlled generated-repository
upgrades, and an explicit complementary product boundary. Review the
[roadmap](https://github.com/haflidif/alz-sub-vending-accelerator/issues/59)
before depending on planned capabilities.
