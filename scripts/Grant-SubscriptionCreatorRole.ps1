#Requires -Version 7.2
<#
.SYNOPSIS
    Grants the Azure Billing SubscriptionCreator role to a service principal.

.DESCRIPTION
    Validates the Azure CLI session, billing scope, and service principal,
    then creates the billing role assignment through the Azure Billing REST
    API. The script supports Enterprise Agreement (EA), Microsoft Customer
    Agreement (MCA), and an explicit billing resource ID for other supported
    billing scopes.

    This implementation follows the ALZ PowerShell module helper while fixing
    MCA parameter detection, explicit billing-scope parameter binding, native
    JSON argument handling, and repeat execution.

.EXAMPLE
    ./scripts/Grant-SubscriptionCreatorRole.ps1 `
      -servicePrincipalObjectId '00000000-0000-0000-0000-000000000000' `
      -billingAccountID '1234567' `
      -enrollmentAccountID '987654'

.EXAMPLE
    ./scripts/Grant-SubscriptionCreatorRole.ps1 `
      -servicePrincipalObjectId '00000000-0000-0000-0000-000000000000' `
      -billingAccountID '<MCA billing account name>' `
      -billingProfileID '<billing profile name>' `
      -invoiceSectionID '<invoice section name>'

.EXAMPLE
    ./scripts/Grant-SubscriptionCreatorRole.ps1 `
      -servicePrincipalObjectId '00000000-0000-0000-0000-000000000000' `
      -billingResourceID '/providers/Microsoft.Billing/billingAccounts/<account>/customers/<customer>'
#>
[CmdletBinding(DefaultParameterSetName = 'EA', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $servicePrincipalObjectId,

    [Parameter(Mandatory = $true, ParameterSetName = 'EA', Position = 1)]
    [Parameter(Mandatory = $true, ParameterSetName = 'MCA', Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string] $billingAccountID,

    [Parameter(Mandatory = $true, ParameterSetName = 'EA', Position = 2)]
    [ValidateNotNullOrEmpty()]
    [string] $enrollmentAccountID,

    [Parameter(Mandatory = $true, ParameterSetName = 'MCA', Position = 2)]
    [ValidateNotNullOrEmpty()]
    [string] $billingProfileID,

    [Parameter(Mandatory = $true, ParameterSetName = 'MCA', Position = 3)]
    [ValidateNotNullOrEmpty()]
    [string] $invoiceSectionID,

    [Parameter(Mandatory = $true, ParameterSetName = 'Advanced', Position = 1)]
    [ValidatePattern('^/providers/Microsoft\.Billing/billingAccounts/[^/]+/.+$')]
    [string] $billingResourceID,

    [ValidateNotNullOrEmpty()]
    [string] $managementApiPrefix = 'https://management.azure.com'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$subscriptionCreatorRoleId = 'a0bcee42-bf30-4d1b-926a-48d21664ef71'
$apiVersion = '2024-04-01'

function Invoke-AzCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [switch] $AllowEmpty
    )

    $output = @(& az @Arguments 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        $detail = ($output -join [Environment]::NewLine).Trim()
        if (-not $detail) {
            $detail = "Azure CLI exited with code $LASTEXITCODE."
        }
        throw "Azure CLI command failed: $detail"
    }

    $text = ($output -join [Environment]::NewLine).Trim()
    if (-not $AllowEmpty -and -not $text) {
        throw 'Azure CLI returned an empty response.'
    }
    return $text
}

function Invoke-AzJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $text = Invoke-AzCli -Arguments $Arguments
    try {
        return $text | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Azure CLI returned invalid JSON: $($_.Exception.Message)"
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI command 'az' was not found."
}

$principalGuid = [guid]::Empty
if (-not [guid]::TryParse($servicePrincipalObjectId, [ref] $principalGuid)) {
    throw "servicePrincipalObjectId must be a GUID. Received '$servicePrincipalObjectId'."
}

switch ($PSCmdlet.ParameterSetName) {
    'EA' {
        $billingResourceID = "/providers/Microsoft.Billing/billingAccounts/$billingAccountID/enrollmentAccounts/$enrollmentAccountID"
        $agreementType = 'EA'
    }
    'MCA' {
        $billingResourceID = "/providers/Microsoft.Billing/billingAccounts/$billingAccountID/billingProfiles/$billingProfileID/invoiceSections/$invoiceSectionID"
        $agreementType = 'MCA'
    }
    'Advanced' {
        $billingResourceID = $billingResourceID.TrimEnd('/')
        $agreementType = 'Explicit'
    }
}

$managementApiPrefix = $managementApiPrefix.TrimEnd('/')
$tenantId = Invoke-AzCli -Arguments @(
    'account', 'show',
    '--query', 'tenantId',
    '--output', 'tsv',
    '--only-show-errors'
)

$servicePrincipal = Invoke-AzJson -Arguments @(
    'ad', 'sp', 'show',
    '--id', $servicePrincipalObjectId,
    '--output', 'json',
    '--only-show-errors'
)

$scopeUrl = "$managementApiPrefix$billingResourceID"
$null = Invoke-AzJson -Arguments @(
    'rest',
    '--method', 'GET',
    '--url', "$scopeUrl`?api-version=$apiVersion",
    '--output', 'json',
    '--only-show-errors'
)

$roleDefinitionId = "$billingResourceID/billingRoleDefinitions/$subscriptionCreatorRoleId"
$assignments = Invoke-AzJson -Arguments @(
    'rest',
    '--method', 'GET',
    '--url', "$scopeUrl/billingRoleAssignments?api-version=$apiVersion",
    '--output', 'json',
    '--only-show-errors'
)

$existingAssignment = @($assignments.value) |
    Where-Object {
        $assignmentRoleDefinitionId = "$($_.properties.roleDefinitionId)".TrimEnd('/')
        $_.properties.principalId -eq $servicePrincipalObjectId -and
        $assignmentRoleDefinitionId -eq $roleDefinitionId
    } |
    Select-Object -First 1

if ($existingAssignment) {
    [pscustomobject]@{
        Status                   = 'AlreadyAssigned'
        AgreementType            = $agreementType
        BillingScope             = $billingResourceID
        PrincipalId              = $servicePrincipalObjectId
        PrincipalDisplayName     = $servicePrincipal.displayName
        PrincipalTenantId        = $tenantId
        RoleDefinitionId         = $roleDefinitionId
        BillingRoleAssignmentId  = $existingAssignment.id
    }
    return
}

$assignmentName = [guid]::NewGuid().ToString()
$assignmentUrl = "$scopeUrl/billingRoleAssignments/$assignmentName`?api-version=$apiVersion"
$target = "$($servicePrincipal.displayName) ($servicePrincipalObjectId) at $billingResourceID"

if (-not $PSCmdlet.ShouldProcess($target, 'Grant Azure Billing SubscriptionCreator role')) {
    [pscustomobject]@{
        Status                   = 'WhatIf'
        AgreementType            = $agreementType
        BillingScope             = $billingResourceID
        PrincipalId              = $servicePrincipalObjectId
        PrincipalDisplayName     = $servicePrincipal.displayName
        PrincipalTenantId        = $tenantId
        RoleDefinitionId         = $roleDefinitionId
        BillingRoleAssignmentId  = $null
    }
    return
}

$payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) "subscription-creator-$assignmentName.json"
try {
    @{
        properties = @{
            principalId       = $servicePrincipalObjectId
            roleDefinitionId  = $roleDefinitionId
            principalTenantId = $tenantId
        }
    } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $payloadPath -Encoding utf8NoBOM

    $createdAssignment = Invoke-AzJson -Arguments @(
        'rest',
        '--method', 'PUT',
        '--url', $assignmentUrl,
        '--headers', 'Content-Type=application/json',
        '--body', "@$payloadPath",
        '--output', 'json',
        '--only-show-errors'
    )
}
finally {
    Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    Status                   = 'Created'
    AgreementType            = $agreementType
    BillingScope             = $billingResourceID
    PrincipalId              = $servicePrincipalObjectId
    PrincipalDisplayName     = $servicePrincipal.displayName
    PrincipalTenantId        = $tenantId
    RoleDefinitionId         = $roleDefinitionId
    BillingRoleAssignmentId  = $createdAssignment.id
}
