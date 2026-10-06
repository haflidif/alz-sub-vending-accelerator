#Requires -Version 7.2

[CmdletBinding()]
param(
  [string] $ThemeRoot = (Join-Path $PSScriptRoot 'themes/hugo-geekdoc')
)

$ErrorActionPreference = 'Stop'
$version = 'v4.1.4'
$expectedHash = '384675981b41bf70fbc2943d05fadb20ac6090f52c08550fd139842bdb8cb260'
$archiveUrl = "https://github.com/thegeeklab/hugo-geekdoc/releases/download/$version/hugo-geekdoc.tar.gz"

if (Test-Path -LiteralPath (Join-Path $ThemeRoot 'theme.toml') -PathType Leaf) {
  Write-Host "Hugo Geekdoc $version is already installed."
  return
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "hugo-geekdoc-$([guid]::NewGuid())"
$archivePath = Join-Path $temporaryRoot 'hugo-geekdoc.tar.gz'

try {
  New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
  Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath

  $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne $expectedHash) {
    throw "Hugo Geekdoc archive checksum mismatch. Expected '$expectedHash', got '$actualHash'."
  }

  New-Item -ItemType Directory -Path $ThemeRoot -Force | Out-Null
  & tar -xzf $archivePath -C $ThemeRoot
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to extract Hugo Geekdoc $version."
  }
  if (-not (Test-Path -LiteralPath (Join-Path $ThemeRoot 'theme.toml') -PathType Leaf)) {
    throw "The Hugo Geekdoc archive did not contain theme.toml at its root."
  }

  Write-Host "Installed Hugo Geekdoc $version with verified SHA-256."
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
