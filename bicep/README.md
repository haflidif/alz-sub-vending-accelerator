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
