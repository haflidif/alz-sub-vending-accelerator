@{
  RootModule = 'SubscriptionVending.psm1'
  ModuleVersion = '0.1.0'
  GUID = '6378dcca-c3f5-4f15-a83e-5437d96eac6c'
  Author = 'AzureViking'
  CompanyName = 'Community'
  Copyright = '(c) AzureViking contributors. All rights reserved.'
  Description = 'Bootstrap and maintain an Azure subscription-vending delivery environment.'
  PowerShellVersion = '7.2'
  FunctionsToExport = @(
    'Get-SubscriptionVendingEngine'
    'Initialize-SubscriptionVending'
    'Test-SubscriptionVendingConfiguration'
    'Test-SubscriptionVendingStarter'
  )
  CmdletsToExport = @()
  VariablesToExport = @()
  AliasesToExport = @()
  PrivateData = @{
    PSData = @{
      Tags = @('Azure', 'ALZ', 'SubscriptionVending', 'Terraform', 'Bicep')
      ProjectUri = 'https://github.com/haflidif/alz-sub-vending-terraform-accelerator'
      LicenseUri = 'https://github.com/haflidif/alz-sub-vending-terraform-accelerator/blob/main/LICENSE'
      Prerelease = 'preview'
    }
  }
}
