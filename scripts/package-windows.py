#!/usr/bin/env python3
"""Validate and archive self-contained Windows preview payloads for GitHub."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import zipfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def machine(path):
    with path.open('rb') as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:2] != b'MZ':
            raise ValueError(f'Invalid PE image: {path}')
        stream.seek(struct.unpack_from('<I', header, 60)[0])
        signature = stream.read(6)
    if len(signature) != 6 or signature[:4] != b'PE\0\0':
        raise ValueError(f'Invalid PE signature: {path}')
    return struct.unpack_from('<H', signature, 4)[0]


def validate(payload, kind, version, runtime):
    if payload.is_symlink() or any(path.is_symlink() for path in payload.rglob('*')):
        raise ValueError('Windows payloads cannot contain symbolic links.')
    stem = 'Shou.Windows.App' if kind == 'app' else 'shou'
    files = [stem + suffix for suffix in ['.exe', '.dll', '.deps.json', '.runtimeconfig.json']]
    files += ['coreclr.dll', 'hostfxr.dll', 'hostpolicy.dll', 'System.Private.CoreLib.dll',
              'Shou.Windows.Core.dll', 'Shou.Windows.Platform.dll',
              'notices/DOTNET-LICENSE.txt', 'notices/DOTNET-THIRD-PARTY-NOTICES.txt', 'notices/WINDOWS-SDK-NOTICE.txt']
    if kind == 'app':
        files += [stem + '.pri', 'Microsoft.UI.Xaml.dll', 'Shou.Windows.Presentation.dll', 'Velopack.dll',
                  'notices/WINDOWS-APP-SDK-NOTICE.txt', 'notices/VELOPACK-LICENSE.txt', 'notices/VELOPACK-NOTICE.txt']
    for name in files:
        if not (payload / name).is_file() or not (payload / name).stat().st_size:
            raise ValueError(f'Missing self-contained {kind} dependency: {name}')
    expected = 0xAA64 if runtime == 'win-arm64' else 0x8664
    for name in [stem + '.exe', 'coreclr.dll', 'hostfxr.dll'] + (['Microsoft.UI.Xaml.dll'] if kind == 'app' else []):
        if machine(payload / name) != expected:
            raise ValueError(f'Architecture mismatch: {name}')
    deps = json.loads((payload / (stem + '.deps.json')).read_text(encoding='utf-8-sig'))
    if deps['runtimeTarget']['name'].rsplit('/', 1)[-1] != runtime or stem + '/' + version not in deps['libraries']:
        raise ValueError('Native dependency RID/version differs from the requested release.')
    configuration = json.loads((payload / (stem + '.runtimeconfig.json')).read_text(encoding='utf-8-sig'))
    frameworks = configuration['runtimeOptions'].get('includedFrameworks', [])
    if not any(value['name'] == 'Microsoft.NETCore.App' and value['version'].startswith('10.') for value in frameworks):
        raise ValueError('A self-contained .NET 10 runtime is required.')
    return stem


def capability_metadata(runtime):
    rule_cleanup = runtime == 'win-x64'
    return {'public_mutation_available': rule_cleanup, 'rule_cleanup_available': rule_cleanup,
            'storage_removal_available': False, 'privacy_cleanup_available': False,
            'mutation_host_requirement': 'native-windows11-x64-rule-cleanup' if rule_cleanup else 'native-acceptance-pending'}


def require_capability_metadata(receipt, runtime):
    if any(type(receipt.get(key)) is not type(value) or receipt.get(key) != value
           for key, value in capability_metadata(runtime).items()):
        raise ValueError('The capability metadata differs from the accepted runtime scope.')


def package(payload_root, output, version, runtime, source, native_checked):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Use a release version and an exact source commit.')
    arch = runtime.removeprefix('win-')
    output.mkdir(parents=True, exist_ok=True)
    receipts = []
    root = Path(__file__).resolve().parents[1]
    for kind in ['app', 'cli']:
        payload = payload_root / kind
        validate(payload, kind, version, runtime)
        name = ('Shou' if kind == 'app' else 'shou-cli') + f'-{version}-windows-{arch}.zip'
        archive = output / name
        if archive.exists():
            raise ValueError(f'Refusing to overwrite an archive: {archive}')
        paths = sorted(path for path in payload.rglob('*') if path.is_file())
        if any(path.is_symlink() for path in payload.rglob('*')):
            raise ValueError('Archive payloads cannot contain symbolic links.')
        if (payload / 'BUILD.json').exists():
            raise ValueError('BUILD.json is reserved for verified release metadata.')
        hashes = {path.relative_to(payload).as_posix(): digest(path) for path in paths}
        receipt = {'format_version': 1, 'version': version, 'source_commit': source, 'configuration': 'Release',
                   'runtime': runtime, 'kind': kind, 'minimum_windows_build': 22000, 'signing': 'unsigned',
                   'distribution': 'portable-preview', 'native_smoke_checked': native_checked,
                   **capability_metadata(runtime), 'files': hashes}
        with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as bundle:
            for path in paths:
                bundle.write(path, path.relative_to(payload).as_posix())
            bundle.write(root / 'LICENSE', 'SHOU-LICENSE.txt')
            bundle.writestr('BUILD.json', json.dumps(receipt, indent=2) + '\n')
        with zipfile.ZipFile(archive) as bundle:
            if bundle.testzip() is not None:
                raise ValueError('Archive integrity validation failed.')
            for name, expected in hashes.items():
                if hashlib.sha256(bundle.read(name)).hexdigest() != expected:
                    raise ValueError('Archived bytes differ from the validated payload.')
        receipts.append({'file': archive.name, 'sha256': digest(archive), 'bytes': archive.stat().st_size})
    (output / ('SHA256SUMS-windows-' + arch)).write_text(''.join(value['sha256'] + '  ' + value['file'] + '\n' for value in receipts), encoding='utf-8')
    print(json.dumps({'version': version, 'runtime': runtime, 'assets': receipts}))


def collect_release_assets(assets, output, version, source):
    verified = {}
    for arch in ('x64', 'arm64'):
        setup = f'Shou-{version}-windows-{arch}-Setup.exe'
        expected = {
            f'SHA256SUMS-windows-{arch}': {f'Shou-{version}-windows-{arch}.zip', f'shou-cli-{version}-windows-{arch}.zip'},
            f'SHA256SUMS-windows-installer-{arch}': {setup, setup + '.BUILD.json'},
        }
        for manifest, names in expected.items():
            recorded = {}
            for line in (assets / manifest).read_text(encoding='utf-8').splitlines():
                match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9.-]+)', line)
                if not match or match[2] not in names or match[2] in recorded:
                    raise ValueError('Unexpected or duplicate Windows release checksum entry.')
                path = assets / match[2]
                if path.is_symlink() or digest(path) != match[1]:
                    raise ValueError('Windows release bytes differ from their final checksum.')
                if (output / path.name).exists():
                    raise ValueError('Refusing to replace an existing release asset.')
                recorded[path.name] = match[1]
            if recorded.keys() != names:
                raise ValueError('A required Windows release asset is missing.')
            verified.update(recorded)
        for kind, prefix in (('app', 'Shou'), ('cli', 'shou-cli')):
            with zipfile.ZipFile(assets / f'{prefix}-{version}-windows-{arch}.zip') as bundle:
                portable = json.loads(bundle.read('BUILD.json'))
            require_capability_metadata(portable, 'win-' + arch)
            if (portable.get('source_commit') != source or portable.get('version') != version
                    or portable.get('runtime') != 'win-' + arch or portable.get('kind') != kind):
                raise ValueError('The portable receipt differs from the requested release.')
        receipt = json.loads((assets / (setup + '.BUILD.json')).read_text(encoding='utf-8-sig'))
        require_capability_metadata(receipt, 'win-' + arch)
        if (receipt['file'] != setup or receipt['sha256'] != verified[setup] or receipt['version'] != version
                or receipt['source_commit'] != source or receipt['runtime'] != 'win-' + arch
                or receipt['install_id'] != 'Limecloud.Shou'
                or receipt['signing'] not in ('unsigned', 'authenticode')
                or (receipt['signing'] == 'authenticode' and not receipt['timestamp_verified'])):
            raise ValueError('The installer receipt differs from the requested release.')
    checksum = output / 'SHA256SUMS'
    existing = checksum.read_text(encoding='utf-8')
    if existing and not existing.endswith('\n'):
        raise ValueError('The existing release checksum file is incomplete.')
    for name in sorted(verified):
        shutil.copyfile(assets / name, output / name)
    with checksum.open('a', encoding='utf-8', newline='\n') as stream:
        stream.write(''.join(f'{verified[name]}  {name}\n' for name in sorted(verified)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--payload-root', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--runtime', choices=['win-x64', 'win-arm64'], required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--native-checked', action='store_true')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--validate-app', action='store_true', help='Validate one App directory without creating an archive.')
    mode.add_argument('--collect-release-assets', action='store_true', help='Copy only final verified Windows assets into a release.')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or not re.fullmatch(r'[0-9a-f]{40}', args.source):
        parser.error('Use a release version and an exact source commit.')
    if args.validate_app:
        validate(args.payload_root, 'app', args.version, args.runtime)
    else:
        if args.output is None:
            parser.error('--output is required when creating archives.')
        if args.collect_release_assets:
            collect_release_assets(args.payload_root.resolve(), args.output.resolve(), args.version, args.source)
        else:
            package(args.payload_root.resolve(), args.output.resolve(), args.version, args.runtime, args.source, args.native_checked)
