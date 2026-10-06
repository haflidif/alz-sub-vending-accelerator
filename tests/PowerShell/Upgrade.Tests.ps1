#Requires -Version 7.2

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$upgradeScript = Join-Path $repositoryRoot 'scripts/Update-SubscriptionVending.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "subscription-vending-upgrade-tests-$([guid]::NewGuid())"

function Assert-Equal {
  param(
    [Parameter(Mandatory)] $Expected,
    [Parameter(Mandatory)] $Actual,
    [Parameter(Mandatory)][string] $Message
  )

  if ($Expected -ne $Actual) {
    throw "$Message Expected '$Expected', got '$Actual'."
  }
}

function Assert-Throws {
  param(
    [Parameter(Mandatory)][scriptblock] $Script,
    [Parameter(Mandatory)][string] $MessagePattern
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

function Set-TestFile {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $RelativePath,
    [Parameter(Mandatory)][string] $Value
  )

  $path = Join-Path $Root $RelativePath
  $parent = Split-Path -Parent $path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  Set-Content -LiteralPath $path -Value $Value -Encoding utf8NoBOM
}

function Get-TestManagedHash {
  param([Parameter(Mandatory)][string] $Path)

  $content = [System.IO.File]::ReadAllText($Path)
  $normalized = $content.Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
  [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Invoke-TestGit {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string[]] $Arguments
  )

  Push-Location -LiteralPath $Root
  try {
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Git command failed: git $($Arguments -join ' ')"
    }
  }
  finally {
    Pop-Location
  }
}

function New-TestManifest {
  param([Parameter(Mandatory)][string] $Root)

  @{
    schemaVersion = '1.0'
    common = @{
      includeFiles = @('README.md')
      includePrefixes = @('.github/', 'scripts/')
      excludeFiles = @()
      excludePrefixes = @()
      excludePatterns = @('(^|/)\.terraform/')
    }
    engines = @{
      terraform = @{
        includePrefixes = @('terraform/')
        excludeFiles = @('terraform/terraform.auto.tfvars')
        excludePrefixes = @()
        excludePatterns = @()
      }
      bicep = @{
        includePrefixes = @('bicep/')
        excludeFiles = @('bicep/platform.json')
        excludePrefixes = @('bicep/out/')
        excludePatterns = @()
      }
    }
  } |
    ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $Root 'upgrade-manifest.json') -Encoding utf8NoBOM
}

function New-SourceFixture {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $Version,
    [Parameter(Mandatory)][string] $Label,
    [string] $Repository = 'example/accelerator'
  )

  New-Item -ItemType Directory -Path $Root -Force | Out-Null
  New-TestManifest -Root $Root
  @{
    schemaVersion = '1.0'
    version = $Version
    repository = $Repository
  } |
    ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $Root 'accelerator.json') -Encoding utf8NoBOM
  Set-TestFile -Root $Root -RelativePath 'README.md' -Value "$Label readme"
  Set-TestFile -Root $Root -RelativePath '.github/workflows/apply.yml' -Value "name: $Label"
  Set-TestFile -Root $Root -RelativePath '.github/dependabot.yml' -Value 'version: 2'
  Set-TestFile -Root $Root -RelativePath 'scripts/helper.ps1' -Value "Write-Output '$Label'"
  Set-TestFile -Root $Root -RelativePath 'terraform/main.tf' -Value "# $Label terraform"
  Set-TestFile -Root $Root -RelativePath 'bicep/main.bicep' -Value "// $Label bicep"
}

function New-GeneratedRepository {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][ValidateSet('terraform', 'bicep')][string] $Engine,
    [string] $SourceRepository = 'example/accelerator',
    [switch] $WithMetadata
  )

  New-Item -ItemType Directory -Path $Root -Force | Out-Null
  $managedPaths = [System.Collections.Generic.List[string]]::new()
  foreach ($relativePath in @('README.md')) {
    Copy-Item -LiteralPath (Join-Path $SourceRoot $relativePath) -Destination (Join-Path $Root $relativePath)
    $managedPaths.Add($relativePath)
  }
  foreach ($prefix in @('.github', 'scripts', $Engine)) {
    $sourceDirectory = Join-Path $SourceRoot $prefix
    $destinationDirectory = Join-Path $Root $prefix
    Copy-Item -LiteralPath $sourceDirectory -Destination $destinationDirectory -Recurse
    foreach ($file in Get-ChildItem -LiteralPath $destinationDirectory -File -Recurse) {
      $managedPaths.Add([System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/'))
    }
  }
  Set-TestFile -Root $Root -RelativePath 'landingzones/corp/request.yaml' -Value 'repository-owned request'
  Set-TestFile -Root $Root -RelativePath '.github/CODEOWNERS' -Value '* @platform'
  Set-TestFile -Root $Root -RelativePath 'docs/local-runbook.md' -Value 'repository-owned documentation'
  if ($Engine -eq 'terraform') {
    Set-TestFile -Root $Root -RelativePath 'terraform/terraform.auto.tfvars' -Value 'tenant_id = "preserve"'
  }
  else {
    Set-TestFile -Root $Root -RelativePath 'bicep/platform.json' -Value '{"preserve":true}'
  }
  if ($WithMetadata) {
    New-Item -ItemType Directory -Path (Join-Path $Root '.accelerator') -Force | Out-Null
    $managedFiles = [ordered]@{}
    foreach ($relativePath in @($managedPaths | Sort-Object -Unique)) {
      $managedFiles[$relativePath] = Get-TestManagedHash -Path (Join-Path $Root $relativePath)
    }
    [ordered]@{
      schemaVersion = '1.0'
      sourceRepository = $SourceRepository
      acceleratorVersion = 'v1.0.0'
      starter = $Engine
      managedFiles = $managedFiles
    } |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath (Join-Path $Root '.accelerator/metadata.json') -Encoding utf8NoBOM
  }

  Invoke-TestGit -Root $Root -Arguments @('init', '-q')
  Invoke-TestGit -Root $Root -Arguments @('config', 'user.email', 'test@example.com')
  Invoke-TestGit -Root $Root -Arguments @('config', 'user.name', 'Upgrade Test')
  Invoke-TestGit -Root $Root -Arguments @('config', 'commit.gpgsign', 'false')
  Invoke-TestGit -Root $Root -Arguments @('config', 'core.autocrlf', 'false')
  Invoke-TestGit -Root $Root -Arguments @('add', '.')
  Invoke-TestGit -Root $Root -Arguments @('commit', '-qm', 'Initial generated repository')
}

try {
  $currentRoot = Join-Path $testRoot 'source-current'
  $targetRoot = Join-Path $testRoot 'source-target'
  New-SourceFixture -Root $currentRoot -Version 'v1.0.0' -Label 'current'
  New-SourceFixture -Root $targetRoot -Version 'v1.1.0' -Label 'target'
  Set-TestFile -Root $currentRoot -RelativePath 'terraform/removed.tf' -Value '# remove me'
  Set-TestFile -Root $targetRoot -RelativePath 'terraform/added.tf' -Value '# add me'
  Set-TestFile -Root $currentRoot -RelativePath 'bicep/removed.bicep' -Value '// remove me'
  Set-TestFile -Root $targetRoot -RelativePath 'bicep/added.bicep' -Value '// add me'

  $legacyCurrentRoot = Join-Path $testRoot 'source-legacy-current'
  $renamedTargetRoot = Join-Path $testRoot 'source-renamed-target'
  New-SourceFixture `
    -Root $legacyCurrentRoot `
    -Version 'v1.0.0' `
    -Label 'legacy-current' `
    -Repository 'haflidif/alz-sub-vending-terraform-accelerator'
  New-SourceFixture `
    -Root $renamedTargetRoot `
    -Version 'v1.1.0' `
    -Label 'renamed-target' `
    -Repository 'haflidif/alz-sub-vending-accelerator'

  $renamedRepository = Join-Path $testRoot 'renamed-repository'
  New-GeneratedRepository `
    -Root $renamedRepository `
    -SourceRoot $legacyCurrentRoot `
    -Engine terraform `
    -SourceRepository 'haflidif/alz-sub-vending-terraform-accelerator' `
    -WithMetadata
  & $upgradeScript `
    -RepositoryRoot $renamedRepository `
    -TargetVersion v1.1.0 `
    -CurrentSourceRoot $legacyCurrentRoot `
    -TargetSourceRoot $renamedTargetRoot `
    -Apply `
    -NoBranch
  $renamedMetadata = Get-Content `
    -LiteralPath (Join-Path $renamedRepository '.accelerator/metadata.json') `
    -Raw |
    ConvertFrom-Json
  Assert-Equal `
    'haflidif/alz-sub-vending-accelerator' `
    $renamedMetadata.sourceRepository `
    'Legacy repository metadata was not migrated to the canonical repository name.'

  $terraformRepo = Join-Path $testRoot 'terraform-repo'
  New-GeneratedRepository -Root $terraformRepo -SourceRoot $currentRoot -Engine terraform -WithMetadata
  $readmePath = Join-Path $terraformRepo 'README.md'
  $readmeContent = [System.IO.File]::ReadAllText($readmePath).Replace("`r`n", "`n")
  [System.IO.File]::WriteAllText($readmePath, $readmeContent.Replace("`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))
  Set-TestFile -Root $terraformRepo -RelativePath '.github/dependabot.yml' -Value 'version: 2 # local cadence'
  Invoke-TestGit -Root $terraformRepo -Arguments @('add', '.')
  Invoke-TestGit -Root $terraformRepo -Arguments @('commit', '-qm', 'Customize unchanged managed file')

  $preview = & $upgradeScript `
    -RepositoryRoot $terraformRepo `
    -TargetVersion v1.1.0 `
    -CurrentSourceRoot $currentRoot `
    -TargetSourceRoot $targetRoot 6>&1 | Out-String
  Assert-Equal $true ($preview -match '\[UPDATE\] terraform/main\.tf') 'Preview must report engine updates.'
  Assert-Equal $true ($preview -match '\[ADD\] terraform/added\.tf') 'Preview must report additions.'
  Assert-Equal $true ($preview -match '\[REMOVE\] terraform/removed\.tf') 'Preview must report removals.'
  Assert-Equal '# current terraform' ((Get-Content -LiteralPath (Join-Path $terraformRepo 'terraform/main.tf') -Raw).Trim()) 'Preview changed a managed file.'
  Assert-Throws `
    -Script {
      & $upgradeScript `
        -RepositoryRoot $terraformRepo `
        -TargetVersion v1.1.0 `
        -CurrentSourceRoot $currentRoot `
        -TargetSourceRoot $targetRoot `
        -CreatePullRequest
    } `
    -MessagePattern '*CreatePullRequest requires Apply*'

  & $upgradeScript `
    -RepositoryRoot $terraformRepo `
    -TargetVersion v1.1.0 `
    -CurrentSourceRoot $currentRoot `
    -TargetSourceRoot $targetRoot `
    -Apply `
    -NoBranch | Out-Null
  Assert-Equal '# target terraform' ((Get-Content -LiteralPath (Join-Path $terraformRepo 'terraform/main.tf') -Raw).Trim()) 'Terraform engine file was not upgraded.'
  Assert-Equal $true (Test-Path -LiteralPath (Join-Path $terraformRepo 'terraform/added.tf')) 'New Terraform managed file was not added.'
  Assert-Equal $false (Test-Path -LiteralPath (Join-Path $terraformRepo 'terraform/removed.tf')) 'Removed Terraform managed file was retained.'
  Assert-Equal 'tenant_id = "preserve"' ((Get-Content -LiteralPath (Join-Path $terraformRepo 'terraform/terraform.auto.tfvars') -Raw).Trim()) 'Rendered Terraform configuration changed.'
  Assert-Equal 'repository-owned request' ((Get-Content -LiteralPath (Join-Path $terraformRepo 'landingzones/corp/request.yaml') -Raw).Trim()) 'Subscription request changed.'
  Assert-Equal '* @platform' ((Get-Content -LiteralPath (Join-Path $terraformRepo '.github/CODEOWNERS') -Raw).Trim()) 'CODEOWNERS changed.'
  Assert-Equal 'version: 2 # local cadence' ((Get-Content -LiteralPath (Join-Path $terraformRepo '.github/dependabot.yml') -Raw).Trim()) 'Unchanged upstream managed customization was overwritten.'
  Assert-Equal 'repository-owned documentation' ((Get-Content -LiteralPath (Join-Path $terraformRepo 'docs/local-runbook.md') -Raw).Trim()) 'Local documentation changed.'
  $terraformMetadata = Get-Content -LiteralPath (Join-Path $terraformRepo '.accelerator/metadata.json') -Raw | ConvertFrom-Json
  Assert-Equal 'v1.1.0' $terraformMetadata.acceleratorVersion 'Terraform metadata version was not updated.'
  Assert-Equal $true ($terraformMetadata.managedFiles.PSObject.Properties.Name -contains 'terraform/added.tf') 'Updated metadata does not include new managed files.'
  Assert-Equal $false ($terraformMetadata.managedFiles.PSObject.Properties.Name -contains 'terraform/removed.tf') 'Updated metadata retained removed managed files.'

  $conflictRepo = Join-Path $testRoot 'conflict-repo'
  New-GeneratedRepository -Root $conflictRepo -SourceRoot $currentRoot -Engine terraform -WithMetadata
  Set-TestFile -Root $conflictRepo -RelativePath 'README.md' -Value 'local customization'
  Invoke-TestGit -Root $conflictRepo -Arguments @('add', '.')
  Invoke-TestGit -Root $conflictRepo -Arguments @('commit', '-qm', 'Customize managed file')
  Assert-Throws `
    -Script {
      & $upgradeScript `
        -RepositoryRoot $conflictRepo `
        -TargetVersion v1.1.0 `
        -CurrentSourceRoot $currentRoot `
        -TargetSourceRoot $targetRoot `
        -Apply `
        -NoBranch
    } `
    -MessagePattern '*conflict(s). No files were changed.*'
  Assert-Equal '# current terraform' ((Get-Content -LiteralPath (Join-Path $conflictRepo 'terraform/main.tf') -Raw).Trim()) 'Conflict handling partially applied the upgrade.'

  $bicepRepo = Join-Path $testRoot 'bicep-repo'
  New-GeneratedRepository -Root $bicepRepo -SourceRoot $currentRoot -Engine bicep -WithMetadata
  & $upgradeScript `
    -RepositoryRoot $bicepRepo `
    -TargetVersion v1.1.0 `
    -TargetSourceRoot $targetRoot `
    -Apply `
    -NoBranch | Out-Null
  Assert-Equal '// target bicep' ((Get-Content -LiteralPath (Join-Path $bicepRepo 'bicep/main.bicep') -Raw).Trim()) 'Bicep engine file was not upgraded.'
  Assert-Equal '{"preserve":true}' ((Get-Content -LiteralPath (Join-Path $bicepRepo 'bicep/platform.json') -Raw).Trim()) 'Rendered Bicep configuration changed.'

  $adoptionRepo = Join-Path $testRoot 'adoption-repo'
  New-GeneratedRepository -Root $adoptionRepo -SourceRoot $currentRoot -Engine terraform
  & $upgradeScript `
    -RepositoryRoot $adoptionRepo `
    -CurrentVersion v1.0.0 `
    -Starter terraform `
    -SourceRepository example/accelerator `
    -TargetVersion v1.1.0 `
    -CurrentSourceRoot $currentRoot `
    -TargetSourceRoot $targetRoot `
    -Apply `
    -NoBranch | Out-Null
  Assert-Equal $true (Test-Path -LiteralPath (Join-Path $adoptionRepo '.accelerator/metadata.json')) 'One-time adoption did not create metadata.'

  $branchRepo = Join-Path $testRoot 'branch-repo'
  New-GeneratedRepository -Root $branchRepo -SourceRoot $currentRoot -Engine terraform -WithMetadata
  & $upgradeScript `
    -RepositoryRoot $branchRepo `
    -TargetVersion v1.1.0 `
    -CurrentSourceRoot $currentRoot `
    -TargetSourceRoot $targetRoot `
    -Apply | Out-Null
  Push-Location -LiteralPath $branchRepo
  try {
    $createdBranch = git branch --show-current
  }
  finally {
    Pop-Location
  }
  Assert-Equal 'upgrade/accelerator-1.1.0' $createdBranch 'Apply did not create the versioned upgrade branch.'

  $noChangeTarget = Join-Path $testRoot 'source-no-change'
  Copy-Item -LiteralPath $currentRoot -Destination $noChangeTarget -Recurse
  $noChangeAccelerator = Get-Content -LiteralPath (Join-Path $noChangeTarget 'accelerator.json') -Raw | ConvertFrom-Json
  $noChangeAccelerator.version = 'v1.0.1'
  $noChangeAccelerator | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $noChangeTarget 'accelerator.json') -Encoding utf8NoBOM
  $noChangeRepo = Join-Path $testRoot 'no-change-repo'
  New-GeneratedRepository -Root $noChangeRepo -SourceRoot $currentRoot -Engine terraform -WithMetadata
  $noChangeOutput = & $upgradeScript `
    -RepositoryRoot $noChangeRepo `
    -TargetVersion v1.0.1 `
    -CurrentSourceRoot $currentRoot `
    -TargetSourceRoot $noChangeTarget 6>&1 | Out-String
  Assert-Equal $true ($noChangeOutput -match 'No accelerator-managed files changed') 'No-change upgrade did not exit cleanly.'
  $noChangeMetadata = Get-Content -LiteralPath (Join-Path $noChangeRepo '.accelerator/metadata.json') -Raw | ConvertFrom-Json
  Assert-Equal 'v1.0.0' $noChangeMetadata.acceleratorVersion 'No-change upgrade changed metadata.'

  $unsafeTarget = Join-Path $testRoot 'source-unsafe'
  Copy-Item -LiteralPath $targetRoot -Destination $unsafeTarget -Recurse
  $unsafeManifest = Get-Content -LiteralPath (Join-Path $unsafeTarget 'upgrade-manifest.json') -Raw | ConvertFrom-Json
  $unsafeManifest.common.includeFiles = @($unsafeManifest.common.includeFiles) + '../outside.txt'
  $unsafeManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $unsafeTarget 'upgrade-manifest.json') -Encoding utf8NoBOM
  Assert-Throws `
    -Script {
      & $upgradeScript `
        -RepositoryRoot $noChangeRepo `
        -TargetVersion v1.1.0 `
        -TargetSourceRoot $unsafeTarget
    } `
    -MessagePattern '*Managed path escapes its repository root*'

  Write-Host 'Subscription vending upgrade tests passed.'
}
finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
