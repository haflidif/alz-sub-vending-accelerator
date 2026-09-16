# Subscription-vending delivery plan

> Status: Extended roadmap, not the current delivery sequence.
> Scope decision, 2026-09-16: first deliver the PowerShell bootstrap module and
> equivalent Terraform and Bicep vending starters. Broader workload onboarding
> remains optional future work. The current implementation contract is
> documented in [starter-contract.md](../starter-contract.md).

## Delivery principle

Build a maintained accelerator through small, evidence-based releases.
The PoC establishes the reusable foundation; it is not the product's scope.
Do not turn every roadmap feature into a dependency of the first preview.

No phase authorizes creating Azure resources, sending external messages,
publishing packages, or pushing changes without the relevant operator approval.

## Customer suitability and adoption

The product ambition is a standard configuration-driven path suitable for 95%
of customers with subscription-vending needs. The local PoC and first preview
do not establish that level of coverage.

During M0, define the target customer population and a representative scenario
inventory covering billing agreements, existing platforms, repository providers,
IaC engines, networking, access controls, and lifecycle requirements. Do not
equate a count of implemented features with a percentage of customers served.

During pilots, classify each customer's required workflow as supported by
configuration, requiring an extension, requiring a fork/core change, or blocked.
Record the complete workflow, including onboarding and maintenance, rather than
only whether the initial deployment succeeds. Prioritize repeated gaps over
one-off customization.

Report sample size, selection method, exclusions, and outcomes before claiming
a coverage percentage. Keep actual adoption separate from suitability; collect
feedback or usage evidence only with an explicit, privacy-appropriate approach.
No new customer telemetry is implied by this specification.

The 95% goal guides the roadmap, not a promise that every preview already meets
it or a reason to build all features before delivering the first useful release.

## Milestones

| Milestone | Deliverable | Exit condition |
|---|---|---|
| M0: Specification and alignment | Product scope, reuse inventory, PoC contract, and maintainer discussion | Record architectural decisions and known overlap; identify a bounded first implementation |
| M1: Local foundation PoC | Thin PowerShell entry point, contract fixtures, starter adapters, local rendering | Pass the local acceptance cases below without cloud mutations |
| M2: Bootstrap integration | Proven consumption/adaptation of upstream bootstrap components | Establish one disposable GitHub delivery environment with documented ownership and recovery |
| M3: Dual-engine preview | Real Terraform and Bicep vending with a declared common feature set | Demonstrate creation, safe rerun, change, failure recovery, and handoff for each engine |
| M4: Operational lifecycle | Adoption, drift reporting, controlled detach/retirement, sandbox renewal | Document and exercise non-destructive and destructive paths separately |
| M5: Broader adoption | Azure DevOps, connectivity profiles, IPAM/vWAN as prioritized | Publish provider/engine matrix, upgrade procedure, and support boundaries |

M1 depends on the proposed contracts in M0, not on upstream endorsement.
M2 depends on the bootstrap reuse findings in M1. M3 depends on M1 and M2.
M4 and M5 are later product milestones, not requirements for the local PoC.
Collect upstream feedback during M0/M1, before substantial bootstrap integration.

## M1: Local foundation PoC

### Purpose

Demonstrate one subscription request model and two engine-specific starters
without recreating ALZ's orchestration internals or changing the existing
Terraform entry point.

### Proposed development layout

These paths are planned and do not yet exist:

```text
powershell/
  SubscriptionVending/
    SubscriptionVending.psd1
    SubscriptionVending.psm1
    Public/
    Private/
schemas/
  bootstrap.schema.json
  platform.schema.json
  subscription.schema.json
starters/
  terraform/
  bicep/
tests/
  fixtures/
```

Use this repository initially. Do not split into multiple repositories or
publish a package before the interfaces stabilize. Generated vending repositories
must contain only their runtime starter, relevant configuration, and operator
documentation, not accelerator development notes or outreach drafts.

### Minimal interfaces

Names are provisional; no commands are advertised as installed or available.

| Boundary | Input | Output |
|---|---|---|
| Configuration validation | Bootstrap/platform/request documents and schema versions | Structured validation result with errors tied to source fields |
| Shared resolution | Validated documents | Normalized request with effective governance and stable request identity |
| Starter rendering | Normalized request, engine, and pinned starter manifest | Engine-specific configuration in a new local output directory |
| Bootstrap preparation | Validated bootstrap config and chosen upstream adapter | Proposed inputs and ownership manifest; no apply during the local PoC |

Separate explicit dependency retrieval from offline rendering. Once dependencies
are present, local fixture rendering must not require Azure or GitHub credentials.
Remote resource checks belong to a separate preflight mode, not offline validation.

The manifest records contract/starter versions, exact AVM dependencies, supported
capabilities, repository provider, and generated-file ownership. Pin dependencies
only after choosing actual published releases.

### First fixture set

Start with an isolated sandbox request: stable request identity, location,
business owner, application environment, billing offer, tags, management-group
selection, and a mandatory budget. No networking is required for the first
fixture. Add access and optional networking only when their mappings are explicit.

Use non-sensitive placeholders. Do not reuse real tenant or billing identifiers
from an operator workstation.

Provide one current-format request fixture to demonstrate the legacy Terraform
compatibility boundary. Current filenames/state keys must remain unchanged.

### Local acceptance cases

| ID | Scenario | Expected result |
|---|---|---|
| P01 | Render the same normalized request with each engine | Equivalent governed intent; engine-specific parameters are explicit |
| P02 | Render identical input twice | Identical configuration content; no timestamp-driven input drift |
| P03 | Required owner, location, or sandbox budget is missing | Field-specific failure before rendering |
| P04 | Request hub connectivity for a forbidden profile | Explicit rejection, not a silently modified request |
| P05 | Request a capability unsupported by the chosen adapter | Explicit capability error |
| P06 | Use unknown schema or starter versions | Reject with supported-version guidance |
| P07 | Render into a directory containing user-owned files | Refuse overwrite; leave those files unchanged |
| P08 | Load an existing Terraform contract fixture | Preserve legacy behavior and state identity; report required migration separately |
| P09 | Run offline fixture rendering | No credential prompt, provider login, API mutation, or deployment |
| P10 | Generate a Bicep starter and Terraform starter | Each contains a real pinned upstream module reference, not a success-only placeholder |
| P11 | Supply malformed nested access/network data | Reject at the shared boundary before module invocation |
| P12 | Attempt to change engine ownership for an existing request | Reject normal update and require a separate migration procedure |

Local syntax/build validation can establish that templates are structurally
usable, not that billing permissions, Azure Policy, provider registration,
deployment scripts, or runtime resource ownership work.

Do not call M1 complete with only a module manifest and empty public functions.
It must render the declared fixture through both adapters. If an upstream input
cannot be mapped, record the missing capability rather than inventing parity.

## Bootstrap reuse investigation

Before implementing M2, record an interface-level decision for each component:

| Concern | Questions to resolve |
|---|---|
| Repository setup | Can the upstream module seed a custom vending starter without platform-only files or assumptions? |
| Workflow setup | Can preview/apply workflows use a per-request matrix and stable required checks? |
| Identity and permissions | Which resources can be reused, and where are billing, target-MG, hub, and existing-subscription permissions different? |
| State | Where is bootstrap state retained, and when is per-subscription Terraform state provisioned? |
| Configuration | Which upstream settings are public inputs versus private PowerShell implementation details? |
| Outputs | Can our wrapper consume documented outputs without parsing console text? |
| Ownership | Which repository files and cloud resources remain managed after initial setup? |
| Upgrades | How do pinned upstream upgrades preserve operator edits and permit rollback? |
| Provider support | Which abstractions are reusable for GitHub now and Azure DevOps later? |

For each result choose `consume`, `adapt`, or `implement`, include a source/release,
and explain the reason. Do not fork a component merely because its name contains
ALZ. Do not claim compatibility solely because both projects use Terraform.

## Production gaps to close before M3

These findings are from the existing implementation, not an instruction to
change the current production path during M1:

- Shared Terraform/archetype edits do not select affected subscriptions in
  `.github/scripts/discover-subs.sh`.
- The PR result gate does not explicitly require successful discovery.
- Sandbox peering defaults to off but is not forbidden by the archetype logic.
- Bootstrap does not require CODEOWNER reviews despite the documented workflow.
- Budget start dates derive from the current timestamp.
- The environment tag conflates application environment with billing offer.
- Contract deletion, rename, retirement, and detach need distinct treatment.
- The detach runbook must not describe applying after state removal as a no-op.
- Bootstrap-managed seed files need a safe day-two ownership transition.

Address these through small focused changes and corresponding regression cases,
not an unrelated broad rewrite.

## Release and maintenance framework

Maintain separate version identities for the accelerator package, contract,
starter, and upstream modules. Publish a compatibility matrix instead of
assuming any newest version combination works.

Each release must state its support level, prerequisites, capability changes,
migration requirements, and known limitations. Generated repositories need a
record of their source release and a reviewable update process.

Use local checks for frequent iterations. Reserve Azure end-to-end exercises
for explicitly approved milestones with a named environment, spending limits,
and a cleanup plan. Batch CI changes rather than using repeated deployment runs
to discover basic contract errors.

Before a public preview, define maintainer responsibilities, contribution
guidance, issue triage, security reporting, dependency update policy, and
supported repository-provider/engine combinations.

### Eventual Azure organization hosting

The preferred long-term direction is to move from personal or AzureViking
incubation to the GitHub `Azure` organization, subject to acceptance.
Discuss this during early coordination rather than assuming a transfer is
available once the code is finished.

Before any move, agree the destination owner, maintainers, support model,
licensing/contribution requirements, runner access, and responsibility for
Azure end-to-end costs. Repository location alone does not guarantee additional
Actions capacity. Public repositories already receive free standard
GitHub-hosted runner minutes under
[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Prepare a migration checklist covering repository URLs, release/package
references, documentation links, Actions policies and environments, secrets and
variables, and OIDC subjects that include the repository owner/name. Review
bootstrap state and generated consumer configuration for old repository
references. Do not automatically recreate or transfer consumer vending repos.
Perform any transfer only after explicit approval and a recovery plan.

## Maintainer coordination

Share the project specification and describe M1 as planned until it actually
works. Reference
[Azure/Azure-Landing-Zones#420](https://github.com/Azure/Azure-Landing-Zones/issues/420)
and ask whether current or planned work overlaps.

Ask for input on reuse boundaries, not approval of an already finished design.
The project maintainer retains implementation ownership unless a different
arrangement is explicitly agreed. A future ALZ documentation link is a separate
maintainer decision and must not be represented as promised.
