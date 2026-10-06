# Subscription Vending IaC Accelerator

> Status: Extended product vision, 2026-09-08.
> Scope decision, 2026-09-16: the initial accelerator product is limited to an
> ALZ-style PowerShell module that bootstraps a complete Terraform or Bicep
> subscription-vending repository. Workload repository creation and application
> onboarding are deferred extensions. The versioned starter contract in
> [starter-contract.md](../starter-contract.md) defines the current delivery
> boundary.
>
> Permanent product mandate, 2026-10-01: this accelerator is the complementary
> subscription-vending step after the official ALZ Accelerator establishes the
> platform landing zone. It consumes that foundation and does not support an
> alternative platform authority.

## Problem statement

Subscription vending is the next phase after establishing an Azure platform
landing zone. The ALZ ecosystem provides Terraform and Bicep subscription-vending
modules, but operators still need a configured delivery environment around them:
repositories, identities, permissions, request contracts, approvals, and pipelines.

This project already implements a Terraform-based version of that experience.
Its [bootstrap script](../../bootstrap/Invoke-Bootstrap.ps1) provides guided
configuration, prerequisite checks, validation, and resumability.
The [engine](../../terraform/main.tf) consumes the upstream AVM pattern.
The [workflows](../../.github/workflows/pr-validate.yml) operate on individual
subscription contracts with isolated Terraform state.

Extending this by copying the engine and bootstrap would duplicate governance
rules and create two products to maintain. The current contract also exposes
Terraform-specific role-assignment and subnet fields, while platform configuration
and archetype resolution live in Terraform.

The objective is a maintained Subscription Vending IaC Accelerator, not a
throwaway proof of concept. The PoC is the first delivery milestone.

## Product position

Follow the Azure Landing Zones IaC Accelerator approach for the
subscription-vending phase:

1. Establish the platform landing zone.
2. Bootstrap a subscription-vending delivery environment.
3. Vend and maintain application landing zones through reviewed requests.
4. Hand off application deployment to workload teams.

The official ALZ Accelerator establishes the platform landing zone first.
Require its management groups, governance, connectivity, shared services,
billing access, and other platform integrations as the foundation for
subscription vending. This accelerator must not establish a competing platform
authority.

This is an independently maintained project aligned with ALZ, not an official
Azure product or an endorsed ALZ extension. Azure organization hosting,
documentation links, naming, and long-term upstream ownership require separate
agreement. Do not assume internal team responsibilities or unpublished roadmaps.

### Product ambition: a standard path for 95% of customers

Aim to provide a standard subscription-vending product that 95% of customers
with subscription-vending needs can adopt through supported configuration,
without bespoke accelerator code or a customer-specific fork. The ambition is
to become a widely adopted default approach, not another reference sample that
each customer must turn into a product.

The 95% figure is a design and suitability target, not a measured compatibility
result, an adoption forecast, or a claim that 95% of customers already use it.
Actual adoption is a separate outcome. Define the target customer population
and gather representative evidence before making a quantified coverage claim.
Report exclusions and prerequisites rather than narrowing the denominator to
customers whose scenarios already work.

This goal means:

- Common requirements use documented configuration and opinionated defaults.
- Customers do not need to understand upstream AVM internals to get started.
- Terraform/Bicep and GitHub/Azure DevOps are product coverage goals, even when
  preview releases introduce them incrementally.
- Onboarding, diagnostics, recovery, upgrades, and lifecycle operations are
  product capabilities, not exercises left to each customer.
- Uncommon requirements use explicit extension points without duplicating the
  shared engine or preventing future upgrades.
- Configuration scope grows from recurring customer needs, not from exposing
  every upstream parameter or embedding individual customer exceptions.

Not every scenario belongs in the core. A customer's access prerequisites,
billing eligibility, organizational approvals, and platform prerequisites still
apply. Make supported, extension-required, and unsupported scenarios visible.

### Intended hosting path

Incubate in the maintainer's personal repository or an AzureViking organization
repository, with eventual hosting in the GitHub `Azure` organization as the
preferred direction if accepted by its owners. This is an aspiration, not an
approved transfer or a prerequisite for beginning implementation.

Agree sponsorship, maintainer access, support responsibilities, contribution
requirements, and CI/deployment funding before proposing the transfer.
Do not equate organization hosting with product support or guaranteed CI capacity.
Standard GitHub-hosted runner minutes are already free for public repositories;
private repository allowances, larger runners, storage, and Azure deployment
costs need separate consideration.

### Audiences

| Audience | Outcome |
|---|---|
| Platform operator | Establish and maintain a governed vending service with a familiar ALZ-style experience |
| Workload team | Request a subscription without understanding AVM module parameters or bootstrap infrastructure |
| Governance and finance reviewers | Review ownership, placement, connectivity, budget, and lifecycle decisions |
| Contributor | Extend a documented contract and starter interface without duplicating resource implementations |

## Proposed architecture

Separate orchestration, bootstrap, starters, and routine vending.

```text
Operator configuration
        |
Dedicated PowerShell entry point
        |
Prerequisites -> configuration -> validation -> bootstrap
                                                |
                           Upstream bootstrap components + thin adapter
                                                |
                                     Generated vending repository
                                                |
Subscription YAML -> shared contract resolver -> review and approval
                                                |
                                   Selected deployment engine
                                   /                        \
                           Terraform AVM                 Bicep AVM
                                   \                        /
                                   Deployment receipt and handoff
```

### PowerShell orchestration

Own a thin module with a distinct package and command namespace, provisionally
`SubscriptionVending`. Start by extracting behavior from
`bootstrap/Invoke-Bootstrap.ps1`, not by copying the ALZ PowerShell implementation.

The module is responsible for configuration capture, prerequisite reporting,
tenant and account binding, starter selection, and bootstrap orchestration.
Interactive and unattended execution consume the same validated inputs.
Sensitive authentication material must not be written into configuration,
generated repositories, deployment receipts, or logs.

Retain `Invoke-Bootstrap.ps1` as a compatibility entry point during migration.
Do not change its existing behavior merely to introduce the new module.
Package names, public command names, and release distribution are not finalized.

The operator's workstation is not a runtime dependency for normal subscription
requests. Generated CI/CD owns routine vending.

### Bootstrap components

Reuse public ALZ bootstrap components where their interfaces fit. A separate
entry point does not require a separate implementation of identities, federation,
repositories, or approval configuration.

Terraform remains an acceptable bootstrap dependency for both starters. This
matches the documented ALZ accelerator model. Distinguish bootstrap state from
per-subscription vending state: Bicep does not require the latter, but that does
not eliminate the bootstrap's own Terraform state and recovery requirements.

Document the owner, scope, and lifecycle of each bootstrap resource. Bootstrap
reruns must not overwrite workload contracts or day-two repository edits.
Template upgrades must produce reviewable changes, not silently reseed a repo.

Separate preview and deployment identities with explicit permissions. Treat
untrusted PR execution, state access, billing permissions, management-group
placement, and hub networking access as separate authorization concerns.
Do not assume new-subscription permissions apply when adopting an existing one.

### Shared configuration and contract

Define three independently versioned inputs:

| Input | Contents |
|---|---|
| Bootstrap configuration | Repository provider, engine, deployment location, identity setup, and bootstrap resource references |
| Platform configuration | Billing scope references, target management groups, connectivity profiles, archetypes, and tagging rules |
| Subscription contract | Request identity, owner, application environment, location, budget, access, and requested connectivity |

Use one resolver for editor/local validation and CI. It validates the contract,
applies platform defaults and guardrails, and emits a normalized deployment model.
Engine adapters translate that model into Terraform inputs or ARM deployment
parameters. Business rules must not be independently implemented in each adapter.

Required invariants:

- Every request has a stable identity independent of its file name and folder.
  Existing Terraform state keys require an explicit migration, not automatic
  renaming when this identity is introduced.
- A repository selects one deployment engine initially. Engine ownership cannot
  change through an ordinary subscription edit.
- An application environment such as `dev`, `test`, or `prod` is distinct from
  the subscription billing workload offer `Production` or `DevTest`.
- Connectivity rules express `required`, `optional`, or `forbidden`; invalid
  requests fail rather than silently changing the requested behavior.
- Reserved tags, billing choices, archetype placement, and budget rules are
  enforced before deployment.
- Unsupported engine capabilities produce explicit errors, not ignored fields
  or a success-shaped fallback.
- Removing a contract is not authorization to delete resources or cancel a
  subscription.
- Authentication material is not part of the contract.

Introduce schema versions and a compatibility adapter for current YAML.
Keep legacy rendering until old and new Terraform inputs can be compared.
Do not require existing consumers to migrate as a prerequisite for using the
current Terraform workflow.

### Engine starters

Each starter contains a thin AVM wrapper, pipeline templates, parameter rendering,
output normalization, and engine-specific lifecycle documentation.

| Engine | Upstream resource implementation | Execution semantics |
|---|---|---|
| Terraform | `Azure/avm-ptn-alz-sub-vending/azure` | Per-subscription state, plan, approval, and apply |
| Bicep | `avm/ptn/lz/sub-vending` | ARM validation, what-if where meaningful, approval, and deployment |

Publish a capability matrix against exact module releases before claiming
feature parity. In particular, map budgets, resource groups, role assignments,
managed identities, peering, and resource-provider registration.

Bicep what-if is not a saved Terraform plan. A new subscription identifier,
nested deployment, or deployment script can limit preview completeness. Report
those limits explicitly and bind the deployment to the reviewed commit,
configuration, and module versions.

Incremental ARM deployments do not delete resources merely because declarations
are removed. Subscription cancellation is a separate lifecycle action. Evaluate
deployment stacks only for explicitly scoped resource ownership; do not present
them as a general subscription-destroy equivalent.

Define platform versus workload ownership of subnets, NSG rules, and routes.
Neither starter may assume that redeployment safely preserves out-of-band edits
without evidence for the selected module and resource configuration.

### Delivery and handoff

PR discovery must include shared engine and platform changes, not only
subscription YAML changes. Plan the affected set and require explicit approval
for fleet-wide application. Discovery failures must fail the final gate rather
than look like an empty set of subscriptions.

After a successful deployment, emit a versioned receipt containing the request
identity, subscription ID, engine, source commit, relevant module versions,
management-group placement, and resource references needed by the workload team.
Report failed or partial deployments separately from successful handoffs.

Receipts are operational records, not Terraform state, credentials, or a claim
of continuing policy compliance. Use stable identity and preserved state to
support recovery without creating a second subscription.

## Reuse strategy

Reuse first, adapt where necessary, and build only what is missing.
Upstream availability does not prove compatibility with vending.

| Component | Proposed treatment | Evidence or compatibility work |
|---|---|---|
| Terraform AVM vending pattern | Consume a pinned upstream release | Already used by the current engine |
| Bicep AVM vending pattern | Consume a pinned upstream release | Map each exposed capability and deployment prerequisite |
| `Azure/accelerator-bootstrap-modules` | Prefer consumption through a thin adapter | Framework supports Terraform and Bicep; vending-specific permissions, state, outputs, and templates still need mapping |
| ALZ PowerShell module | Follow public orchestration conventions; optionally consume useful public commands | Do not depend on private functions or require changes in the other team's repository |
| ALZ starter and workflow patterns | Reuse compatible published components and established structure | Preserve provenance and license notices; document any maintained copies |
| Existing bootstrap script | Refactor incrementally | Preserve behavior and recovery paths |
| Contract resolver and lifecycle | Implement vending-specific behavior | These define this accelerator's request and operational model |

A reuse decision must record the upstream source and release, public interface,
required adaptation, license obligations, and upgrade owner. An incompatible
component requires a documented reason before replacement. Do not pin release
numbers based only on a repository's current branch or a wildcard version.

## What changes

- Introduce a dedicated PowerShell module and starter selection.
- Move shared configuration and business rules out of Terraform-only inputs.
- Add Bicep rendering and delivery without forking the resource implementation.
- Define bootstrap ownership and reviewable generated-repository upgrades.
- Add explicit capability, lifecycle, and release contracts.
- Evolve documentation from a Terraform-only template to an accelerator product.

## What stays the same

- The existing Terraform flow remains available during development.
- Workload teams continue to submit YAML requests through PRs.
- AVM remains responsible for the resource implementation.
- Terraform subscriptions retain their existing state unless explicitly migrated.
- Existing ALZ management groups and platform services remain externally owned.
- No automatic engine switch, destructive cleanup, or production rollout occurs.

## Scope

### First deployable preview

GitHub, one engine per generated repository, Terraform and Bicep starters, an
existing platform, and a documented common capability set: new subscription,
placement, tags, budget, access, optional managed identity, and optional spoke
peering. Capabilities enter the preview only after their adapter semantics are
demonstrated. Any missing capability remains explicit in the published matrix.

The local PoC precedes this preview and is not itself a deployable release.

### Maintained product roadmap

Azure DevOps support, local starter export, existing-subscription adoption,
readiness and handoff reporting, drift reporting, approved retirement and
detach, sandbox expiry and renewal, connectivity profiles, IPAM, and vWAN.
Sequence these by evidence and user demand rather than enabling every AVM input.

### Outside the initial scope

Platform landing-zone deployment, workload application deployment, a new
self-service portal, ITSM adapters, automatic Terraform-to-Bicep migration,
unattended subscription cancellation, and a Terraform-free bootstrap.
These are not prerequisites for a useful vending accelerator.

## Key decisions needed

| Decision | Recommendation | Decision owner |
|---|---|---|
| Product ownership | Maintain independently and coordinate with ALZ and AVM contributors | Project maintainer |
| Orchestration | Own a thin PowerShell module, reuse compatible upstream components | Project maintainer, informed by PoC findings |
| Bootstrap reuse | Select components after an interface-level compatibility exercise | Project maintainer |
| Initial repository provider | GitHub first; Azure DevOps is a subsequent milestone | Project maintainer |
| Engine selection | One engine per generated repository | Project maintainer |
| Shared contract | Versioned neutral model with legacy Terraform compatibility | Project maintainer |
| Public naming and hosting | Use a provisional name; do not imply Microsoft endorsement | Project maintainer; upstream maintainers for any upstream hosting or link |
| Destructive operations | Separate reviewed lifecycle actions, never inferred from file deletion | Project maintainer and deploying platform owner |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Parallel upstream work duplicates effort | Medium | High | Contact maintainers during the specification/local-PoC phase, before fixing public interfaces |
| Bootstrap modules assume platform deployment | Medium | High | Map inputs, permissions, templates, outputs, and state ownership before choosing reuse |
| Engine behavior diverges behind one schema | High | High | Publish capability matrix; compare normalized fixtures; reject unsupported input |
| Migration changes existing subscriptions | Medium | High | Preserve state keys and legacy engine; require explicit migration and preview |
| Broad pipeline privileges bypass intended approval | Medium | High | Separate identity scopes and trust boundaries; approval-bound deployment credentials |
| Bootstrap reruns overwrite consumer changes | Medium | High | Separate bootstrap-owned resources from user-owned files; upgrades through reviewed diffs |
| Maintainer scope becomes unsustainable | Medium | High | Small releases, limited initial matrix, pinned dependencies, and clear support boundaries |
| Removal is mistaken for resource deletion | Medium | High | Explicit lifecycle state machine and engine-specific ownership documentation |

## Success criteria

The first local PoC has the acceptance criteria in the
[delivery plan](subscription-vending-delivery-plan.md). It does not establish
Azure deployability.

Before describing the first preview as deployable:

1. Bootstrap a disposable GitHub vending environment with the selected upstream
   components and preserve its state for recovery.
2. Demonstrate the common contract with each engine in an explicitly authorized
   environment; record exact versions and unsupported combinations.
3. Show that identical inputs do not create another subscription on rerun.
4. Show a reviewed change affects only the intended subscription or affected set.
5. Produce an accurate deployment receipt and recover from a partial failure.
6. Preserve the existing Terraform consumer path.
7. Publish prerequisites, permission boundaries, preview limitations, upgrade
   instructions, support scope, and cost/cleanup responsibilities.

## Related work and coordination

[Azure/Azure-Landing-Zones#420](https://github.com/Azure/Azure-Landing-Zones/issues/420)
is an open request to include subscription vending in the accelerator. A
September 2023 maintainer comment identifies vending as a logical future
extension. It is historical context, not proof of the current roadmap.

[Azure/Subscription-Vending-Machine](https://github.com/Azure/Subscription-Vending-Machine)
is an archived earlier implementation. Current AVM patterns are the resource
foundations; the archived repository is prior art, not the default dependency.

Contact the relevant ALZ and AVM maintainers with this specification and accurate
PoC status. Ask about overlap, compatible bootstrap interfaces, contribution
boundaries, and a future documentation link. Do not wait for a finished product
to establish alignment, and do not assume their endorsement is required to
experiment independently.

## Sources

- [ALZ IaC accelerator](https://azure.github.io/Azure-Landing-Zones/accelerator/)
- [ALZ subscription vending](https://azure.github.io/Azure-Landing-Zones/sub-vending/)
- [Accelerator bootstrap modules](https://github.com/Azure/accelerator-bootstrap-modules)
- [ALZ PowerShell module](https://github.com/Azure/ALZ-PowerShell-Module)
- [Terraform AVM vending pattern](https://github.com/Azure/terraform-azure-avm-ptn-alz-sub-vending)
- [Bicep AVM vending pattern](https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/lz/sub-vending)
