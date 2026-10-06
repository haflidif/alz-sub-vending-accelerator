---
title: Azure Subscription Vending Accelerator
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

<figure class="product-sequence">
  <a
    href="https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending"
  >
    <img
      src="images/subscription-vending-high-res.png"
      width="2184"
      height="280"
      style="display: block; width: 100%; max-width: 100%; height: auto"
      alt="Four-step subscription lifecycle: create platform subscriptions, create the platform, establish subscription vending, and deploy the workload. The first two steps belong to the platform, subscription vending spans the platform and application boundary, and workload deployment belongs to the application."
    />
  </a>
  <figcaption>
    Source:
    <a
      href="https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/subscription-vending"
    >Subscription vending, Microsoft Cloud Adoption Framework</a>.
    Licensed under
    <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>.
  </figcaption>
</figure>

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
