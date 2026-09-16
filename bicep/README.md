# Bicep subscription-vending starter

This package is the Bicep engine for the subscription-vending accelerator. It
wraps the official Azure Verified Modules pattern
`br/public:avm/ptn/lz/sub-vending:0.8.0` and preserves the repository's existing
YAML subscription contract.

The starter is still marked `Planned`. The template, request compiler, shared
GitHub Actions routing, discovery, and bootstrap platform rendering are in
place. Cloud deployment verification, remaining Terraform parity, and
bootstrap enablement are still required before the starter can be selected.

## Build the template

```powershell
az bicep build --file ./bicep/main.bicep
```

## Compile a request

The compiler combines a YAML request with platform configuration and emits an
ARM deployment parameters file.

```powershell
Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser
Import-Module ./bicep/SubscriptionVending.Bicep.psm1

New-BicepSubscriptionParameters `
  -RequestPath ./landingzones/sandbox/dev-sandbox-platform-001.yaml `
  -PlatformPath ./bicep/platform.json `
  -OutputPath ./bicep/out/dev-sandbox-platform-001.parameters.json
```

For local testing, copy `platform.example.json` to `platform.json` and replace
its placeholders. Bootstrap is prepared to render `platform.json`
automatically when the Bicep starter is enabled.

`platform.json`, compiled request parameters, and generated ARM templates are
ignored locally.

## Current parity boundary

The compiler currently covers subscription creation, management-group
placement, governed tags, billing-scope selection, resource-provider
registration, subscription-scoped role assignments, one requested managed
identity, one spoke virtual network, hub peering, and one subscription budget.

The upstream Bicep AVM accepts one budget threshold type per deployment. This
foundation uses forecast thresholds. Matching the Terraform starter's separate
actual and forecast notifications remains part of the parity work.

The AVM's default resource-provider registration uses an Azure deployment
script and supporting identity, storage, and private networking resources.
Omit `resourceProviders` to keep that full default. Set it to a provider map to
control registration, or `{}` when providers are managed by another platform
process.

The pinned default provider map is stored in
`default-resource-providers.json` so the wrapper remains deterministic for AVM
version 0.8.0.

The wrapper also exposes `existingSubscriptionId` for non-creating validation
and future adoption scenarios. Normal vending leaves it empty and creates a
new subscription alias.

Platform configuration keeps management groups as full resource IDs. The
request compiler passes the final name segment to the AVM because version
0.8.0 currently requires the bare management-group identifier when creating
the subscription association.

## Cloud validation status

The wrapper has been validated at management-group scope against an existing
subscription in an ALZ hierarchy, using `existingSubscriptionId` so no
subscription alias was created.

Cloud validation found and fixed two issues that were not visible during
offline compilation:

- Disabled networking must pass a null VNet name to the upstream module.
- Management-group resource IDs must be normalized to their final name
  segment before association.

The final what-if with platform-managed provider registration produced only
the expected management-group association, subscription tag, and budget
operations. No deployment was applied.
