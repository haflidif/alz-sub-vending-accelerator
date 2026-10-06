#Requires -Version 7.2

[CmdletBinding(DefaultParameterSetName = 'Version')]
param(
  [Parameter(Mandatory, ParameterSetName = 'Version')]
  [ValidatePattern('^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
  [string] $TargetVersion,

  [Parameter(Mandatory, ParameterSetName = 'Latest')]
  [switch] $Latest,

  [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

  [ValidatePattern('^v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
  [string] $CurrentVersion,

  [ValidateSet('terraform', 'bicep')]
  [string] $Starter,

  [string] $SourceRepository,

  [string] $CurrentSourceRoot,

  [string] $TargetSourceRoot,

  [switch] $Apply,

  [switch] $NoBranch,

  [switch] $CreatePullRequest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$canonicalSourceRepository = 'haflidif/alz-sub-vending-accelerator'
$legacySourceRepositories = @(
  'haflidif/alz-sub-vending-terraform-accelerator'
)

function ConvertTo-NormalizedVersion {
  param([Parameter(Mandatory)][string] $Version)

  if ($Version.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
    return "v$($Version.Substring(1))"
  }
  "v$Version"
}

function ConvertTo-CanonicalSourceRepository {
  param([Parameter(Mandatory)][string] $Repository)

  if ($Repository -in $legacySourceRepositories) {
    return $canonicalSourceRepository
  }
  $Repository
}

function Get-NormalizedRelativePath {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $Path
  )

  [System.IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
}

function Resolve-ContainedPath {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $RelativePath
  )

  if ([System.IO.Path]::IsPathRooted($RelativePath)) {
    throw "Managed path must be relative: '$RelativePath'."
  }
  $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
  $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $RelativePath))
  $rootPrefix = $resolvedRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $resolvedPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Managed path escapes its repository root: '$RelativePath'."
  }
  $resolvedPath
}

function Get-ManagedFileHash {
  param([Parameter(Mandatory)][string] $Path)

  $content = [System.IO.File]::ReadAllText($Path)
  $normalized = $content.Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
  [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Read-JsonFile {
  param(
    [Parameter(Mandatory)][string] $Path,
    [Parameter(Mandatory)][string] $Description
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Description not found at '$Path'."
  }
  Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 32
}

function Test-IsExcludedPath {
  param(
    [Parameter(Mandatory)][string] $RelativePath,
    [Parameter(Mandatory)] $ManifestSection
  )

  if ($RelativePath -in @($ManifestSection.excludeFiles)) {
    return $true
  }
  foreach ($prefix in @($ManifestSection.excludePrefixes)) {
    if ($RelativePath.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
      return $true
    }
  }
  foreach ($pattern in @($ManifestSection.excludePatterns)) {
    if ($RelativePath -match $pattern) {
      return $true
    }
  }
  $false
}

function Get-ManagedPackageFiles {
  param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)] $Manifest,
    [Parameter(Mandatory)][ValidateSet('terraform', 'bicep')][string] $Engine
  )

  $engineSection = $Manifest.engines.$Engine
  if ($null -eq $engineSection) {
    throw "Upgrade manifest does not define engine '$Engine'."
  }

  $paths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
  )

  foreach ($relativePath in @($Manifest.common.includeFiles)) {
    $candidate = Resolve-ContainedPath -Root $SourceRoot -RelativePath $relativePath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      $null = $paths.Add($relativePath)
    }
  }

  foreach ($section in @($Manifest.common, $engineSection)) {
    foreach ($prefix in @($section.includePrefixes)) {
      $directory = Resolve-ContainedPath -Root $SourceRoot -RelativePath $prefix
      if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        continue
      }
      foreach ($file in Get-ChildItem -LiteralPath $directory -File -Recurse) {
        $relativePath = Get-NormalizedRelativePath -Root $SourceRoot -Path $file.FullName
        if (-not (Test-IsExcludedPath -RelativePath $relativePath -ManifestSection $Manifest.common) `
          -and -not (Test-IsExcludedPath -RelativePath $relativePath -ManifestSection $engineSection)) {
          $null = $paths.Add($relativePath)
        }
      }
    }
  }

  @($paths | Sort-Object)
}

function Get-LatestReleaseVersion {
  param([Parameter(Mandatory)][string] $Repository)

  $headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'subscription-vending-updater'
  }
  $release = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$Repository/releases/latest" `
    -Headers $headers
  if (-not $release.tag_name) {
    throw "Latest release for '$Repository' did not contain a tag."
  }
  ConvertTo-NormalizedVersion -Version $release.tag_name
}

function Get-ReleaseSourceRoot {
  param(
    [Parameter(Mandatory)][string] $Repository,
    [Parameter(Mandatory)][string] $Version,
    [Parameter(Mandatory)][string] $WorkingDirectory
  )

  $archivePath = Join-Path $WorkingDirectory "$($Version.TrimStart('v')).zip"
  $extractPath = Join-Path $WorkingDirectory $Version
  $uri = "https://github.com/$Repository/archive/refs/tags/$Version.zip"

  Write-Host "Downloading $Repository $Version..."
  Invoke-WebRequest -Uri $uri -OutFile $archivePath
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
  $roots = @(Get-ChildItem -LiteralPath $extractPath -Directory)
  if ($roots.Count -ne 1) {
    throw "Expected one repository root in '$archivePath', found $($roots.Count)."
  }
  $roots[0].FullName
}

function Get-UpgradePlan {
  param(
    [Parameter(Mandatory)][string] $LocalRoot,
    [string] $CurrentRoot,
    [hashtable] $CurrentHashes,
    [Parameter(Mandatory)][string] $TargetRoot,
    [Parameter(Mandatory)] $Manifest,
    [Parameter(Mandatory)][ValidateSet('terraform', 'bicep')][string] $Engine
  )

  if (($null -eq $CurrentHashes -or $CurrentHashes.Count -eq 0) -and -not $CurrentRoot) {
    throw 'CurrentRoot is required when managed-file hashes are unavailable.'
  }
  $currentFiles = if ($CurrentHashes -and $CurrentHashes.Count -gt 0) {
    @($CurrentHashes.Keys | Sort-Object)
  }
  else {
    @(Get-ManagedPackageFiles -SourceRoot $CurrentRoot -Manifest $Manifest -Engine $Engine)
  }
  $targetFiles = @(Get-ManagedPackageFiles -SourceRoot $TargetRoot -Manifest $Manifest -Engine $Engine)
  $allPaths = @($currentFiles + $targetFiles | Sort-Object -Unique)
  $targetHashes = @{}
  foreach ($relativePath in $targetFiles) {
    $targetPath = Resolve-ContainedPath -Root $TargetRoot -RelativePath $relativePath
    $targetHashes[$relativePath] = Get-ManagedFileHash -Path $targetPath
  }
  $changes = [System.Collections.Generic.List[object]]::new()
  $conflicts = [System.Collections.Generic.List[object]]::new()

  foreach ($relativePath in $allPaths) {
    $currentPath = if ($CurrentRoot) {
      Resolve-ContainedPath -Root $CurrentRoot -RelativePath $relativePath
    }
    else {
      $null
    }
    $targetPath = Resolve-ContainedPath -Root $TargetRoot -RelativePath $relativePath
    $localPath = Resolve-ContainedPath -Root $LocalRoot -RelativePath $relativePath
    $currentExists = if ($CurrentHashes -and $CurrentHashes.Count -gt 0) {
      $CurrentHashes.ContainsKey($relativePath)
    }
    else {
      Test-Path -LiteralPath $currentPath -PathType Leaf
    }
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf
    $localExists = Test-Path -LiteralPath $localPath -PathType Leaf
    $currentHash = if (-not $currentExists) {
      $null
    }
    elseif ($CurrentHashes -and $CurrentHashes.Count -gt 0) {
      $CurrentHashes[$relativePath]
    }
    else {
      Get-ManagedFileHash -Path $currentPath
    }
    $targetHash = if ($targetExists) { $targetHashes[$relativePath] } else { $null }
    $localHash = if ($localExists) { Get-ManagedFileHash -Path $localPath } else { $null }
    $upstreamChanged = $currentHash -ne $targetHash

    if (-not $upstreamChanged) {
      continue
    }

    if ($currentExists) {
      if (-not $targetExists -and -not $localExists) {
        continue
      }
      if (-not $localExists -or $localHash -ne $currentHash) {
        $conflicts.Add([pscustomobject]@{
          Path = $relativePath
          Reason = if ($localExists) { 'Locally modified managed file' } else { 'Locally deleted managed file' }
        })
        continue
      }
      $changes.Add([pscustomobject]@{
        Path = $relativePath
        Action = if ($targetExists) { 'Update' } else { 'Remove' }
      })
      continue
    }

    if ($localExists -and $localHash -ne $targetHash) {
      $conflicts.Add([pscustomobject]@{
        Path = $relativePath
        Reason = 'Target managed file collides with a repository-owned file'
      })
      continue
    }
    if (-not $localExists) {
      $changes.Add([pscustomobject]@{ Path = $relativePath; Action = 'Add' })
    }
  }

  [pscustomobject]@{
    Changes = @($changes)
    Conflicts = @($conflicts)
    TargetHashes = $targetHashes
  }
}

function Assert-CleanGitRepository {
  param([Parameter(Mandatory)][string] $Root)

  Push-Location -LiteralPath $Root
  try {
    $inside = & git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
      throw "Repository root '$Root' is not a Git working tree."
    }
    $status = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to inspect Git status for '$Root'."
    }
  }
  finally {
    Pop-Location
  }
  if ($status.Count -gt 0) {
    throw 'The working tree must be clean before applying an accelerator upgrade.'
  }
}

function New-UpgradeBranch {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $Version
  )

  $branch = "upgrade/accelerator-$($Version.TrimStart('v'))"
  Push-Location -LiteralPath $Root
  try {
    & git switch -c $branch
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to create upgrade branch '$branch'."
    }
  }
  finally {
    Pop-Location
  }
  $branch
}

function Invoke-UpgradeChanges {
  param(
    [Parameter(Mandatory)][string] $LocalRoot,
    [Parameter(Mandatory)][string] $TargetRoot,
    [Parameter(Mandatory)] $Plan
  )

  foreach ($change in $Plan.Changes) {
    $localPath = Resolve-ContainedPath -Root $LocalRoot -RelativePath $change.Path
    if ($change.Action -eq 'Remove') {
      Remove-Item -LiteralPath $localPath
      continue
    }
    $targetPath = Resolve-ContainedPath -Root $TargetRoot -RelativePath $change.Path
    $parent = Split-Path -Parent $localPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $targetPath -Destination $localPath -Force
  }
}

function Write-UpgradeMetadata {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $Repository,
    [Parameter(Mandatory)][string] $Version,
    [Parameter(Mandatory)][string] $Engine,
    [Parameter(Mandatory)][hashtable] $ManagedFiles
  )

  $metadataDirectory = Join-Path $Root '.accelerator'
  New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
  $sortedManagedFiles = [ordered]@{}
  foreach ($path in @($ManagedFiles.Keys | Sort-Object)) {
    $sortedManagedFiles[$path] = $ManagedFiles[$path]
  }
  $metadata = [ordered]@{
    schemaVersion = '1.0'
    sourceRepository = $Repository
    acceleratorVersion = $Version
    starter = $Engine
    managedFiles = $sortedManagedFiles
  }
  $metadata |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $metadataDirectory 'metadata.json') -Encoding utf8NoBOM
}

function Publish-UpgradePullRequest {
  param(
    [Parameter(Mandatory)][string] $Root,
    [Parameter(Mandatory)][string] $Current,
    [Parameter(Mandatory)][string] $Target,
    [Parameter(Mandatory)][string] $Branch,
    [Parameter(Mandatory)][string] $Repository
  )

    $commitMessagePath = [System.IO.Path]::GetTempFileName()
    Set-Content `
      -LiteralPath $commitMessagePath `
      -Value "chore: upgrade accelerator to $Target" `
      -Encoding utf8NoBOM

    $body = @"
## Summary

Upgrade accelerator-managed files from $Current to $Target.

Repository-owned subscription requests, platform configuration, CODEOWNERS,
and local additions are preserved. Review the full fleet preview before merge.
After merge, run Apply explicitly with ``mode=all`` when ready.

Release notes: https://github.com/$Repository/releases/tag/$Target
"@

    Push-Location -LiteralPath $Root
    try {
      & git add --all
      if ($LASTEXITCODE -ne 0) { throw 'Unable to stage upgrade changes.' }
      & git diff --cached --quiet
      if ($LASTEXITCODE -eq 0) { throw 'Upgrade produced no staged changes.' }
      & git commit -F $commitMessagePath
      if ($LASTEXITCODE -ne 0) { throw 'Unable to commit upgrade changes.' }
      & git push --set-upstream origin $Branch
      if ($LASTEXITCODE -ne 0) { throw "Unable to push upgrade branch '$Branch'." }

      & gh pr create `
        --title "Upgrade accelerator to $Target" `
        --body $body `
        --head $Branch
      if ($LASTEXITCODE -ne 0) { throw 'Unable to create the upgrade pull request.' }
    }
    finally {
      Pop-Location
      Remove-Item -LiteralPath $commitMessagePath -Force -ErrorAction SilentlyContinue
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
  throw "Repository root not found at '$resolvedRoot'."
}
$metadataPath = Join-Path $resolvedRoot '.accelerator/metadata.json'
$metadata = if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
  Read-JsonFile -Path $metadataPath -Description 'Accelerator metadata'
}
else {
  $null
}
$currentHashes = @{}

if ($metadata) {
  if ($CurrentVersion -and (ConvertTo-NormalizedVersion $CurrentVersion) -ne $metadata.acceleratorVersion) {
    throw "CurrentVersion does not match recorded version '$($metadata.acceleratorVersion)'."
  }
  if ($Starter -and $Starter -ne $metadata.starter) {
    throw "Starter does not match recorded starter '$($metadata.starter)'."
  }
  if (
    $SourceRepository `
      -and (ConvertTo-CanonicalSourceRepository $SourceRepository) `
      -ne (ConvertTo-CanonicalSourceRepository $metadata.sourceRepository)
  ) {
    throw "SourceRepository does not match recorded repository '$($metadata.sourceRepository)'."
  }
  $CurrentVersion = $metadata.acceleratorVersion
  $Starter = $metadata.starter
  $SourceRepository = ConvertTo-CanonicalSourceRepository $metadata.sourceRepository
  if ($metadata.PSObject.Properties.Name -contains 'managedFiles') {
    foreach ($property in $metadata.managedFiles.PSObject.Properties) {
      $currentHashes[$property.Name] = [string] $property.Value
    }
  }
}
elseif (-not $CurrentVersion -or -not $Starter) {
  throw 'Metadata is missing. Supply both -CurrentVersion and -Starter for one-time adoption.'
}

if (-not $SourceRepository) {
  $SourceRepository = $canonicalSourceRepository
}
$SourceRepository = ConvertTo-CanonicalSourceRepository $SourceRepository
if ($SourceRepository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
  throw "SourceRepository must use owner/repository format: '$SourceRepository'."
}
if ($CreatePullRequest -and -not $Apply) {
  throw 'CreatePullRequest requires Apply.'
}

$CurrentVersion = ConvertTo-NormalizedVersion $CurrentVersion
$TargetVersion = if ($Latest) {
  Get-LatestReleaseVersion -Repository $SourceRepository
}
else {
  ConvertTo-NormalizedVersion $TargetVersion
}

if ($CurrentVersion -eq $TargetVersion) {
  Write-Host "Repository already records accelerator $TargetVersion. No upgrade is required."
  return
}

$temporaryRoot = $null
try {
  if ($CurrentSourceRoot -and -not $TargetSourceRoot) {
    throw 'TargetSourceRoot is required when CurrentSourceRoot is supplied.'
  }
  if (-not $TargetSourceRoot) {
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "subscription-vending-upgrade-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $TargetSourceRoot = Get-ReleaseSourceRoot `
      -Repository $SourceRepository `
      -Version $TargetVersion `
      -WorkingDirectory $temporaryRoot
  }
  if ($currentHashes.Count -eq 0 -and -not $CurrentSourceRoot) {
    if (-not $temporaryRoot) {
      $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "subscription-vending-upgrade-$([guid]::NewGuid())"
      New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    }
    $CurrentSourceRoot = Get-ReleaseSourceRoot `
      -Repository $SourceRepository `
      -Version $CurrentVersion `
      -WorkingDirectory $temporaryRoot
  }

  $TargetSourceRoot = [System.IO.Path]::GetFullPath($TargetSourceRoot)
  if ($CurrentSourceRoot) {
    $CurrentSourceRoot = [System.IO.Path]::GetFullPath($CurrentSourceRoot)
  }
  foreach ($sourceRoot in @($CurrentSourceRoot, $TargetSourceRoot) | Where-Object { $_ }) {
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
      throw "Release source root not found at '$sourceRoot'."
    }
  }
  $targetAccelerator = Read-JsonFile `
    -Path (Join-Path $TargetSourceRoot 'accelerator.json') `
    -Description 'Target accelerator metadata'
  if ((ConvertTo-NormalizedVersion $targetAccelerator.version) -ne $TargetVersion) {
    throw "Target source version '$($targetAccelerator.version)' does not match requested version '$TargetVersion'."
  }
  if ((ConvertTo-CanonicalSourceRepository $targetAccelerator.repository) -ne $SourceRepository) {
    throw "Target source repository '$($targetAccelerator.repository)' does not match '$SourceRepository'."
  }
  $manifest = Read-JsonFile `
    -Path (Join-Path $TargetSourceRoot 'upgrade-manifest.json') `
    -Description 'Target upgrade manifest'
  if ($manifest.schemaVersion -ne '1.0') {
    throw "Unsupported upgrade manifest version '$($manifest.schemaVersion)'."
  }

  $plan = Get-UpgradePlan `
    -LocalRoot $resolvedRoot `
    -CurrentRoot $CurrentSourceRoot `
    -CurrentHashes $currentHashes `
    -TargetRoot $TargetSourceRoot `
    -Manifest $manifest `
    -Engine $Starter

  Write-Host "Accelerator upgrade: $CurrentVersion -> $TargetVersion ($Starter)"
  foreach ($change in $plan.Changes) {
    Write-Host "[$($change.Action.ToUpperInvariant())] $($change.Path)"
  }
  foreach ($conflict in $plan.Conflicts) {
    Write-Host "[CONFLICT] $($conflict.Path): $($conflict.Reason)" -ForegroundColor Red
  }

  if ($plan.Conflicts.Count -gt 0) {
    throw "Upgrade has $($plan.Conflicts.Count) conflict(s). No files were changed."
  }
  if ($plan.Changes.Count -eq 0) {
    Write-Host 'No accelerator-managed files changed. No branch or pull request was created.'
    return
  }
  if (-not $Apply) {
    Write-Host 'Preview complete. Re-run with -Apply to create the upgrade branch and update files.'
    return
  }
  if ($CreatePullRequest -and $NoBranch) {
    throw 'CreatePullRequest cannot be combined with NoBranch.'
  }

  Assert-CleanGitRepository -Root $resolvedRoot
  $branch = $null
  if (-not $NoBranch) {
    $branch = New-UpgradeBranch -Root $resolvedRoot -Version $TargetVersion
  }
  Invoke-UpgradeChanges -LocalRoot $resolvedRoot -TargetRoot $TargetSourceRoot -Plan $plan
  Write-UpgradeMetadata `
    -Root $resolvedRoot `
    -Repository $SourceRepository `
    -Version $TargetVersion `
    -Engine $Starter `
    -ManagedFiles $plan.TargetHashes

  Write-Host "Applied $($plan.Changes.Count) managed-file change(s). Review the working tree before committing."
  if ($CreatePullRequest) {
    Publish-UpgradePullRequest `
      -Root $resolvedRoot `
      -Current $CurrentVersion `
      -Target $TargetVersion `
      -Branch $branch `
      -Repository $SourceRepository
  }
}
finally {
  if ($temporaryRoot -and (Test-Path -LiteralPath $temporaryRoot)) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
