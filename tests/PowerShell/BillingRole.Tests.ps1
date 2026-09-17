#Requires -Version 7.2

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repositoryRoot 'scripts/Grant-SubscriptionCreatorRole.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "billing-role-tests-$([guid]::NewGuid())"
$fakeAzPath = Join-Path $testRoot 'az.ps1'
$logPath = Join-Path $testRoot 'az-calls.jsonl'
$bodyPath = Join-Path $testRoot 'request-body.json'
$principalId = 'e7dd5a57-4a9f-4a59-9371-2e588a7637f4'
$tenantId = 'dac8feee-8768-4fbd-9cf9-9d96d4718018'
$roleId = 'a0bcee42-bf30-4d1b-926a-48d21664ef71'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] $Actual,
        [Parameter(Mandatory = $true)] [string] $Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throw {
    param(
        [Parameter(Mandatory = $true)] [scriptblock] $Script,
        [Parameter(Mandatory = $true)] [string] $MessagePattern
    )

    try {
        & $Script
    }
    catch {
        if ($_.Exception.Message -notlike $MessagePattern) {
            throw "Expected error matching '$MessagePattern', got '$($_.Exception.Message)'."
        }
        return
    }
    throw "Expected error matching '$MessagePattern', but no error was thrown."
}

function Invoke-BillingRoleTest {
    param([hashtable] $Parameters)

    $result = @(& $scriptPath @Parameters -Confirm:$false)
    return $result | Where-Object { $_.PSObject.Properties.Name -contains 'Status' } | Select-Object -Last 1
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    @'
$arguments = @($args)
$logEntry = ($arguments | ConvertTo-Json -Compress) + [Environment]::NewLine
[System.IO.File]::AppendAllText($env:BILLING_ROLE_TEST_LOG, $logEntry)

if ($arguments[0] -eq 'account' -and $arguments[1] -eq 'show') {
    $env:BILLING_ROLE_TEST_TENANT
    exit 0
}

if ($arguments[0] -eq 'ad' -and $arguments[1] -eq 'sp') {
    @{
        id = $env:BILLING_ROLE_TEST_PRINCIPAL
        displayName = 'id-subscription-vending'
        servicePrincipalType = 'ManagedIdentity'
    } | ConvertTo-Json -Compress
    exit 0
}

if ($arguments[0] -eq 'rest') {
    $method = $arguments[[array]::IndexOf($arguments, '--method') + 1]
    $url = $arguments[[array]::IndexOf($arguments, '--url') + 1]

    if ($method -eq 'GET' -and $url -match '/billingRoleAssignments\?') {
        if ($env:BILLING_ROLE_TEST_EXISTING -eq 'true') {
            @{
                value = @(
                    @{
                        id = "$env:BILLING_ROLE_TEST_SCOPE/billingRoleAssignments/existing"
                        properties = @{
                            principalId = $env:BILLING_ROLE_TEST_PRINCIPAL
                            roleDefinitionId = "$env:BILLING_ROLE_TEST_SCOPE/billingRoleDefinitions/$env:BILLING_ROLE_TEST_ROLE"
                        }
                    }
                )
            } | ConvertTo-Json -Depth 6 -Compress
        }
        else {
            @{ value = @() } | ConvertTo-Json -Compress
        }
        exit 0
    }

    if ($method -eq 'GET') {
        @{ id = $url.Split('?')[0]; properties = @{} } | ConvertTo-Json -Compress
        exit 0
    }

    if ($method -eq 'PUT') {
        $bodyArgument = $arguments[[array]::IndexOf($arguments, '--body') + 1]
        Copy-Item -LiteralPath $bodyArgument.Substring(1) -Destination $env:BILLING_ROLE_TEST_BODY -Force
        @{ id = $url.Split('?')[0] } | ConvertTo-Json -Compress
        exit 0
    }
}

Write-Error "Unexpected az arguments: $($arguments -join ' ')"
exit 1
'@ | Set-Content -LiteralPath $fakeAzPath

    Set-Alias -Name az -Value $fakeAzPath -Scope Global
    $env:BILLING_ROLE_TEST_LOG = $logPath
    $env:BILLING_ROLE_TEST_BODY = $bodyPath
    $env:BILLING_ROLE_TEST_PRINCIPAL = $principalId
    $env:BILLING_ROLE_TEST_TENANT = $tenantId
    $env:BILLING_ROLE_TEST_ROLE = $roleId
    $env:BILLING_ROLE_TEST_EXISTING = 'false'

    Assert-Throw `
        -Script {
            & $scriptPath `
                -servicePrincipalObjectId 'not-a-guid' `
                -billingAccountID '7690848' `
                -enrollmentAccountID '403507'
        } `
        -MessagePattern "*servicePrincipalObjectId must be a GUID*"

    $eaScope = '/providers/Microsoft.Billing/billingAccounts/7690848/enrollmentAccounts/403507'
    $env:BILLING_ROLE_TEST_SCOPE = $eaScope
    $eaResult = Invoke-BillingRoleTest -Parameters @{
        servicePrincipalObjectId = $principalId
        billingAccountID = '7690848'
        enrollmentAccountID = '403507'
    }
    Assert-Equal 'Created' $eaResult.Status 'EA assignment status is incorrect.'
    Assert-Equal 'EA' $eaResult.AgreementType 'EA agreement detection is incorrect.'
    Assert-Equal $eaScope $eaResult.BillingScope 'EA scope construction is incorrect.'
    $eaBody = Get-Content -LiteralPath $bodyPath -Raw | ConvertFrom-Json
    Assert-Equal $principalId $eaBody.properties.principalId 'EA payload principal is incorrect.'
    Assert-Equal "$eaScope/billingRoleDefinitions/$roleId" $eaBody.properties.roleDefinitionId 'EA role definition is incorrect.'
    Assert-Equal $tenantId $eaBody.properties.principalTenantId 'EA payload tenant is incorrect.'

    $mcaScope = '/providers/Microsoft.Billing/billingAccounts/account-1/billingProfiles/profile-1/invoiceSections/section-1'
    $env:BILLING_ROLE_TEST_SCOPE = $mcaScope
    $mcaResult = Invoke-BillingRoleTest -Parameters @{
        servicePrincipalObjectId = $principalId
        billingAccountID = 'account-1'
        billingProfileID = 'profile-1'
        invoiceSectionID = 'section-1'
    }
    Assert-Equal 'Created' $mcaResult.Status 'MCA assignment status is incorrect.'
    Assert-Equal 'MCA' $mcaResult.AgreementType 'MCA agreement detection is incorrect.'
    Assert-Equal $mcaScope $mcaResult.BillingScope 'MCA scope construction is incorrect.'

    $mpaScope = '/providers/Microsoft.Billing/billingAccounts/partner-1/customers/customer-1'
    $env:BILLING_ROLE_TEST_SCOPE = $mpaScope
    $advancedResult = Invoke-BillingRoleTest -Parameters @{
        servicePrincipalObjectId = $principalId
        billingResourceID = $mpaScope
    }
    Assert-Equal 'Created' $advancedResult.Status 'Explicit scope assignment status is incorrect.'
    Assert-Equal 'Explicit' $advancedResult.AgreementType 'Explicit scope detection is incorrect.'
    Assert-Equal $mpaScope $advancedResult.BillingScope 'Explicit scope was changed.'

    $env:BILLING_ROLE_TEST_SCOPE = $mcaScope
    $env:BILLING_ROLE_TEST_EXISTING = 'true'
    Clear-Content -LiteralPath $logPath
    $existingResult = Invoke-BillingRoleTest -Parameters @{
        servicePrincipalObjectId = $principalId
        billingAccountID = 'account-1'
        billingProfileID = 'profile-1'
        invoiceSectionID = 'section-1'
    }
    Assert-Equal 'AlreadyAssigned' $existingResult.Status 'Existing assignments must be reused.'
    $existingCalls = Get-Content -LiteralPath $logPath
    Assert-Equal 0 @($existingCalls | Where-Object { $_ -match '"PUT"' }).Count 'Existing assignment lookup must skip PUT.'

    $env:BILLING_ROLE_TEST_EXISTING = 'false'
    Clear-Content -LiteralPath $logPath
    $whatIfResult = @(
        & $scriptPath `
            -servicePrincipalObjectId $principalId `
            -billingAccountID '7690848' `
            -enrollmentAccountID '403507' `
            -WhatIf
    ) | Where-Object { $_.PSObject.Properties.Name -contains 'Status' } | Select-Object -Last 1
    Assert-Equal 'WhatIf' $whatIfResult.Status 'WhatIf must report a preview result.'
    $whatIfCalls = Get-Content -LiteralPath $logPath
    Assert-Equal 4 @($whatIfCalls).Count 'WhatIf must perform the four read-only validation calls.'
    Assert-Equal 0 @($whatIfCalls | Where-Object { $_ -match '"PUT"' }).Count 'WhatIf must not create an assignment.'

    Write-Output 'Billing role helper tests passed.'
}
finally {
    Remove-Item Alias:az -Force -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_BODY -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_PRINCIPAL -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_TENANT -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_ROLE -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_SCOPE -ErrorAction SilentlyContinue
    Remove-Item Env:BILLING_ROLE_TEST_EXISTING -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
