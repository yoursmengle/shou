"""Exercise root release entry points only against generated source/tool fixtures."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    'apps/windows/Directory.Build.props': '<Project><PropertyGroup><Version>3.4.5</Version><Keep>8.9.0</Keep></PropertyGroup></Project>\n',
    'apps/macos/Info.plist': plistlib.dumps({'CFBundleShortVersionString': '3.4.5', 'CFBundleVersion': '3.4.5',
                                          'CFBundleDisplayName': 'Shou 收拾一下'}).decode('utf-8'),
    'apps/cli/Sources/ShouCLI.swift': '@main enum ShouCLI {\n    static let version = "3.4.5"\n    static let other = "8.9.0"\n}\n',
    'packages/shou-npm/package.json': '{\n  "version": "3.4.5",\n  "private": true\n}\n',
}


@unittest.skipUnless(shutil.which('pwsh'), 'PowerShell 7 is required.')
class ReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='shou-generated-release-entry-')
        self.root = Path(self.temporary.name)
        for name, content in SOURCES.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding='utf-8', newline='')
        for name in ('set_version.ps1', 'release.ps1'):
            shutil.copyfile(ROOT / name, self.root / name)

    def tearDown(self):
        self.temporary.cleanup()

    def run_script(self, name, *arguments):
        return subprocess.run(['pwsh', '-NoProfile', '-NonInteractive', '-File', str(self.root / name), *arguments],
                              cwd=self.root.parent, capture_output=True, text=True, encoding='utf-8', timeout=30)

    def snapshot(self):
        return {name: (self.root / name).read_bytes() for name in SOURCES}

    def test_version_updates_all_authoritative_fields_without_reformatting(self):
        before = self.snapshot()
        result = self.run_script('set_version.ps1', '1.23.4')
        self.assertEqual(0, result.returncode, result.stderr)
        names = list(SOURCES)
        props = ET.parse(self.root / names[0]).findtext('.//Version')
        info = plistlib.loads((self.root / names[1]).read_bytes())
        cli = re.search(r'static let version = "([^"]+)"', (self.root / names[2]).read_text(encoding='utf-8'))[1]
        npm = json.loads((self.root / names[3]).read_text(encoding='utf-8'))['version']
        self.assertEqual(['1.23.4'] * 5, [props, info['CFBundleShortVersionString'], info['CFBundleVersion'], cli, npm])
        for name, data in before.items():
            self.assertEqual(data.replace(b'3.4.5', b'1.23.4'), (self.root / name).read_bytes())
        saved = self.snapshot()
        self.assertEqual(0, self.run_script('set_version.ps1', '1.23.4').returncode)
        self.assertEqual(saved, self.snapshot())

    def test_invalid_versions_and_missing_fields_never_partially_update_sources(self):
        before = self.snapshot()
        for version in ('v1.2.3', '1.2', '01.2.3', '1.2.3;exit', '65535.0.0', '999999999999.0.0'):
            with self.subTest(version=version):
                self.assertNotEqual(0, self.run_script('set_version.ps1', version).returncode)
                self.assertEqual(before, self.snapshot())
        plist = self.root / 'apps/macos/Info.plist'
        plist.write_bytes(plist.read_bytes().replace(b'CFBundleVersion', b'MissingVersion'))
        before = self.snapshot()
        self.assertNotEqual(0, self.run_script('set_version.ps1', '1.2.3').returncode)
        self.assertEqual(before, self.snapshot())

    def release_fixture(self, fail_runtime=''):
        scripts = self.root / 'scripts/windows'
        scripts.mkdir(parents=True)
        (scripts / 'build.ps1').write_text(r'''
param($Runtime, $ArtifactsRoot)
Add-Content -LiteralPath $env:SHOU_ENTRY_CALLS -Value "build $Runtime"
if ($Runtime -eq $env:SHOU_ENTRY_FAIL) { throw 'Generated build failure.' }
if ($env:SHOU_ENTRY_FAIL -eq 'change-version') {
    $path = Join-Path $PSScriptRoot '../../apps/windows/Directory.Build.props'
    [IO.File]::WriteAllText($path, [IO.File]::ReadAllText($path).Replace('3.4.5', '3.4.6'))
}
''', encoding='utf-8')
        (scripts / 'package-installer.ps1').write_text(r'''
param($PublishRoot, $OutputDirectory, $Version, $Runtime, $SourceCommit)
Add-Content -LiteralPath $env:SHOU_ENTRY_CALLS -Value "package $Runtime $Version"
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$arch = $Runtime.Substring(4)
$name = "Shou-$Version-windows-$arch-Setup.exe"
if (Test-Path -LiteralPath (Join-Path $OutputDirectory $name)) { throw 'Generated packager refuses old installers.' }
[IO.File]::WriteAllText((Join-Path $OutputDirectory $name), 'Generated installer fixture')
[IO.File]::WriteAllText((Join-Path $OutputDirectory ($name + '.BUILD.json')), '{}')
$lines = foreach ($file in @($name, ($name + '.BUILD.json'))) {
    (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $file)).Hash.ToLowerInvariant() + '  ' + $file
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory "SHA256SUMS-windows-installer-$arch"), ($lines -join "`n") + "`n")
''', encoding='utf-8')
        (self.root / 'driver.ps1').write_text(r'''
param($Script, $OutputDirectory, $Calls, $FailRuntime)
$env:SHOU_ENTRY_CALLS = $Calls
$env:SHOU_ENTRY_FAIL = $FailRuntime
function global:dotnet { $global:LASTEXITCODE = 0; '10.0.402' }
function global:git { $global:LASTEXITCODE = 0; 'a' * 40 }
$beforePath = $env:PATH; $beforeRoot = $env:DOTNET_ROOT; $beforeLocation = Get-Location
try { & $Script -OutputDirectory $OutputDirectory }
finally {
    if ($env:PATH -cne $beforePath -or $env:DOTNET_ROOT -cne $beforeRoot -or
        (Get-Location).Path -cne $beforeLocation.Path) { throw 'Caller environment or location was changed.' }
}
''', encoding='utf-8')
        return ('driver.ps1', str(self.root / 'release.ps1'), str(self.root / 'output with spaces'),
                str(self.root / 'calls.txt'), fail_runtime)

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_release_replaces_same_version_artifacts_and_regenerates_both_architectures(self):
        arguments = self.release_fixture()
        result = self.run_script(*arguments)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(['build win-x64', 'package win-x64 3.4.5', 'build win-arm64', 'package win-arm64 3.4.5'],
                         (self.root / 'calls.txt').read_text(encoding='utf-8-sig').splitlines())
        output = self.root / 'output with spaces'
        lines = (output / 'SHA256SUMS').read_text().splitlines()
        self.assertEqual(4, len(lines))
        for line in lines:
            digest, name = line.split('  ')
            self.assertEqual(digest, hashlib.sha256((output / name).read_bytes()).hexdigest())
        setup = output / 'Shou-3.4.5-windows-x64-Setup.exe'
        setup.write_bytes(b'stale generated installer')
        (output / 'SHA256SUMS').write_text('incomplete prior generated checksum')
        result = self.run_script(*arguments)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(b'Generated installer fixture', setup.read_bytes())
        self.assertEqual(8, len((self.root / 'calls.txt').read_text(encoding='utf-8-sig').splitlines()))
        for line in (output / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split('  ')
            self.assertEqual(digest, hashlib.sha256((output / name).read_bytes()).hexdigest())

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_unknown_files_are_preserved_before_any_old_artifact_is_deleted(self):
        arguments = self.release_fixture()
        self.assertEqual(0, self.run_script(*arguments).returncode)
        output = self.root / 'output with spaces'
        (output / 'personal.txt').write_bytes(b'keep this generated non-release file')
        before = {path.name: path.read_bytes() for path in output.iterdir()}
        result = self.run_script(*arguments)
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(before, {path.name: path.read_bytes() for path in output.iterdir()})
        self.assertEqual(4, len((self.root / 'calls.txt').read_text(encoding='utf-8-sig').splitlines()))

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_another_versions_checksum_is_preserved_before_cleanup(self):
        arguments = self.release_fixture()
        self.assertEqual(0, self.run_script(*arguments).returncode)
        output = self.root / 'output with spaces'
        (output / 'SHA256SUMS').write_text('a' * 64 + '  Shou-9.9.9-windows-x64-Setup.exe\n')
        before = {path.name: path.read_bytes() for path in output.iterdir()}
        self.assertNotEqual(0, self.run_script(*arguments).returncode)
        self.assertEqual(before, {path.name: path.read_bytes() for path in output.iterdir()})

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_release_rejects_directories_with_installer_names(self):
        arguments = self.release_fixture()
        directory = self.root / 'output with spaces/Shou-3.4.5-windows-x64-Setup.exe'
        directory.mkdir(parents=True)
        (directory / 'keep.txt').write_bytes(b'generated directory data')
        self.assertNotEqual(0, self.run_script(*arguments).returncode)
        self.assertEqual(b'generated directory data', (directory / 'keep.txt').read_bytes())

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_release_rejects_a_junction_without_deleting_its_target(self):
        arguments = self.release_fixture()
        foreign = self.root / 'foreign'
        foreign.mkdir()
        marker = foreign / 'Shou-3.4.5-windows-x64-Setup.exe'
        marker.write_bytes(b'keep this generated junction target')
        (self.root / 'make-junction.ps1').write_text(
            'param($Path, $Target)\n$ErrorActionPreference = "Stop"\nNew-Item -ItemType Junction -Path $Path -Target $Target | Out-Null\n',
            encoding='utf-8')
        created = self.run_script('make-junction.ps1', str(self.root / 'output with spaces'), str(foreign))
        self.assertEqual(0, created.returncode, created.stderr)
        self.assertNotEqual(0, self.run_script(*arguments).returncode)
        self.assertEqual(b'keep this generated junction target', marker.read_bytes())

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_build_failure_stops_before_packaging_or_claiming_a_complete_release(self):
        result = self.run_script(*self.release_fixture(fail_runtime='win-x64'))
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(['build win-x64'], (self.root / 'calls.txt').read_text(encoding='utf-8-sig').splitlines())
        self.assertFalse((self.root / 'output with spaces/SHA256SUMS').exists())

    @unittest.skipUnless(os.name == 'nt', 'Windows release orchestration requires Windows.')
    def test_version_changes_during_a_build_cannot_mix_release_versions(self):
        result = self.run_script(*self.release_fixture(fail_runtime='change-version'))
        self.assertNotEqual(0, result.returncode)
        self.assertIn('version changed during the build', result.stderr)
        self.assertEqual(['build win-x64'], (self.root / 'calls.txt').read_text(encoding='utf-8-sig').splitlines())
        self.assertFalse((self.root / 'output with spaces').exists())


if __name__ == '__main__':
    unittest.main()
