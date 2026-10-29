#Requires -Version 7.4
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) { throw 'Windows installer generation requires Windows.' }
[xml]$properties = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'apps/windows/Directory.Build.props'))
$version = [string]$properties.Project.PropertyGroup.Version
if ($version -cnotmatch '\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z') {
    throw 'Set a valid release version with set_version.ps1 first.'
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot "dist/windows/$version" }
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$installerNames = foreach ($architecture in @('x64', 'arm64')) {
    $name = "Shou-$version-windows-$architecture-Setup.exe"
    $name
    $name + '.BUILD.json'
}
$releaseNames = $installerNames + @('SHA256SUMS', 'SHA256SUMS-windows-installer-x64', 'SHA256SUMS-windows-installer-arm64')
$previousArtifacts = @()
$ancestor = $OutputDirectory
while ($ancestor) {
    if ((Test-Path -LiteralPath $ancestor) -and
        ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The output directory and its ancestors cannot be reparse points.'
    }
    $ancestor = Split-Path $ancestor -Parent
}
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'The output path must be a directory.' }
    foreach ($entry in Get-ChildItem -LiteralPath $OutputDirectory -Force) {
        if ($entry.Name -notin $releaseNames -or $entry.PSIsContainer -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "The output directory contains an unrelated file or directory; nothing was removed: $($entry.Name)"
        }
        if ($entry.Name.StartsWith('SHA256SUMS')) {
            $lines = @(Get-Content -LiteralPath $entry.FullName)
            foreach ($line in $lines) {
                $match = [regex]::Match($line, '\A[0-9a-f]{64}  (.+)\z')
                if ($match.Success -and $match.Groups[1].Value -notin $installerNames) {
                    throw 'An existing checksum manifest contains other release files; nothing was removed.'
                }
            }
        }
        $previousArtifacts += $entry.FullName
    }
}

$originalPath = $env:PATH
$originalDotnetRoot = $env:DOTNET_ROOT
Push-Location (Join-Path $PSScriptRoot 'apps/windows')
try {
    $localSdk = Join-Path $PSScriptRoot '.build/dotnet'
    if (Test-Path -LiteralPath (Join-Path $localSdk 'dotnet.exe') -PathType Leaf) {
        $env:DOTNET_ROOT = $localSdk
        $env:PATH = $localSdk + [IO.Path]::PathSeparator + $env:PATH
    }
    foreach ($command in @('dotnet', 'python', 'git')) { $null = Get-Command $command -ErrorAction Stop }
    $sdk = & dotnet --version
    if ($LASTEXITCODE -ne 0) { throw 'Install the .NET SDK pinned in apps/windows/global.json.' }
    Write-Output "Building Windows installers $version with .NET SDK $sdk."
    $sourceCommit = & git -C $PSScriptRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $sourceCommit -cnotmatch '\A[0-9a-f]{40}\z') { throw 'The source checkout HEAD could not be resolved.' }
    # Remove only this version's known files, after all output entries and tools pass validation.
    foreach ($path in $previousArtifacts) {
        $entry = Get-Item -LiteralPath $path -Force
        if ([IO.Path]::GetDirectoryName($entry.FullName) -ine $OutputDirectory.TrimEnd('\', '/') -or
            $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'An existing artifact changed its path or type; refusing to remove it.'
        }
        Remove-Item -LiteralPath $entry.FullName -Force
    }
    if ($previousArtifacts.Count) { Write-Output "Removed $($previousArtifacts.Count) previous artifacts for $version." }
    $buildRoot = Join-Path $PSScriptRoot ('.build/windows-release/' + [Guid]::NewGuid().ToString('N'))
    $checksums = ''
    foreach ($runtime in @('win-x64', 'win-arm64')) {
        $artifacts = Join-Path $buildRoot $runtime
        & (Join-Path $PSScriptRoot 'scripts/windows/build.ps1') -Runtime $runtime -ArtifactsRoot $artifacts
        [xml]$currentProperties = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'apps/windows/Directory.Build.props'))
        if ([string]$currentProperties.Project.PropertyGroup.Version -cne $version) {
            throw 'The version changed during the build; run release.ps1 again with the current version.'
        }
        & (Join-Path $PSScriptRoot 'scripts/windows/package-installer.ps1') -PublishRoot (Join-Path $artifacts 'publish') `
            -OutputDirectory $OutputDirectory -Version $version -Runtime $runtime -SourceCommit $sourceCommit
        $checksums += [IO.File]::ReadAllText((Join-Path $OutputDirectory ('SHA256SUMS-windows-installer-' + $runtime.Substring(4))))
    }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS'), $checksums, [Text.UTF8Encoding]::new($false))
    Write-Output "Both Windows installers and SHA256SUMS are ready: $OutputDirectory"
} finally {
    $env:PATH = $originalPath
    $env:DOTNET_ROOT = $originalDotnetRoot
    Pop-Location
}
