import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('windows_release', ROOT / 'scripts/package-windows.py')
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class WindowsReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='shou-generated-windows-release-')
        self.root = Path(self.temporary.name)
        for kind in ['app', 'cli']:
            payload = self.root / 'publish' / kind
            payload.mkdir(parents=True)
            stem = 'Shou.Windows.App' if kind == 'app' else 'shou'
            names = ['coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'System.Private.CoreLib.dll',
                     'Shou.Windows.Core.dll', 'Shou.Windows.Platform.dll', stem + '.exe', stem + '.dll',
                     'notices/DOTNET-LICENSE.txt', 'notices/DOTNET-THIRD-PARTY-NOTICES.txt', 'notices/WINDOWS-SDK-NOTICE.txt']
            if kind == 'app':
                names += ['Microsoft.UI.Xaml.dll', stem + '.pri', 'Shou.Windows.Presentation.dll', 'Velopack.dll',
                          'notices/WINDOWS-APP-SDK-NOTICE.txt', 'notices/VELOPACK-LICENSE.txt', 'notices/VELOPACK-NOTICE.txt',
                          'createdump.exe', 'Shou.Windows.App.pdb']
            image = b'MZ' + b'\0' * 58 + struct.pack('<I', 64) + b'PE\0\0' + struct.pack('<H', 0x8664)
            for name in names:
                path = payload / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(image if path.suffix in ['.exe', '.dll'] else b'generated fixture')
            (payload / (stem + '.deps.json')).write_text(json.dumps({'runtimeTarget': {'name': '.NETCoreApp,Version=v10.0/win-x64'}, 'libraries': {stem + '/0.14.0': {}}}))
            (payload / (stem + '.runtimeconfig.json')).write_text(json.dumps({'runtimeOptions': {'includedFrameworks': [{'name': 'Microsoft.NETCore.App', 'version': '10.0.13'}]}}))

    def tearDown(self):
        self.temporary.cleanup()

    def package(self):
        PACKAGE.package(self.root / 'publish', self.root / 'archives', '0.14.0', 'win-x64', 'a' * 40, True)

    def set_payload_runtime(self, runtime):
        for kind in ('app', 'cli'):
            payload = self.root / 'publish' / kind
            for path in payload.iterdir():
                if path.suffix in ('.exe', '.dll'):
                    image = bytearray(path.read_bytes())
                    struct.pack_into('<H', image, 68, 0xAA64 if runtime == 'win-arm64' else 0x8664)
                    path.write_bytes(image)
            stem = 'Shou.Windows.App' if kind == 'app' else 'shou'
            deps = payload / (stem + '.deps.json')
            document = json.loads(deps.read_text())
            document['runtimeTarget']['name'] = '.NETCoreApp,Version=v10.0/' + runtime
            deps.write_text(json.dumps(document))

    def test_archives_bind_payload_bytes_version_source_and_capability_limits(self):
        self.package()
        archives = sorted((self.root / 'archives').glob('*.zip'))
        self.assertEqual(2, len(archives))
        for archive in archives:
            with zipfile.ZipFile(archive) as bundle:
                receipt = json.loads(bundle.read('BUILD.json'))
                self.assertEqual('0.14.0', receipt['version'])
                self.assertEqual('a' * 40, receipt['source_commit'])
                self.assertTrue(receipt['public_mutation_available'])
                self.assertTrue(receipt['rule_cleanup_available'])
                self.assertFalse(receipt['storage_removal_available'])
                self.assertFalse(receipt['privacy_cleanup_available'])
                self.assertEqual('native-windows11-x64-rule-cleanup', receipt['mutation_host_requirement'])
                self.assertEqual('portable-preview', receipt['distribution'])
                self.assertEqual('unsigned', receipt['signing'])
                self.assertEqual(len(bundle.namelist()), len(set(bundle.namelist())))
                self.assertEqual((ROOT / 'LICENSE').read_bytes(), bundle.read('SHOU-LICENSE.txt'))

    def test_arm64_archives_keep_mutations_unavailable(self):
        self.set_payload_runtime('win-arm64')
        PACKAGE.package(self.root / 'publish', self.root / 'archives', '0.14.0', 'win-arm64', 'a' * 40, False)
        for archive in (self.root / 'archives').glob('*.zip'):
            with zipfile.ZipFile(archive) as bundle:
                receipt = json.loads(bundle.read('BUILD.json'))
            self.assertFalse(receipt['public_mutation_available'])
            self.assertFalse(receipt['rule_cleanup_available'])
            self.assertFalse(receipt['storage_removal_available'])
            self.assertFalse(receipt['privacy_cleanup_available'])
            self.assertEqual('native-acceptance-pending', receipt['mutation_host_requirement'])

    def test_wrong_architecture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Architecture mismatch'):
            PACKAGE.validate(self.root / 'publish/app', 'app', '0.14.0', 'win-arm64')

    def test_missing_native_runtime_is_rejected(self):
        (self.root / 'publish/app/hostfxr.dll').unlink()
        with self.assertRaisesRegex(ValueError, 'dependency'):
            self.package()

    def test_wrong_version_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'RID/version'):
            PACKAGE.validate(self.root / 'publish/cli', 'cli', '0.15.0', 'win-x64')

    def test_framework_dependent_payload_is_rejected(self):
        (self.root / 'publish/cli/shou.runtimeconfig.json').write_text('{"runtimeOptions": {}}')
        with self.assertRaisesRegex(ValueError, 'self-contained'):
            self.package()

    def test_untrusted_link_is_rejected(self):
        try:
            (self.root / 'publish/app/foreign').symlink_to(ROOT / 'LICENSE')
        except OSError as error:
            self.skipTest(f'The host does not grant generated symlink creation: {error}')
        with self.assertRaisesRegex(ValueError, 'symbolic links'):
            self.package()

    def test_reserved_receipt_is_rejected(self):
        (self.root / 'publish/app/BUILD.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'reserved'):
            self.package()

    def test_existing_archive_is_not_replaced(self):
        self.package()
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            self.package()

    def release_assets(self):
        self.package()
        assets = self.root / 'archives'
        self.set_payload_runtime('win-arm64')
        PACKAGE.package(self.root / 'publish', assets, '0.14.0', 'win-arm64', 'a' * 40, False)
        for arch in ('x64', 'arm64'):
            setup = assets / f'Shou-0.14.0-windows-{arch}-Setup.exe'
            setup.write_bytes(b'generated installer fixture')
            receipt = setup.with_name(setup.name + '.BUILD.json')
            receipt.write_text(json.dumps({'file': setup.name, 'sha256': PACKAGE.digest(setup), 'version': '0.14.0',
                'source_commit': 'a' * 40, 'runtime': 'win-' + arch, 'install_id': 'Limecloud.Shou',
                'public_mutation_available': arch == 'x64', 'rule_cleanup_available': arch == 'x64',
                'storage_removal_available': False, 'privacy_cleanup_available': False,
                'mutation_host_requirement': 'native-windows11-x64-rule-cleanup' if arch == 'x64' else 'native-acceptance-pending',
                'signing': 'unsigned', 'timestamp_verified': False}))
            (assets / f'SHA256SUMS-windows-installer-{arch}').write_text(
                ''.join(f'{PACKAGE.digest(path)}  {path.name}\n' for path in (setup, receipt)))
        output = self.root / 'release'
        output.mkdir()
        (output / 'SHA256SUMS').write_text('')
        return assets, output

    def test_release_collection_publishes_only_all_verified_architecture_assets(self):
        assets, output = self.release_assets()
        (assets / 'private-full.nupkg').write_bytes(b'not a public update channel')
        PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)
        self.assertEqual(8, len((output / 'SHA256SUMS').read_text().splitlines()))
        self.assertEqual(9, len(list(output.iterdir())))
        self.assertFalse((output / 'private-full.nupkg').exists())

    def test_release_collection_rejects_tampered_installer_before_copying(self):
        assets, output = self.release_assets()
        (assets / 'Shou-0.14.0-windows-arm64-Setup.exe').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'final checksum'):
            PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)
        self.assertEqual(['SHA256SUMS'], [path.name for path in output.iterdir()])

    def test_release_collection_rejects_another_source_or_missing_architecture(self):
        assets, output = self.release_assets()
        with self.assertRaisesRegex(ValueError, 'receipt'):
            PACKAGE.collect_release_assets(assets, output, '0.14.0', 'b' * 40)
        (assets / 'SHA256SUMS-windows-installer-arm64').write_text('')
        with self.assertRaisesRegex(ValueError, 'missing'):
            PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)

    def test_release_collection_rejects_duplicate_or_foreign_manifest_entries(self):
        assets, output = self.release_assets()
        manifest = assets / 'SHA256SUMS-windows-x64'
        manifest.write_text(manifest.read_text() * 2)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)
        manifest.write_text('a' * 64 + '  ../untrusted.exe\n')
        with self.assertRaisesRegex(ValueError, 'Unexpected'):
            PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)

    def test_release_collection_rejects_false_installer_capability_claims(self):
        assets, output = self.release_assets()
        receipt_path = assets / 'Shou-0.14.0-windows-arm64-Setup.exe.BUILD.json'
        original = json.loads(receipt_path.read_text())
        setup = assets / 'Shou-0.14.0-windows-arm64-Setup.exe'
        for field, value in (('rule_cleanup_available', True), ('public_mutation_available', True),
                             ('storage_removal_available', True), ('privacy_cleanup_available', True),
                             ('mutation_host_requirement', 'any-windows'), ('rule_cleanup_available', 0)):
            with self.subTest(field=field, value=value):
                receipt_path.write_text(json.dumps({**original, field: value}))
                (assets / 'SHA256SUMS-windows-installer-arm64').write_text(
                    ''.join(f'{PACKAGE.digest(path)}  {path.name}\n' for path in (setup, receipt_path)))
                with self.assertRaisesRegex(ValueError, 'capability metadata'):
                    PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)
                self.assertEqual(['SHA256SUMS'], [path.name for path in output.iterdir()])

    def test_release_collection_rejects_false_portable_capability_claims(self):
        assets, output = self.release_assets()
        archive = assets / 'Shou-0.14.0-windows-x64.zip'
        with zipfile.ZipFile(archive) as bundle:
            entries = {name: bundle.read(name) for name in bundle.namelist()}
        receipt = json.loads(entries['BUILD.json'])
        receipt['storage_removal_available'] = True
        entries['BUILD.json'] = json.dumps(receipt).encode()
        with zipfile.ZipFile(archive, 'w') as bundle:
            for name, content in entries.items():
                bundle.writestr(name, content)
        cli = assets / 'shou-cli-0.14.0-windows-x64.zip'
        (assets / 'SHA256SUMS-windows-x64').write_text(
            ''.join(f'{PACKAGE.digest(path)}  {path.name}\n' for path in (archive, cli)))
        with self.assertRaisesRegex(ValueError, 'capability metadata'):
            PACKAGE.collect_release_assets(assets, output, '0.14.0', 'a' * 40)
        self.assertEqual(['SHA256SUMS'], [path.name for path in output.iterdir()])

    def run_installer(self, mode='valid'):
        if sys.platform != 'win32' or not shutil.which('pwsh'):
            self.skipTest('The installer wrapper requires Windows PowerShell 7.')
        runner = self.root / 'installer-contract.ps1'
        runner.write_text(r'''
param([string]$Script, [string]$PublishRoot, [string]$Output, [string]$Source, [string]$Mode)
$ErrorActionPreference = 'Stop'
$FixtureCertificate = [pscustomobject]@{ HasPrivateKey = $true; NotBefore = [DateTime]::Now.AddDays(-1); NotAfter = [DateTime]::Now.AddDays(1);
    EnhancedKeyUsageList = @([pscustomobject]@{ ObjectId = '1.3.6.1.5.5.7.3.3' }); Thumbprint = ('A' * 40); Subject = 'CN=Generated Fixture' }
function global:Get-Item {
    param([string]$LiteralPath)
    if ($LiteralPath.StartsWith('Cert:')) { return $FixtureCertificate }
    Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath
}
function global:Get-AuthenticodeSignature {
    param([string]$LiteralPath)
    if (-not $Mode.StartsWith('signed-')) { return [pscustomobject]@{ Status = 'NotSigned' } }
    [pscustomobject]@{
        Status = $(if ($Mode -eq 'signed-invalid') { 'HashMismatch' } else { 'Valid' });
        SignerCertificate = $(if ($Mode -eq 'signed-other-publisher') { [pscustomobject]@{Thumbprint = ('B' * 40); Subject = 'CN=Other'} } else { $FixtureCertificate });
        TimeStamperCertificate = $(if ($Mode -eq 'signed-no-timestamp') { $null } else { [pscustomobject]@{Subject = 'CN=Timestamp Fixture'} })
    }
}
function global:dotnet {
    if ($args[0] -eq 'tool' -and $args[1] -eq 'restore') { $global:LASTEXITCODE = 0; return }
    $PackDirectory = $args[[Array]::IndexOf($args, '--packDir') + 1]
    $Destination = $args[[Array]::IndexOf($args, '--outputDir') + 1]
    $null = New-Item -ItemType Directory -Path (Join-Path $Destination 'fixture/lib') -Force
    Copy-Item -LiteralPath $PackDirectory -Destination (Join-Path $Destination 'fixture/lib/app') -Recurse
    $Payload = Join-Path $Destination 'fixture/lib/app'
    if ('--noDefaultExclude' -notin $args) { Remove-Item -LiteralPath (Join-Path $Payload 'createdump.exe') }
    if ($args[[Array]::IndexOf($args, '--exclude') + 1] -ne '^$') { Remove-Item -LiteralPath (Join-Path $Payload 'Shou.Windows.App.pdb') }
    [IO.File]::WriteAllBytes((Join-Path $Payload 'Squirrel.exe'), [byte[]](1,2,3))
    if ($Mode -eq 'tampered') { [IO.File]::WriteAllText((Join-Path $Payload 'Shou.Windows.Core.dll'), 'changed after validation') }
    [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $Destination 'fixture'), (Join-Path $Destination 'Limecloud.Shou-0.14.0-full.nupkg'))
    if ($Mode -ne 'missing-setup') { [IO.File]::WriteAllBytes((Join-Path $Destination 'Limecloud.Shou-win-x64-Setup.exe'), [byte[]](4,5,6)) }
    $global:LASTEXITCODE = 0
}
$SigningOptions = @{}
if ($Mode.StartsWith('signed-')) { $SigningOptions = @{ CertificateThumbprint = ('A' * 40); TimestampUrl = 'https://timestamp.example' } }
& $Script -PublishRoot $PublishRoot -OutputDirectory $Output -Version '0.14.0' -Runtime 'win-x64' -SourceCommit $Source @SigningOptions
''', encoding='utf-8')
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        return subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-File', str(runner), '-Script',
            str(ROOT / 'scripts/windows/package-installer.ps1'), '-PublishRoot', str(self.root / 'publish'),
            '-Output', str(self.root / 'installer'), '-Source', source, '-Mode', mode],
            cwd=ROOT, text=True, encoding='utf-8', capture_output=True, timeout=60)

    def test_installer_wrapper_records_final_payload_and_keeps_update_packages_private(self):
        result = self.run_installer()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        output = self.root / 'installer'
        receipt = json.loads((output / 'Shou-0.14.0-windows-x64-Setup.exe.BUILD.json').read_text(encoding='utf-8-sig'))
        self.assertEqual('Limecloud.Shou', receipt['install_id'])
        self.assertEqual('unsigned', receipt['signing'])
        self.assertFalse(receipt['timestamp_verified'])
        self.assertFalse(receipt['lifecycle_accepted'])
        self.assertTrue(receipt['public_mutation_available'])
        self.assertTrue(receipt['rule_cleanup_available'])
        self.assertFalse(receipt['storage_removal_available'])
        self.assertFalse(receipt['privacy_cleanup_available'])
        self.assertEqual('native-windows11-x64-rule-cleanup', receipt['mutation_host_requirement'])
        self.assertIn('BUILD.json', receipt['files'])
        self.assertIn('Squirrel.exe', receipt['files'])
        self.assertIn('SHOU-LICENSE.txt', receipt['files'])
        self.assertIn('createdump.exe', receipt['files'])
        self.assertIn('Shou.Windows.App.pdb', receipt['files'])
        self.assertEqual(3, len(list(output.iterdir())))
        self.assertEqual(PACKAGE.digest(output / receipt['file']), receipt['sha256'])
        rerun = self.run_installer()
        self.assertNotEqual(0, rerun.returncode)
        self.assertIn('Refusing to replace', rerun.stderr)

    def test_installer_wrapper_refuses_missing_setup_or_changed_packaged_payload(self):
        for mode, message in (('missing-setup', 'Setup output is missing'), ('tampered', 'differs from its validated input')):
            with self.subTest(mode=mode):
                result = self.run_installer(mode=mode)
                self.assertNotEqual(0, result.returncode)
                self.assertIn(message, result.stderr)
                output = self.root / 'installer'
                self.assertEqual([], list(output.iterdir()))

    def test_installer_wrapper_rejects_signing_without_https_and_a_paired_certificate(self):
        if sys.platform != 'win32' or not shutil.which('pwsh'):
            self.skipTest('The installer wrapper requires Windows PowerShell 7.')
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        command = ['pwsh', '-NoProfile', '-NonInteractive', '-File', str(ROOT / 'scripts/windows/package-installer.ps1'),
            '-PublishRoot', str(self.root / 'publish'), '-OutputDirectory', str(self.root / 'installer'),
            '-Version', '0.14.0', '-Runtime', 'win-x64', '-SourceCommit', source]
        for extra, message in ((['-CertificateThumbprint', 'a' * 40], 'requires both'),
                (['-CertificateThumbprint', 'a' * 40, '-TimestampUrl', 'http://timestamp.example'], 'Use an HTTPS'),
                (['-CertificateThumbprint', 'a' * 40, '-TimestampUrl', 'https://timestamp.example/a&calc'], 'Use an HTTPS'),
                (['-CertificateThumbprint', 'not-a-thumbprint', '-TimestampUrl', 'https://timestamp.example'], 'exact certificate')):
            with self.subTest(extra=extra):
                result = subprocess.run(command + extra, cwd=ROOT, text=True, encoding='utf-8', capture_output=True, timeout=30)
                self.assertNotEqual(0, result.returncode)
                self.assertIn(message, result.stderr)
                self.assertFalse((self.root / 'installer').exists())

    def test_installer_wrapper_never_publishes_receipts_for_unverified_signatures(self):
        for mode in ('signed-invalid', 'signed-other-publisher', 'signed-no-timestamp'):
            with self.subTest(mode=mode):
                result = self.run_installer(mode=mode)
                self.assertNotEqual(0, result.returncode)
                self.assertIn('does not match the intended publisher', result.stderr)
                self.assertEqual([], list((self.root / 'installer').iterdir()))


if __name__ == '__main__':
    unittest.main()
