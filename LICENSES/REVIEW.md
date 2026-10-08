# Distribution review — 8.0.16-bilingual.3+337

The combined derivative is released under **GPL-3.0-only**. This review covers
the locked source and Windows x64 / Android arm64 release, not future updates.

## Provenance and compatibility

- JHenTai's base revision and Apache-2.0 copyright are preserved in `NOTICE`
  and `Apache-2.0.txt`. Changed source files identify the derivative changes.
- Bilingual Lite's GPL-3.0-only provenance is recorded in `NOTICE`.
- Apache-2.0 code can be included in GPLv3 works; its existing notices remain.
  Reference: https://www.apache.org/licenses/GPL-compatibility.html
- The 274 resolved Dart/Flutter package records have corresponding license
  files and recorded hashes. Their main licenses are MIT, BSD, Apache-2.0 and
  MPL-2.0; nested third-party notices are retained as well.
- The two MPL-2.0 Linux packages (`dbus`, `upower`) retain MPL source rights
  and are additionally distributed under GPL-3.0-only for this combination,
  as described in `README.md` in this directory.
  Reference: https://www.mozilla.org/en-US/MPL/2.0/FAQ/#q14
- All 77 Android runtime component records have declared licenses. The
  inventory includes Apache-2.0 libraries, SQLite's public-domain code, and
  Flutter's BSD license and engine notices.
- Windows plugin notices include the versioned WebView2 loader, WIL and
  CppWinRT. The separately installed Edge WebView2 Runtime is not bundled.
- Syncfusion and Pinput/SmartAuth with unused Google Play dependencies were
  removed before this release. Obsolete local notice folders are excluded
  using the active dependency inventories.

## Source and notices supplied with releases

Each release supplies the application source ZIP, `dependency-sources.zip`,
`android-dependency-sources.zip`, `native-source-supplement.zip`, license
notices, and SHA-256 checksums alongside the binaries. The application source
includes the lockfile, tests and build/packaging scripts. `BUILDING.md` pins
the Flutter SDK and engine revisions and provides build instructions.
Flutter's generated notices and native notices are included in the app.

The application source and new repository exclude local credentials, private
development reports, user-provided test media and inherited publishing jobs.
Unneeded upstream store screenshots/marketing assets are omitted rather than
assuming the software license grants rights to artwork depicted in them.
Historical upstream documentation is retained with references to its source.

This is a technical distribution review of the supplied files, not a legal
opinion or a guarantee covering third-party services, content or later changes.
