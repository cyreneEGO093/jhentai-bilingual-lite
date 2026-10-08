#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Collect the Maven metadata/notices of the exact Android release dependencies.

Run the Gradle inventory task first. Only read the local Gradle cache; no keys,
machine paths, or user configuration are copied to the public inventory.
"""
import argparse
import hashlib
import io
import json
import re
import shutil
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--gradle-cache', type=Path, required=True)
args = parser.parse_args()
cache = args.gradle_cache / 'caches/modules-2/files-2.1'
modules = json.loads((root / 'LICENSES/android-dependencies.json').read_text(encoding='utf-8'))
output = root / 'LICENSES/android'
records = []
notices = ['Android runtime dependency notices\n\nGenerated from the resolved Maven packages.\n']
ns = {'p': 'http://maven.apache.org/POM/4.0.0'}

def inherited_licenses(pom, destination, depth=0):
    licenses = [{'name': node.findtext('p:name', '', ns), 'url': node.findtext('p:url', '', ns)}
                for node in pom.findall('p:licenses/p:license', ns)]
    if licenses or depth >= 8:
        return licenses
    parent = pom.find('p:parent', ns)
    if parent is not None:
        group = parent.findtext('p:groupId', '', ns)
        artifact = parent.findtext('p:artifactId', '', ns)
        version = parent.findtext('p:version', '', ns)
        candidates = sorted((cache / group / artifact / version).glob('*/*.pom'))
        if candidates:
            shutil.copyfile(candidates[0], destination / f'parent-{depth}.pom.xml')
            return inherited_licenses(ET.parse(candidates[0]).getroot(), destination, depth + 1)
    return []

def append_notices(archive, destination, prefix=''):
    for entry in archive.infolist():
        if entry.is_dir():
            continue
        name = Path(entry.filename).name
        if re.match(r'(?i)^(license|licence|notice|copying)([._-]|$)', name):
            data = archive.read(entry)
            if len(data) > 2_000_000:
                continue
            safe = re.sub(r'[^A-Za-z0-9_.-]', '_', prefix + entry.filename)
            (destination / safe).write_bytes(data)
            notices.append(f'\n--- {destination.name}/{entry.filename} ---\n' + data.decode('utf-8', errors='replace'))
        elif entry.filename == 'classes.jar':
            with zipfile.ZipFile(io.BytesIO(archive.read(entry))) as nested:
                append_notices(nested, destination, 'classes-')

for item in modules:
    coordinate = f'{item["group"]}:{item["name"]}:{item["version"]}'
    folder = cache / item['group'] / item['name'] / item['version']
    poms = sorted(folder.glob('*/*.pom'))
    artifacts = sorted(p for p in folder.glob('*/*') if p.name in {
        f'{item["name"]}-{item["version"]}.aar', f'{item["name"]}-{item["version"]}.jar'})
    if not poms:
        raise SystemExit(f'Missing resolved Maven files: {coordinate}')
    destination = output / coordinate.replace(':', '_')
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(poms[0], destination / 'pom.xml')
    pom = ET.parse(poms[0]).getroot()
    licenses = inherited_licenses(pom, destination)
    if item['group'] == 'io.flutter':
        licenses = [{'name': 'Flutter BSD-3-Clause and bundled engine notices', 'url': 'https://github.com/flutter/flutter'}]
    notices.append(f'\n=== {coordinate} ===\n' + '\n'.join(f'{lic["name"]}: {lic["url"]}' for lic in licenses))
    if artifacts:
        with zipfile.ZipFile(artifacts[0]) as archive:
            append_notices(archive, destination)
    records.append({**item, 'artifact': artifacts[0].name if artifacts else 'metadata or SDK component',
                    'sha256': hashlib.sha256(artifacts[0].read_bytes()).hexdigest() if artifacts else None,
                    'licenses': licenses, 'project': pom.findtext('p:url', '', ns)})

notices.append('\n--- Apache License 2.0 (AndroidX and other Apache-licensed dependencies) ---\n' + (root / 'LICENSES/Apache-2.0.txt').read_text())
(root / 'LICENSES/android-inventory.json').write_text(json.dumps(records, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
(root / 'LICENSES/android-notices.txt').write_text('\n'.join(notices) + '\n', encoding='utf-8')
missing = [f'{r["group"]}:{r["name"]}' for r in records if not r['licenses']]
print(f'Collected {len(records)} Android runtime artifacts; missing POM license declarations: {missing}')
if missing or any(item['group'] == 'com.google.android.gms' for item in modules):
    raise SystemExit('Resolve missing or non-open-source runtime licenses before packaging.')
