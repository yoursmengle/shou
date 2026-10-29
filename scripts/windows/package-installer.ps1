#Requires -Version 7
param(
    [Parameter(Mandatory)][string]$PublishRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][ValidateSet('win-x64', 'win-arm64')][string]$Runtime,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl,
    [switch]$NativeChecked
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Velopack removes its installation root; never overlap the existing Shou data root.
$PackId = 'Limecloud.Shou'
$ToolVersion = '1.2.161'
$SourceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$WindowsRoot = Join-Path $SourceRoot 'apps/windows'
$PublishRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PublishRoot)
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$AppPayload = Join-Path $PublishRoot 'app'
$Architecture = $Runtime.Substring(4)
$Channel = $Runtime
$Name = "Shou-$Version-windows-$Architecture-Setup.exe"
$ReceiptName = "$Name.BUILD.json"
$ChecksumName = "SHA256SUMS-windows-installer-$Architecture"
$Signing = -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)
$Certificate = $null
$RuleCleanupAvailable = $Runtime -eq 'win-x64'
$MutationHostRequirement = if ($RuleCleanupAvailable) { 'native-windows11-x64-rule-cleanup' } else { 'native-acceptance-pending' }

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Installer packaging requires Windows.' }
$HeadCommit = & git -C $SourceRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $HeadCommit -cne $SourceCommit) { throw 'The source commit must identify this checkout HEAD.' }
$WorktreeStatus = @(& git -C $SourceRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'The source checkout state could not be recorded.' }
$WorkingTreeDirty = $WorktreeStatus.Count -gt 0
if ($Signing -ne (-not [string]::IsNullOrWhiteSpace($TimestampUrl))) {
    throw 'Signing requires both a certificate thumbprint and an HTTPS timestamp URL.'
}
if ($Signing) {
    if ($CertificateThumbprint -cnotmatch '^[0-9A-Fa-f]{40}$') { throw 'Use an exact certificate thumbprint.' }
    # vpk passes signParams through cmd.exe; accept only a bounded URL without shell syntax.
    if ($TimestampUrl -cnotmatch '^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~/-]*)?$' -or
        -not [Uri]::IsWellFormedUriString($TimestampUrl, [UriKind]::Absolute)) {
        throw 'Use an HTTPS timestamp URL without credentials, query, fragment or shell metacharacters.'
    }
    $CertificateThumbprint = $CertificateThumbprint.ToUpperInvariant()
    $Certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
    if (-not $Certificate.HasPrivateKey -or $Certificate.NotBefore -gt [DateTime]::Now -or $Certificate.NotAfter -le [DateTime]::Now -or
        '1.3.6.1.5.5.7.3.3' -notin @($Certificate.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId })) {
        throw 'The intended current-user certificate must have a private key and be valid for code signing.'
    }
}
foreach ($FileName in @($Name, $ReceiptName, $ChecksumName)) {
    if (Test-Path -LiteralPath (Join-Path $OutputDirectory $FileName)) { throw "Refusing to replace an existing release artifact: $FileName" }
}
if (Test-Path -LiteralPath (Join-Path $AppPayload 'BUILD.json')) { throw 'BUILD.json is reserved for verified release metadata.' }
if (Test-Path -LiteralPath (Join-Path $AppPayload 'SHOU-LICENSE.txt')) { throw 'SHOU-LICENSE.txt is reserved for the release license.' }
& python (Join-Path $SourceRoot 'scripts/package-windows.py') --validate-app --payload-root $AppPayload --version $Version --runtime $Runtime --source $SourceCommit
if ($LASTEXITCODE -ne 0) { throw 'The application payload did not pass release validation.' }
$ToolManifest = Get-Content -LiteralPath (Join-Path $WindowsRoot '.config/dotnet-tools.json') -Raw | ConvertFrom-Json
if ($ToolManifest.tools.vpk.version -cne $ToolVersion) { throw 'The local vpk version differs from the pinned packaging version.' }

function Assert-IntendedSignature {
    param([string]$Path)
    $Signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($Signature.Status -ne 'Valid' -or $null -eq $Signature.SignerCertificate -or $null -eq $Signature.TimeStamperCertificate -or
        $Signature.SignerCertificate.Thumbprint -cne $CertificateThumbprint -or $Signature.SignerCertificate.Subject -cne $Certificate.Subject) {
        throw "The final signature or timestamp does not match the intended publisher: $([IO.Path]::GetFileName($Path))"
    }
}

function Get-PayloadHashes {
    param([string]$Root)
    $Hashes = [ordered]@{}
    foreach ($File in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
        $Hashes[$Relative] = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $Hashes
}

$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
if ((Get-Item -LiteralPath $OutputDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The release output cannot be a reparse point.' }
$StagingRoot = Join-Path $OutputDirectory ('.shou-installer-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $StagingRoot
try {
    $StagedApp = Join-Path $StagingRoot 'app'
    Copy-Item -LiteralPath $AppPayload -Destination $StagedApp -Recurse
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'LICENSE') -Destination (Join-Path $StagedApp 'SHOU-LICENSE.txt')
    $PayloadReceipt = [ordered]@{
        format_version = 1; version = $Version; source_commit = $SourceCommit; working_tree_dirty = $WorkingTreeDirty; configuration = 'Release';
        runtime = $Runtime; kind = 'app'; minimum_windows_build = 22000;
        distribution = 'current-user-installer-preview'; install_id = $PackId; velopack_version = $ToolVersion;
        signing = $(if ($Signing) { 'authenticode' } else { 'unsigned' });
        native_smoke_checked = $NativeChecked.IsPresent; public_mutation_available = $RuleCleanupAvailable;
        rule_cleanup_available = $RuleCleanupAvailable; storage_removal_available = $false; privacy_cleanup_available = $false;
        mutation_host_requirement = $MutationHostRequirement; input_files = (Get-PayloadHashes $StagedApp)
    }
    $PayloadReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $StagedApp 'BUILD.json') -Encoding utf8
    $PackOutput = Join-Path $StagingRoot 'packed'
    $PackArguments = @('tool', 'run', 'vpk', '--', 'pack', '--packId', $PackId, '--packVersion', $Version,
        '--packDir', $StagedApp, '--mainExe', 'Shou.Windows.App.exe', '--packTitle', 'Shou', '--packAuthors', 'Limecloud',
        '--icon', (Join-Path $WindowsRoot 'Generated/Shou.ico'),
        '--channel', $Channel, '--runtime', "win10.0.22000-$Architecture", '--noPortable',
        '--exclude', '^$', '--noDefaultExclude', '--outputDir', $PackOutput)
    if ($Signing) {
        $PackArguments += @('--signParams', "/sha1 $CertificateThumbprint /s My /fd SHA256 /tr $TimestampUrl /td SHA256")
    }
    Push-Location $WindowsRoot
    try {
        & dotnet tool restore
        if ($LASTEXITCODE -ne 0) { throw 'The pinned installer tool could not be restored.' }
        & dotnet @PackArguments
        if ($LASTEXITCODE -ne 0) { throw 'Installer packing or signing failed.' }
    } finally { Pop-Location }
    $Setup = Join-Path $PackOutput "$PackId-$Channel-Setup.exe"
    if (-not (Test-Path -LiteralPath $Setup -PathType Leaf)) { throw 'The expected Setup output is missing.' }
    $FullPackages = @(Get-ChildItem -LiteralPath $PackOutput -Filter '*-full.nupkg' -File)
    if ($FullPackages.Count -ne 1) { throw 'Expected exactly one newly generated full installation package.' }
    $Extracted = Join-Path $StagingRoot 'verified-package'
    [IO.Compression.ZipFile]::ExtractToDirectory($FullPackages[0].FullName, $Extracted)
    $FinalApp = Join-Path $Extracted 'lib/app'
    & python (Join-Path $SourceRoot 'scripts/package-windows.py') --validate-app --payload-root $FinalApp --version $Version --runtime $Runtime --source $SourceCommit
    if ($LASTEXITCODE -ne 0) { throw 'The final installation payload did not pass release validation.' }
    $EmbeddedReceipt = Join-Path $FinalApp 'BUILD.json'
    if ((Get-FileHash -LiteralPath $EmbeddedReceipt -Algorithm SHA256).Hash -cne
        (Get-FileHash -LiteralPath (Join-Path $StagedApp 'BUILD.json') -Algorithm SHA256).Hash) {
        throw 'The source-bound installation receipt changed during packing.'
    }
    if ($Signing) {
        Assert-IntendedSignature $Setup
        foreach ($File in Get-ChildItem -LiteralPath $FinalApp -File -Recurse | Where-Object {
            $_.Name -match '^Shou.*\.(exe|dll)$' -or $_.Name -eq 'Squirrel.exe'
        }) { Assert-IntendedSignature $File.FullName }
    } else {
        if ((Get-AuthenticodeSignature -LiteralPath $Setup).Status -ne 'NotSigned') { throw 'Unsigned preview Setup has an unexpected signature.' }
        foreach ($Entry in $PayloadReceipt.input_files.GetEnumerator()) {
            if ((Get-FileHash -LiteralPath (Join-Path $FinalApp $Entry.Key) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Entry.Value) {
                throw "Unsigned installation payload differs from its validated input: $($Entry.Key)"
            }
        }
    }
    $FinalReceipt = [ordered]@{
        format_version = 1; version = $Version; source_commit = $SourceCommit; working_tree_dirty = $WorkingTreeDirty; runtime = $Runtime;
        install_id = $PackId; velopack_version = $ToolVersion; distribution = 'current-user-installer-preview';
        signing = $PayloadReceipt.signing; publisher = $(if ($Signing) { $Certificate.Subject } else { $null });
        certificate_thumbprint = $(if ($Signing) { $CertificateThumbprint } else { $null });
        timestamp_verified = $Signing; native_smoke_checked = $NativeChecked.IsPresent;
        lifecycle_accepted = $false; public_mutation_available = $RuleCleanupAvailable;
        rule_cleanup_available = $RuleCleanupAvailable; storage_removal_available = $false; privacy_cleanup_available = $false;
        mutation_host_requirement = $MutationHostRequirement;
        file = $Name; sha256 = (Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash.ToLowerInvariant();
        bytes = (Get-Item -LiteralPath $Setup).Length; files = (Get-PayloadHashes $FinalApp)
    }
    $StagedReceipt = Join-Path $StagingRoot $ReceiptName
    $FinalReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StagedReceipt -Encoding utf8
    $ReceiptHash = (Get-FileHash -LiteralPath $StagedReceipt -Algorithm SHA256).Hash.ToLowerInvariant()
    $Checksums = "$($FinalReceipt.sha256)  $Name`n$ReceiptHash  $ReceiptName`n"
    Copy-Item -LiteralPath $Setup -Destination (Join-Path $OutputDirectory $Name)
    Copy-Item -LiteralPath $StagedReceipt -Destination (Join-Path $OutputDirectory $ReceiptName)
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory $Name) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $FinalReceipt.sha256) {
        throw 'Final installer bytes changed after verification.'
    }
    [IO.File]::WriteAllText((Join-Path $OutputDirectory $ChecksumName), $Checksums, [Text.UTF8Encoding]::new($false))
    Write-Output "Installer and final checksums: $(Join-Path $OutputDirectory $Name) ($($FinalReceipt.signing))"
} finally {
    $ResolvedStage = [IO.Path]::GetFullPath($StagingRoot)
    $ExpectedParent = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $ResolvedStage.StartsWith($ExpectedParent, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($ResolvedStage) -notmatch '^\.shou-installer-[0-9a-f]{32}$') {
        throw 'Refusing to remove a staging directory outside this packaging run.'
    }
    Remove-Item -LiteralPath $ResolvedStage -Recurse -Force
}
