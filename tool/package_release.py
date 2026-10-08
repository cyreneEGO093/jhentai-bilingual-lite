#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Package already-tested native builds and matching source, without local data.

Run collect_licenses.py first. The output must be outside the source tree.
The Android APK is supplied explicitly to avoid packaging a debug/test APK.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--android-apk', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if output == root or output.is_relative_to(root):
    raise SystemExit('Use an output directory outside the source tree.')
output.mkdir(parents=True, exist_ok=True)
version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M)[1]
stem = f'jhentai-bilingual-lite-{version.replace("+", "-")}'
windows = root / 'build/windows/x64/runner/Release'
apk = args.android_apk.resolve()
if not (windows / 'jhentai_bilingual.exe').is_file() or not apk.is_file():
    raise SystemExit('Both native release builds must exist before packaging.')

def write_zip(target, files):
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path, name in sorted(files, key=lambda item: item[1]):
            archive.write(path, name)

docs = ['LICENSE', 'NOTICE', 'README.md', 'BUILDING.md', 'PRIVACY.bilingual.md']
current_dart = {item['package'] for item in json.loads((root / 'LICENSES/dependency-inventory.json').read_text())}
current_android = {f'{item["group"]}_{item["name"]}_{item["version"]}' for item in json.loads((root / 'LICENSES/android-dependencies.json').read_text())}
def current_notice(name):
    parts = Path(name).parts
    if len(parts) > 2 and parts[:2] == ('LICENSES', 'third-party'):
        return parts[2] in current_dart
    if len(parts) > 2 and parts[:2] == ('LICENSES', 'android'):
        return parts[2] in current_android
    return True

notices = [(root / name, name) for name in docs]
notices += [(p, p.relative_to(root).as_posix()) for p in (root / 'LICENSES').rglob('*') if p.is_file() and current_notice(p.relative_to(root))]
binary_files = [(p, p.relative_to(windows).as_posix()) for p in windows.rglob('*') if p.is_file() and p.suffix != '.pdb']
write_zip(output / f'{stem}-windows-x64.zip', binary_files + notices)
shutil.copyfile(apk, output / f'{stem}-android-arm64.apk')
write_zip(output / f'{stem}-notices.zip', notices)

names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
blocked_parts = {'.git', '.dart_tool', '.gradle', '.kotlin', 'node_modules'}
blocked_roots = {'build', 'work', 'private'}
blocked_names = {'key.properties', 'local.properties', '.env', 'google-services.json', 'firebase_app_id_file.json', 'signing-credentials.json'}
files = []
for name in sorted(set(filter(None, names))):
    relative = Path(name)
    if not current_notice(name):
        continue
    if relative.parts[0] in blocked_roots or any(part in blocked_parts for part in relative.parts) or relative.name in blocked_names or relative.suffix.lower() in {'.jks', '.keystore', '.p12', '.pfx', '.log', '.pdb', '.apk', '.zip'}:
        raise SystemExit(f'Unexpected private or generated file in source inventory: {name}')
    path = root / relative
    if not path.is_file() or path.is_symlink():
        continue
    # Refuse recognizable private credentials instead of silently publishing.
    data = path.read_bytes()
    if re.search(rb'sk-or-v1-[0-9a-fA-F]{32,}|gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', data):
        raise SystemExit(f'Potential credential in source file: {name}')
    files.append((path, name))
if 'pubspec.lock' not in {name for _, name in files}:
    raise SystemExit('The exact dependency lockfile must be tracked.')
write_zip(output / f'{stem}-source.zip', files)
checksums = []
for path in sorted(output.iterdir()):
    if path.is_file() and path.suffix in {'.zip', '.apk'}:
        checksums.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}')
(output / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='utf-8')
print(f'Packaged {len(files)} source files and native artifacts in {output}')
