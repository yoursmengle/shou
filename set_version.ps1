#Requires -Version 7.4
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z')]
    [string]$Version
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($component in $Version.Split('.')) {
    if ($component.Length -gt 5 -or [int]$component -gt 65534) {
        throw 'Each version component must be between 0 and 65534 for .NET assembly versions.'
    }
}

$targets = @(
    @{ Path = 'apps/windows/Directory.Build.props'; Patterns = @('(<Version>)[^<]+(</Version>)') },
    @{ Path = 'apps/macos/Info.plist'; Patterns = @(
        '(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)',
        '(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)'
    ) },
    @{ Path = 'apps/cli/Sources/ShouCLI.swift'; Patterns = @('(?m)^([ \t]*static let version = ")[^"]+(")') },
    @{ Path = 'packages/shou-npm/package.json'; Patterns = @('(?m)^([ \t]*"version"\s*:\s*")[^"]+(")') }
)

# Validate every source before changing any version field.
$updates = foreach ($target in $targets) {
    $path = Join-Path $PSScriptRoot $target.Path
    $original = [IO.File]::ReadAllText($path)
    $content = $original
    foreach ($pattern in $target.Patterns) {
        if ([regex]::Matches($content, $pattern).Count -ne 1) {
            throw "Expected exactly one version field in $($target.Path): $pattern"
        }
        $content = [regex]::Replace($content, $pattern, [Text.RegularExpressions.MatchEvaluator]{
            param($match)
            $match.Groups[1].Value + $Version + $match.Groups[2].Value
        })
    }
    [pscustomobject]@{ Path = $path; Original = $original; Content = $content }
}
foreach ($update in $updates) {
    if ($update.Content -cne $update.Original) {
        [IO.File]::WriteAllText($update.Path, $update.Content, [Text.UTF8Encoding]::new($false))
    }
}
Write-Output "Version set to $Version for Windows, macOS, Swift CLI and npm."
