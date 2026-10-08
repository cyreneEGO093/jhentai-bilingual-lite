#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Fetch matching open-source Maven source jars for the release source bundle.

HTTP(S)_PROXY environment settings are supported by urllib. SDK engine source
is pinned separately in BUILDING.md. Missing jars are reported for manual review.
"""
import argparse
import concurrent.futures
import hashlib
import json
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--cache', type=Path, required=True)
parser.add_argument('--archive', type=Path, required=True)
args = parser.parse_args()
args.cache.mkdir(parents=True, exist_ok=True)
modules = json.loads((root / 'LICENSES/android-inventory.json').read_text())

def fetch(item):
    group, name, version = item['group'], item['name'], item['version']
    coordinate = f'{group}:{name}:{version}'
    if group == 'io.flutter':
        return {'module': coordinate, 'source': 'Pinned Flutter SDK/engine; see BUILDING.md'}
    if 'bom' in name:
        return {'module': coordinate, 'source': 'Metadata only; POM is included with notices'}
    if group == 'com.google.guava' and name == 'listenablefuture' and version.startswith('9999.0-empty'):
        return {'module': coordinate, 'source': 'Empty conflict-avoidance artifact; implementation source is in Guava'}
    if group == 'org.jetbrains.kotlin' and name == 'kotlin-stdlib-common':
        return {'module': coordinate, 'source': f'Included under commonMain/ in kotlin-stdlib-{version}-sources.jar'}
    filename = f'{name}-{version}-sources.jar'
    repository = 'https://dl.google.com/dl/android/maven2/' if group.startswith('androidx.') else 'https://repo.maven.apache.org/maven2/'
    url = repository + '/'.join(urllib.parse.quote(s, safe='') for s in [*group.split('.'), name, version, filename])
    destination = args.cache / (group + '_' + filename)
    try:
        if not destination.exists():
            with urllib.request.urlopen(url, timeout=45) as response:
                data = response.read()
            if not data.startswith(b'PK'):
                raise ValueError('Source download is not a jar')
            destination.write_bytes(data)
        with zipfile.ZipFile(destination) as archive:
            if archive.testzip() is not None:
                raise ValueError('Invalid source jar')
        return {'module': coordinate, 'url': url, 'file': destination.name,
                'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        return {'module': coordinate, 'url': url, 'missing': type(error).__name__}

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
    results = list(executor.map(fetch, modules))
with zipfile.ZipFile(args.archive, 'w', zipfile.ZIP_DEFLATED) as output:
    for record in results:
        if 'file' in record:
            output.write(args.cache / record['file'], 'maven/' + record['file'])
    output.writestr('source-inventory.json', json.dumps(results, indent=2) + '\n')
    output.write(root / 'BUILDING.md', 'BUILDING.md')
missing = [r['module'] for r in results if 'missing' in r]
print(f'Source jars bundled: {sum("file" in r for r in results)}; review missing: {missing}')
