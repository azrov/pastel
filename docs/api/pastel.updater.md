# Pastel.Updater

The app updates itself.

    if CheckForUpdate('https://example.com/shop/update.json', '1.4.2', Update) then
      if Ask('Version ' + Update.Version + ' is there. Update now?') then
      begin
        F := DownloadUpdate(Update);          // checked against its SHA-256
        InstallUpdate(F);                     // the installer runs, the app ends
      end;

  The file on your server (pastel update-manifest writes it from dist/):

    { "version": "1.5.0", "notes": "Faster sync",
      "files": { "windows-x86_64": { "url": "https://.../shop-1.5.0-setup.exe", "sha256": "..." },
                 "linux-x86_64":   { "url": "https://.../shop-1.5.0-x86_64.AppImage", "sha256": "..." },
                 "android":        { "url": "https://.../shop-1.5.0.apk", "sha256": "..." } } }

  InstallUpdate: Windows runs the installer (silently, it starts the app again);
  an AppImage is replaced and started again; a .deb opens in the system's
  installer; Android asks the user to install the .apk ([package.android]
  permissions = ["install_updates"]). Apps from Google Play update through Play.

`uses Pastel.Updater;` · source: [framework/src/pastel.updater.pas](../../framework/src/pastel.updater.pas)

**Contents:** [TUpdateInfo](#tupdateinfo) · [EUpdateError](#eupdateerror) · [CheckForUpdate](#checkforupdate) · [UpdateFromManifest](#updatefrommanifest) · [DownloadUpdate](#downloadupdate) · [InstallUpdate](#installupdate) · [UpdatePlatform](#updateplatform) · [CompareVersions](#compareversions)

## Types

### TUpdateInfo

```pascal
type TUpdateInfo = record
```

| | |
|---|---|
| `Version: string` |  |
| `Notes: string` |  |
| `Url: string` |  |
| `Sha256: string` |  |

### EUpdateError

```pascal
type EUpdateError = class(Exception)
```

## Routines

### CheckForUpdate

```pascal
function CheckForUpdate(const ManifestUrl: string; const CurrentVersion: string; out Info: TUpdateInfo): Boolean
```

True when the manifest has a newer version for this platform.

### UpdateFromManifest

```pascal
function UpdateFromManifest(const Json: string; const CurrentVersion: string; out Info: TUpdateInfo): Boolean
```

The same from the manifest's text (tests, a manifest of your own).

### DownloadUpdate

```pascal
function DownloadUpdate(const Info: TUpdateInfo; OnProgress: THttpProgressEvent = nil): string
```

Downloads it into the temporary folder and checks its SHA-256; the file.

### InstallUpdate

```pascal
function InstallUpdate(const FileName: string): Boolean
```

Starts installing it; the app should end (Application.Terminate) when True.

### UpdatePlatform

```pascal
function UpdatePlatform: string
```

This platform's name in the manifest: 'windows-x86_64', 'linux-x86_64', 'linux-aarch64', 'android'.

### CompareVersions

```pascal
function CompareVersions(const A: string; const B: string): Integer
```

1.10.0 > 1.9.2; 1.0.0 > 1.0.0-beta.2: <0, 0, >0

