# SubscriptionVending PowerShell module

The `SubscriptionVending` module is the accelerator entry point. It provides a
stable operator interface for selecting and bootstrapping a subscription-vending
starter.

## Current engine support

| Engine | Status | Implementation |
|---|---|---|
| Terraform | Available | Delegates to `bootstrap/Invoke-Bootstrap.ps1` |
| Bicep | Available | Uses the shared bootstrap and deploys through the pinned Bicep AVM |

## Usage

```powershell
Import-Module ./powershell/SubscriptionVending/SubscriptionVending.psd1

Get-SubscriptionVendingEngine
Test-SubscriptionVendingStarter
Initialize-SubscriptionVending -Engine Terraform
Initialize-SubscriptionVending -Engine Bicep
```

Starter availability comes from the versioned manifests under `starters/`.
See [`docs/starter-contract.md`](../../docs/starter-contract.md) for the
required capability baseline.

Run only one Terraform bootstrap phase:

```powershell
Initialize-SubscriptionVending `
  -Engine Terraform `
  -Phase validate `
  -NonInteractive `
  -InputsPath ./bootstrap/.bootstrap-inputs.json
```

Validate an existing configuration:

```powershell
Test-SubscriptionVendingConfiguration `
  -Engine Terraform `
  -InputsPath ./bootstrap/.bootstrap-inputs.json
```

The generated vending repository remains responsible for routine subscription
requests. Operators do not run the PowerShell module for each subscription.
