# Windows native notices

These notices accompany the native libraries and headers used by the locked
Windows plugins. They supplement, rather than replace, the Dart package notices.

- Microsoft.Web.WebView2 **1.0.992.28**: BSD-3-Clause style license, extracted
  from Microsoft's versioned NuGet package. The plugin's x64 WebView2Loader.dll
  exactly matches that package: SHA-256
  `c4674acf95f0800793a4a6d61132adf5dfa694c218e482d86093494c4e84100a`.
  Package/license: https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.992.28/License
  This loader uses the separately installed Microsoft Edge WebView2 Runtime;
  this application does not redistribute the browser runtime.
- Microsoft.Windows.ImplementationLibrary **1.0.220201.1**: MIT; license copied
  from the NuGet dependency restored by the Windows plugin build.
- Microsoft.Windows.CppWinRT **2.0.220418.1** and **2.0.210806.1**: MIT; licenses
  copied from the restored, versioned NuGet packages.
- Additional vendored headers, including the desktop_webview_window plugin's
  WIL copy, retain their own notices in `../third-party/` and the accompanying
  dependency-source archive.

SQLite's Windows sources are fetched at the version pinned by the
sqlite3_flutter_libs build script. SQLite is dedicated to the public domain:
https://sqlite.org/copyright.html . The plugin's own MIT license is preserved
separately. Flutter, Windows SDK and compiler support/runtime components retain
their own SDK/platform terms; they are not relicensed by this application's GPL.
