#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Collect notices from exactly the packages resolved by flutter pub get.

Run at the repository root. Optionally pass --sources PATH.zip to retain their
source alongside a release. Flutter SDK libraries are provided by the pinned
Flutter SDK described in BUILDING.md; no machine paths go in the inventory.
"""
import argparse
import hashlib
import json
import re
import shutil
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--sources', type=Path)
args = parser.parse_args()
config_file = root / '.dart_tool/package_config.json'
config = json.loads(config_file.read_text(encoding='utf-8'))
def package_path(package):
    uri = urllib.parse.urljoin(config_file.as_uri(), package['rootUri'])
    return Path(urllib.request.url2pathname(urllib.parse.urlparse(uri).path)).resolve()

flutter_root = package_path(next(p for p in config['packages'] if p['name'] == 'flutter')).parent.parent
output = root / 'LICENSES/third-party'
inventory = []
missing = []
omitted_examples = []
archive = zipfile.ZipFile(args.sources, 'w', zipfile.ZIP_DEFLATED) if args.sources else None
skip_dirs = {'.git', '.dart_tool', '.gradle', '.idea', 'build', 'node_modules', '.pub-cache'}
try:
    for package in sorted(config['packages'], key=lambda p: p['name']):
        name = package['name']
        if name == 'jhentai':
            continue
        source = package_path(package)
        pubspec = (source / 'pubspec.yaml').read_text(encoding='utf-8')
        version = re.search(r'^version:\s*([^\s#]+)', pubspec, re.M)
        sdk = source.is_relative_to(flutter_root)
        candidates = source.iterdir() if sdk else source.rglob('*')
        files = sorted(p for p in candidates if p.is_file() and not p.is_symlink() and
                       not any(part in skip_dirs for part in p.relative_to(source).parts) and
                       p.name.upper().split('.')[0] in {'LICENSE', 'COPYING', 'NOTICE', 'AUTHORS'})
        licenses = [p for p in files if p.name.upper().startswith(('LICENSE', 'COPYING'))]
        if not licenses and sdk and (flutter_root / 'LICENSE').exists():
            files.append(flutter_root / 'LICENSE')
            licenses.append(flutter_root / 'LICENSE')
        if not licenses:
            missing.append(name)
        destination = output / name
        destination.mkdir(parents=True, exist_ok=True)
        hashes = {}
        for file in files:
            relative = file.relative_to(source) if file.is_relative_to(source) else Path(file.name)
            copied = destination / relative
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, copied)
            hashes[relative.as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
        inventory.append({'package': name, 'version': version[1].strip("'\"") if version else 'SDK',
                          'source': 'pinned Flutter SDK' if sdk else 'pubspec.lock',
                          'licenseFiles': hashes})
        if archive and not sdk:
            for file in source.rglob('*'):
                relative = file.relative_to(source)
                if file.is_symlink() or not file.is_file() or any(part in skip_dirs for part in relative.parts):
                    continue
                if file.name in {'local.properties', 'key.properties'} or file.suffix in {'.jks', '.keystore', '.pyc'}:
                    continue
                if relative.parts[0] in {'example', 'examples', 'bin'}:
                    with file.open('rb') as candidate:
                        magic = candidate.read(4)
                    if magic[:2] == b'MZ' or magic in {b'\x7fELF', b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'}:
                        # Published packages can contain compiled demo tools.
                        # Retain their source, not unrelated example executables.
                        omitted_examples.append(f'packages/{name}/{relative.as_posix()}')
                        continue
                archive.write(file, f'packages/{name}/{relative.as_posix()}')
    (root / 'LICENSES/dependency-inventory.json').write_text(
        json.dumps(inventory, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    if archive:
        archive.write(root / 'pubspec.lock', 'pubspec.lock')
        archive.write(root / 'BUILDING.md', 'BUILDING.md')
        archive.writestr('omitted-example-binaries.json', json.dumps(omitted_examples, indent=2) + '\n')
finally:
    if archive:
        archive.close()
print(f'Collected notices for {len(inventory)} resolved packages; missing licenses: {missing}')
if missing:
    raise SystemExit(1)
