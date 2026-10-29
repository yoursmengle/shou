#requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$RunGeneratedInstallerFixtures,
    [string]$PublishRoot,
    [string]$ArtifactsRoot,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ChildPath([string]$Path, [string]$Root) {
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path must remain strictly inside its generated boundary: $Path"
    }
}

function Assert-GeneratedIdentity([string]$Identity) {
    if ($Identity -cnotmatch '^Limecloud\.ShouAcceptance\.[0-9a-f]{32}$') {
        throw 'Only a newly generated Shou acceptance identity is allowed.'
    }
}

function Assert-PinnedToolList([string]$ToolList) {
    if ($ToolList -notmatch '(?m)^\s*vpk\s+1\.2\.161\s+vpk(?:\s|$)') {
        throw 'The restored local vpk tool must be version 1.2.161.'
    }
}

function Assert-NoReparse([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -Force -LiteralPath $current).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not accepted in fixture paths: $current"
            }
        }
        $current = Split-Path $current -Parent
    }
}

if ($SelfTest) {
    $testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'ShouInstallerBoundary'))
    Assert-ChildPath (Join-Path $testRoot 'run-1/fixture') $testRoot
    Assert-GeneratedIdentity ('Limecloud.ShouAcceptance.' + ('a' * 32))
    Assert-PinnedToolList "本地工具`nvpk    1.2.161    vpk    D:\repo\.config\dotnet-tools.json"
    $rejected = 0
    foreach ($target in @($testRoot, ($testRoot + '-other'), (Join-Path $testRoot '../outside'))) {
        try { Assert-ChildPath $target $testRoot } catch { $rejected++ }
    }
    foreach ($identity in @('Shou', 'Limecloud.Shou', 'Limecloud.ShouAcceptance../Shou')) {
        try { Assert-GeneratedIdentity $identity } catch { $rejected++ }
    }
    foreach ($toolList in @('vpk 1.2.158 vpk', 'other-vpk 1.2.161 vpk', 'vpk 1.2.161-preview vpk')) {
        try { Assert-PinnedToolList $toolList } catch { $rejected++ }
    }
    if ($rejected -ne 9) { throw 'Fixture boundary/tool rejection self-check failed.' }
    Write-Output 'Installer fixture self-check: 9 unsafe paths/identities/tool versions rejected; no files changed.'
    return
}
if (-not $RunGeneratedInstallerFixtures) {
    throw 'Pass -RunGeneratedInstallerFixtures to pack, install, upgrade and uninstall only a newly generated acceptance product. Existing products and installer paths are never accepted.'
}
if (-not $IsWindows -or -not [OperatingSystem]::IsWindowsVersionAtLeast(10, 0, 22000)) {
    throw 'Generated installer acceptance requires native Windows 11.'
}
$ShouProcessArch = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
$ShouOsArch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
if ($ShouProcessArch -ne $ShouOsArch -or $ShouProcessArch.ToString() -notin @('X64', 'Arm64')) {
    throw 'Use native x64 PowerShell on x64 Windows, or native ARM64 PowerShell on ARM64 Windows.'
}
$ShouIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$ShouSid = $ShouIdentity.User
if ([Security.Principal.WindowsPrincipal]::new($ShouIdentity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run installer acceptance without elevation; an elevated build host cannot prove ordinary-user installation.'
}
if ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0 -or -not [Environment]::UserInteractive) {
    throw 'Window startup acceptance requires an interactive current-user desktop session.'
}
if (-not $PublishRoot) { throw 'PublishRoot must contain the current self-contained app and cli directories.' }
$PublishRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PublishRoot)
if (-not $ArtifactsRoot) { $ArtifactsRoot = Join-Path $env:LOCALAPPDATA 'ShouBuild/generated-installer-tests' }
$ArtifactsRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArtifactsRoot)
foreach ($root in @($PublishRoot, $ArtifactsRoot)) {
    $drive = [IO.Path]::GetPathRoot($root)
    if ($drive -notmatch '^[A-Za-z]:\\$' -or [IO.DriveInfo]::new($drive).DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Fixture inputs and evidence must use a fixed local Windows drive.'
    }
    Assert-NoReparse $root
}
$ShouSourceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ShouWindowsRoot = Join-Path $ShouSourceRoot 'apps/windows'
$ShouToolManifest = Join-Path $ShouWindowsRoot '.config/dotnet-tools.json'
$ShouTools = Get-Content -Raw -LiteralPath $ShouToolManifest | ConvertFrom-Json
if ($ShouTools.tools.vpk.version -ne '1.2.161') { throw 'Acceptance requires the pinned vpk 1.2.161 tool.' }
$ShouAppSource = Join-Path $PublishRoot 'app'
$ShouCli = Join-Path $PublishRoot 'cli/shou.exe'
if (-not (Test-Path -LiteralPath $ShouAppSource -PathType Container) -or -not (Test-Path -LiteralPath $ShouCli -PathType Leaf)) {
    throw 'PublishRoot must contain app and cli/shou.exe.'
}
foreach ($item in (Get-ChildItem -LiteralPath $PublishRoot -Recurse -Force)) {
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Payload contains a reparse point: $($item.FullName)" }
}
$ShouRunId = [Guid]::NewGuid().ToString('N')
$ShouPackId = 'Limecloud.ShouAcceptance.' + $ShouRunId
Assert-GeneratedIdentity $ShouPackId
$ShouTitle = 'Shou Installer Acceptance ' + $ShouRunId
$ShouInstallRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA $ShouPackId))
Assert-ChildPath $ShouInstallRoot $env:LOCALAPPDATA
Assert-NoReparse $ShouInstallRoot
$ShouRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $ShouPackId
$ShouShortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) ($ShouTitle + '.lnk')),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) ($ShouTitle + '.lnk'))
)
foreach ($path in @($ShouInstallRoot, $ShouRegistryPath) + $ShouShortcuts) {
    if (Test-Path -LiteralPath $path) { throw "Generated identity collision; no existing product will be touched: $path" }
}
$ShouRunRoot = Join-Path $ArtifactsRoot ('run-' + $ShouRunId)
Assert-ChildPath $ShouRunRoot $ArtifactsRoot
if ($ShouRunRoot.StartsWith($PublishRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Artifacts cannot be created inside PublishRoot.'
}
$null = New-Item -ItemType Directory -Path $ShouRunRoot
$ShouUserRoot = Join-Path $ShouRunRoot 'user-data'
$ShouDataRoot = Join-Path $ShouUserRoot 'Data'
$ShouDiagnosticsRoot = Join-Path $ShouUserRoot 'Diagnostics'
$ShouRuntime = 'win-' + $ShouProcessArch.ToString().ToLowerInvariant()
$ShouStage = 'created'
$ShouApplication = $null
$ShouInstallerPending = $false
$ShouInstalled = $false
$ShouTeardownVerified = $false
$ShouFailure = $null
$ShouSteps = [Collections.Generic.List[object]]::new()

function Write-Checkpoint([string]$Stage, $Details) {
    $script:ShouStage = $Stage
    $ShouSteps.Add([ordered]@{ stage = $Stage; at_utc = [DateTimeOffset]::UtcNow.ToString('O'); details = $Details })
    [ordered]@{
        schema_version = 1; generated_installer_only = $true; verification_complete = $false
        pack_id = $ShouPackId; install_root = $ShouInstallRoot; stage = $Stage; steps = @($ShouSteps.ToArray())
    } | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $ShouRunRoot 'checkpoint.json') -Encoding utf8
}

function New-PrivateDirectory([string]$Path) {
    Assert-ChildPath $Path $ShouRunRoot
    $null = New-Item -ItemType Directory -Path $Path
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($ShouSid)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($ShouSid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Get-PreservedEvidence {
    foreach ($path in @($ShouUserRoot, $ShouDataRoot, $ShouDiagnosticsRoot, (Join-Path $ShouDataRoot 'preserved.txt'), (Join-Path $ShouDiagnosticsRoot 'preserved.txt'))) {
        Assert-NoReparse $path
        $entry = Get-Item -Force -LiteralPath $path
        [ordered]@{
            path = [IO.Path]::GetRelativePath($ShouRunRoot, $path)
            sddl = (Get-Acl -LiteralPath $path).Sddl
            sha256 = if ($entry.PSIsContainer) { $null } else { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
    }
}

function Invoke-FixtureProcess([string]$FilePath, [string[]]$Arguments, [string]$LogName, [string]$WorkingDirectory = $ShouWindowsRoot) {
    $info = [Diagnostics.ProcessStartInfo]::new($FilePath)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WorkingDirectory = $WorkingDirectory
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $info.Environment['SHOU_DATA_DIR'] = $ShouDataRoot
    $info.Environment['SHOU_DIAGNOSTICS_DIR'] = $ShouDiagnosticsRoot
    [ordered]@{ executable = $FilePath; arguments = $Arguments; working_directory = $WorkingDirectory } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ShouRunRoot ($LogName + '-command.json')) -Encoding utf8
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(300000)) {
        throw "Child process is still running (PID $($process.Id)); no process will be killed or installation replayed. Evidence: $ShouRunRoot"
    }
    $output = $stdout.GetAwaiter().GetResult()
    $errorOutput = $stderr.GetAwaiter().GetResult()
    $output | Set-Content -LiteralPath (Join-Path $ShouRunRoot ($LogName + '-stdout.txt')) -Encoding utf8
    $errorOutput | Set-Content -LiteralPath (Join-Path $ShouRunRoot ($LogName + '-stderr.txt')) -Encoding utf8
    if ($process.ExitCode -ne 0) { throw "$LogName failed with exit code $($process.ExitCode). Evidence: $ShouRunRoot" }
    return $output
}

function Assert-InstalledFixture([string]$Version) {
    Assert-GeneratedIdentity $ShouPackId
    Assert-NoReparse $ShouInstallRoot
    $manifestPath = Join-Path $ShouInstallRoot 'current/sq.version'
    Assert-NoReparse $manifestPath
    [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
    $id = $manifest.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='id']").InnerText
    $observedVersion = $manifest.SelectSingleNode("/*[local-name()='package']/*[local-name()='metadata']/*[local-name()='version']").InnerText
    $registration = Get-ItemProperty -LiteralPath $ShouRegistryPath
    if ($id -cne $ShouPackId -or $observedVersion -cne $Version -or $registration.DisplayName -cne $ShouTitle -or
        $registration.DisplayVersion -cne $Version -or $registration.Publisher -cne 'Shou generated acceptance' -or
        [IO.Path]::GetFullPath($registration.InstallLocation).TrimEnd('\') -ine $ShouInstallRoot) {
        throw 'Generated installation identity, version or current-user registration differs; no uninstall command will be executed.'
    }
    $marker = Get-Content -Raw -LiteralPath (Join-Path $ShouInstallRoot 'current/shou-installer-fixture.json') | ConvertFrom-Json
    if ($marker.run_id -cne $ShouRunId -or $marker.pack_id -cne $ShouPackId -or $marker.version -cne $Version) { throw 'Installed fixture marker differs.' }
    $payloadHashes = [ordered]@{}
    foreach ($file in $ShouPublishedHashes.PSObject.Properties) {
        if (-not $file.Name.StartsWith('app/', [StringComparison]::Ordinal)) { continue }
        $name = $file.Name.Substring(4)
        $installedPath = Join-Path $ShouInstallRoot ('current/' + $name)
        Assert-ChildPath $installedPath $ShouInstallRoot
        Assert-NoReparse $installedPath
        $hash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -cne $file.Value) {
            throw "Installed application file differs from the validated payload: $name"
        }
        $payloadHashes[$name] = $hash
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($path in $ShouShortcuts) {
        Assert-NoReparse $path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing generated shortcut: $path" }
        $target = $shell.CreateShortcut($path).TargetPath
        Assert-ChildPath $target $ShouInstallRoot
    }
    Write-Checkpoint ('installed-' + $Version) ([ordered]@{ registration = $registration | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation; payload_sha256 = $payloadHashes; shortcuts = $ShouShortcuts })
}

function Close-FixtureApplication {
    if ($null -eq $script:ShouApplication -or $script:ShouApplication.HasExited) { return }
    # External Setup/uninstall can force-stop processes; close our own idle window normally first.
    $script:ShouApplication.Refresh()
    if (-not $script:ShouApplication.CloseMainWindow() -or -not $script:ShouApplication.WaitForExit(30000)) {
        throw 'Generated application did not close normally; retain it and do not run an installer/uninstaller that could terminate it.'
    }
    if ($script:ShouApplication.ExitCode -ne 0) { throw 'Generated application failed during normal close.' }
    $script:ShouApplication = $null
}

function Test-FixtureStartup([string]$Version) {
    $path = Join-Path $ShouInstallRoot 'current/Shou.Windows.App.exe'
    Assert-NoReparse $path
    $info = [Diagnostics.ProcessStartInfo]::new($path)
    $info.UseShellExecute = $false
    $info.WorkingDirectory = Split-Path $path -Parent
    $info.Environment['SHOU_DATA_DIR'] = $ShouDataRoot
    $info.Environment['SHOU_DIAGNOSTICS_DIR'] = $ShouDiagnosticsRoot
    $script:ShouApplication = [Diagnostics.Process]::Start($info)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Milliseconds 200
        $ShouApplication.Refresh()
        if ($ShouApplication.HasExited) { throw "Generated application exited before opening its window: $($ShouApplication.ExitCode)" }
    } while ($ShouApplication.MainWindowHandle -eq [IntPtr]::Zero -and $clock.Elapsed.TotalSeconds -lt 45)
    if ($ShouApplication.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Generated application did not open a window.' }
    $token = [ShouInstallerFixtureToken]::Inspect($ShouApplication.Handle)
    if ($token[0] -cne $ShouSid.Value -or $token[1] -ne 'False') { throw 'Generated application has a different user or an elevated token.' }
    $processId = $ShouApplication.Id
    Close-FixtureApplication
    Write-Checkpoint ('window-' + $Version) ([ordered]@{ process_id = $processId; user_sid = $token[0]; elevated = $false; normal_close = $true; complete_ui_acceptance = $false })
}

try {
    foreach ($directory in @($ShouUserRoot, $ShouDataRoot, $ShouDiagnosticsRoot)) { New-PrivateDirectory $directory }
    foreach ($directory in @($ShouDataRoot, $ShouDiagnosticsRoot)) {
        [IO.File]::WriteAllText((Join-Path $directory 'preserved.txt'), ('Generated private fixture ' + $ShouRunId))
    }
    $ShouPreserved = @(Get-PreservedEvidence) | ConvertTo-Json -Depth 4 -Compress
    $ShouPreserved | Set-Content -LiteralPath (Join-Path $ShouRunRoot 'preserved-before.json') -Encoding utf8
    $ShouProvenance = @'
import importlib.util, json, subprocess, sys
from pathlib import Path
sys.dont_write_bytecode = True
root, payload = Path(sys.argv[1]), Path(sys.argv[2])
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, root / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
archive = load('shou_archive', 'scripts/package-windows.py')
provenance = load('shou_provenance', 'scripts/package-npm.py')
versions = {}
for kind, stem in [('app', 'Shou.Windows.App'), ('cli', 'shou')]:
    deps = json.loads((payload/kind/(stem+'.deps.json')).read_text(encoding='utf-8-sig'))
    version = next(key.split('/', 1)[1] for key in deps['libraries'] if key.startswith(stem+'/'))
    archive.validate(payload/kind, kind, version, sys.argv[3])
    versions[kind] = version
if 'Velopack/1.2.161' not in json.loads((payload/'app'/'Shou.Windows.App.deps.json').read_text(encoding='utf-8-sig'))['libraries']:
    raise ValueError('The current app must include Velopack 1.2.161 lifecycle handling.')
files = {p.relative_to(payload).as_posix(): archive.digest(p) for p in sorted(payload.rglob('*')) if p.is_file()}
paths = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-c', '-o', '--exclude-standard', '-z']).decode('utf-8').split('\0')
prefixes = ('apps/windows/', 'packages/shou-contracts/', 'packages/shou-core/Sources/Resources/', 'assets/brand/', 'assets/design/', 'scripts/', '.github/workflows/')
inputs = {}
for name in sorted(set(paths)):
    if not (name.startswith(prefixes) or name in ('LICENSE', 'packages/shou-core/Localizable.xcstrings')):
        continue
    path = root/name
    if path.is_symlink():
        raise ValueError('Build inputs cannot be symbolic links: '+name)
    inputs[name] = archive.digest(path) if path.is_file() else None
source = provenance.source_state('HEAD', True)
stable_inputs = {'source_commit':source['source_commit'], 'source_tree':source['source_tree'], 'build_inputs':inputs, 'payload_versions':versions, 'payload_files':files}
Path(sys.argv[4]).write_text(json.dumps({'source':source, 'stable_inputs':stable_inputs, 'stability_scope':'Windows source, generated/shared resources, packaging/workflows and exact published bytes; documentation edits are recorded but excluded'}, indent=2)+'\n', encoding='utf-8')
'@
    $null = Invoke-FixtureProcess 'python' @('-c', $ShouProvenance, $ShouSourceRoot, $PublishRoot, $ShouRuntime, (Join-Path $ShouRunRoot 'source-before.json')) 'source-before' $ShouSourceRoot
    $ShouPublishedHashes = (Get-Content -Raw -LiteralPath (Join-Path $ShouRunRoot 'source-before.json') | ConvertFrom-Json).stable_inputs.payload_files
    $toolList = Invoke-FixtureProcess 'dotnet' @('tool', 'list', '--local') 'local-tools'
    Assert-PinnedToolList $toolList
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
public static class ShouInstallerFixtureToken {
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out SafeAccessTokenHandle token);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool GetTokenInformation(SafeAccessTokenHandle token, int information, out uint value, uint length, out uint needed);
    public static string[] Inspect(IntPtr process) {
        if (!OpenProcessToken(process, 8, out var token)) throw new Win32Exception(Marshal.GetLastWin32Error());
        using (token) {
            if (!GetTokenInformation(token, 20, out uint elevated, 4, out _)) throw new Win32Exception(Marshal.GetLastWin32Error());
            using var identity = new WindowsIdentity(token.DangerousGetHandle());
            return new[] { identity.User.Value, (elevated != 0).ToString() };
        }
    }
}
'@
    $ShouCapabilities = Invoke-FixtureProcess $ShouCli @('capabilities', '--json') 'capabilities'
    $capabilities = ($ShouCapabilities | ConvertFrom-Json).data
    $RuleCleanupAvailable = $ShouRuntime -eq 'win-x64'
    if ($capabilities.mutation_available -ne $RuleCleanupAvailable -or $capabilities.rule_cleanup_available -ne $RuleCleanupAvailable) {
        throw 'Rule-cleanup availability differs from the native runtime scope.'
    }
    foreach ($gate in @('trash_available', 'storage_removal_available', 'privacy_cleanup_available', 'application_uninstall_available', 'startup_control_available')) {
        if ($capabilities.$gate -ne $false) { throw "Expected closed public gate: $gate" }
    }
    Write-Checkpoint 'preflight-passed' ([ordered]@{ runtime = $ShouRuntime; current_user_sid = $ShouSid.Value; host_elevated = $false; public_execution_enabled = $RuleCleanupAvailable })
    foreach ($version in @('0.0.1', '0.0.2')) {
        $payload = Join-Path $ShouRunRoot ('payload-' + $version)
        $output = Join-Path $ShouRunRoot ('packages-' + $version)
        Assert-ChildPath $payload $ShouRunRoot
        Assert-ChildPath $output $ShouRunRoot
        $null = New-Item -ItemType Directory -Path $payload
        Get-ChildItem -Force -LiteralPath $ShouAppSource | Copy-Item -Destination $payload -Recurse
        Copy-Item -LiteralPath (Join-Path $ShouSourceRoot 'LICENSE') -Destination (Join-Path $payload 'SHOU-LICENSE.txt')
        [ordered]@{ run_id = $ShouRunId; pack_id = $ShouPackId; version = $version } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $payload 'shou-installer-fixture.json') -Encoding utf8
        # Preserve all verified inputs; Velopack otherwise excludes createdump.exe and PDB files.
        $null = Invoke-FixtureProcess 'dotnet' @('tool', 'run', 'vpk', '--', 'pack', '--packId', $ShouPackId, '--packVersion', $version,
            '--packDir', $payload, '--mainExe', 'Shou.Windows.App.exe', '--packTitle', $ShouTitle, '--packAuthors', 'Shou generated acceptance',
            '--runtime', ('win10.0.22000-' + $ShouProcessArch.ToString().ToLowerInvariant()), '--channel', $ShouRuntime,
            '--exclude', '^$', '--noDefaultExclude', '--noPortable', '--outputDir', $output) ('pack-' + $version)
        $setup = Join-Path $output ($ShouPackId + '-' + $ShouRuntime + '-Setup.exe')
        Assert-ChildPath $setup $ShouRunRoot
        $setupHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
        Close-FixtureApplication
        if ($ShouInstalled) { Assert-InstalledFixture '0.0.1' }
        $ShouInstallerPending = $true
        $null = Invoke-FixtureProcess $setup @('--silent', '--log', (Join-Path $ShouRunRoot ('install-' + $version + '.log'))) ('install-' + $version)
        $ShouInstallerPending = $false
        $ShouInstalled = $true
        Assert-InstalledFixture $version
        Write-Checkpoint ('setup-' + $version) ([ordered]@{ setup_sha256 = $setupHash; package_version = $version; payload_assembly_version_unchanged = $true })
        Test-FixtureStartup $version
        if ((@(Get-PreservedEvidence) | ConvertTo-Json -Depth 4 -Compress) -cne $ShouPreserved) { throw 'Existing private fixture contents or ACLs changed during installation/upgrade.' }
    }
    $null = Invoke-FixtureProcess 'python' @('-c', $ShouProvenance, $ShouSourceRoot, $PublishRoot, $ShouRuntime, (Join-Path $ShouRunRoot 'source-after.json')) 'source-after' $ShouSourceRoot
    $beforeInputs = (Get-Content -Raw -LiteralPath (Join-Path $ShouRunRoot 'source-before.json') | ConvertFrom-Json).stable_inputs | ConvertTo-Json -Depth 12 -Compress
    $afterInputs = (Get-Content -Raw -LiteralPath (Join-Path $ShouRunRoot 'source-after.json') | ConvertFrom-Json).stable_inputs | ConvertTo-Json -Depth 12 -Compress
    if ($beforeInputs -cne $afterInputs) {
        throw 'Source or original published payload changed during acceptance.'
    }
} catch {
    $ShouFailure = $_
    Write-Checkpoint 'failed' ([ordered]@{ error = $_.Exception.Message })
} finally {
    try {
        Close-FixtureApplication
        if ($ShouInstallerPending) { throw 'An installer did not complete normally; retain its generated identity for independent observation.' }
        if (Test-Path -LiteralPath $ShouRegistryPath) {
            $currentVersion = (Get-ItemProperty -LiteralPath $ShouRegistryPath).DisplayVersion
            if ($currentVersion -notin @('0.0.1', '0.0.2')) { throw 'Unexpected generated installation version; no teardown attempted.' }
            Assert-InstalledFixture $currentVersion
            $updater = Join-Path $ShouInstallRoot 'Update.exe'
            Assert-ChildPath $updater $ShouInstallRoot
            Assert-NoReparse $updater
            # Execute the fixed updater path after identity verification, never a registry command string.
            $null = Invoke-FixtureProcess $updater @('uninstall', '--silent', '--log', (Join-Path $ShouRunRoot 'uninstall.log')) 'uninstall'
        }
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
        while ((Test-Path -LiteralPath $ShouInstallRoot) -and [DateTimeOffset]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 250 }
        foreach ($path in @($ShouInstallRoot, $ShouRegistryPath) + $ShouShortcuts) {
            if (Test-Path -LiteralPath $path) { throw "Generated installer teardown is incomplete; unknown residuals are retained: $path" }
        }
        $after = @(Get-PreservedEvidence) | ConvertTo-Json -Depth 4 -Compress
        $after | Set-Content -LiteralPath (Join-Path $ShouRunRoot 'preserved-after.json') -Encoding utf8
        if ($after -cne $ShouPreserved) { throw 'Existing generated data/diagnostics or their ACLs changed during uninstall.' }
        $ShouTeardownVerified = $true
        Write-Checkpoint 'fixture-removed' ([ordered]@{ registration_absent = $true; install_root_absent = $true; shortcuts_absent = $true; existing_data_and_acl_preserved = $true })
    } catch {
        Write-Checkpoint 'teardown-failed' ([ordered]@{ error = $_.Exception.Message })
        if ($null -eq $ShouFailure) { $ShouFailure = $_ }
    }
}
if ($null -ne $ShouFailure) { throw "Generated installer acceptance failed: $($ShouFailure.Exception.Message). Evidence: $ShouRunRoot" }
[ordered]@{
    schema_version = 1; at_utc = [DateTimeOffset]::UtcNow.ToString('O'); verification_complete = $true
    generated_installer_only = $true; pack_id = $ShouPackId; runtime = $ShouRuntime
    current_user_sid = $ShouSid.Value; host_elevated = $false; install_and_upgrade_passed = $true
    native_window_start_and_normal_close_passed = $true; private_data_and_acl_preserved = $true
    fixture_teardown_verified = $ShouTeardownVerified; source_and_original_payload_stable = $true
    public_execution_enabled = $RuleCleanupAvailable; rule_cleanup_available = $RuleCleanupAvailable
    production_identity_installed = $false; trusted_signature_tested = $false
    complete_ui_tested = $false; other_architecture_tested = $false; steps = @($ShouSteps.ToArray())
} | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $ShouRunRoot 'verification.json') -Encoding utf8
Write-Output "Generated installer acceptance passed. Evidence retained: $ShouRunRoot"
