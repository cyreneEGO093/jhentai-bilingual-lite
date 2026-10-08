# Third-party notices and source

The application as a combined derivative is distributed under GPL-3.0-only.
JHenTai's original Apache-2.0 notices remain applicable to its original code.
See the root NOTICE for the precise upstream revision and modifications.

`third-party/` contains notices copied from the exact resolved Dart packages;
`dependency-inventory.json` records versions and notice hashes. `pubspec.lock`
records hosted archive hashes and Git revisions. Flutter also embeds its
generated dependency notices in the application's license registry/assets.

The former Syncfusion chart dependency has been removed and replaced with a
Flutter Canvas chart. No Syncfusion runtime is included in this derivative.
The Pinput/SmartAuth dependency has also been replaced with a local Flutter
PIN field, removing unused proprietary Google Play Services SMS/autofill code.

`android-inventory.json` records the resolved Maven runtime components, their
POM license declarations (including inherited declarations), and binary hashes
where available. Preserved POMs/notices are in `android/`. Native notices are
also accessible through the application's license screen. Release packaging
uses the current dependency inventories; obsolete local notice copies are not
part of the release packages.

The resolved Linux-only packages dbus 0.7.10 and upower 0.7.0 use MPL-2.0.
Their original source notices are retained, and no incompatible-secondary-license
declaration was found in their source. For this combined work their source is
additionally available under GPL-3.0-only pursuant to MPL-2.0 section 3.3;
recipients retain their MPL-2.0 rights. Windows and Android do not execute these
Linux implementations.

Distribute the matching application source and dependency-source archive with
the binaries. The dependency-source archive contains the resolved non-SDK Dart
packages in source form, with their original licenses and build scripts. SDK,
toolchain, platform and native-library download versions are specified by the
project, lockfile and plugin build files. Build instructions are in BUILDING.md.
The Flutter SDK revision is pinned there and is available from
https://github.com/flutter/flutter .

Regenerate after `flutter pub get`:

```text
python tool/collect_licenses.py --sources dependency-sources.zip
```

Compatibility references:
- https://www.apache.org/licenses/GPL-compatibility.html
- https://www.mozilla.org/en-US/MPL/2.0/FAQ/#q14

This inventory documents the examined dependencies; it is not a claim that
future dependency updates or redistribution changes need no further review.
