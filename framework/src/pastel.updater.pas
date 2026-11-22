(* Pastel - the app updates itself.

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
  Part of the Pastel project, MIT License. *)
unit Pastel.Updater;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Http;

type
  TUpdateInfo = record
    Version, Notes, Url, Sha256: string;
  end;

  EUpdateError = class(Exception);

{ True when the manifest has a newer version for this platform. }
function CheckForUpdate(const ManifestUrl, CurrentVersion: string; out Info: TUpdateInfo): Boolean;
{ The same from the manifest's text (tests, a manifest of your own). }
function UpdateFromManifest(const Json, CurrentVersion: string; out Info: TUpdateInfo): Boolean;
{ Downloads it into the temporary folder and checks its SHA-256; the file. }
function DownloadUpdate(const Info: TUpdateInfo; OnProgress: THttpProgressEvent = nil): string;
{ Starts installing it; the app should end (Application.Terminate) when True. }
function InstallUpdate(const FileName: string): Boolean;
{ This platform's name in the manifest: 'windows-x86_64', 'linux-x86_64', 'linux-aarch64', 'android'. }
function UpdatePlatform: string;
{ 1.10.0 > 1.9.2; 1.0.0 > 1.0.0-beta.2: <0, 0, >0 }
function CompareVersions(const A, B: string): Integer;

implementation

uses
  Math, fpjson, jsonparser, Process, Pastel.Crypto, Pastel.Files, Pastel.Env, Pastel.Device
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

function UpdatePlatform: string;
begin
  {$IFDEF ANDROID}
  Result := 'android';
  {$ELSE}{$IFDEF WINDOWS}
  Result := 'windows-' + {$I %FPCTARGETCPU%};
  {$ELSE}{$IFDEF DARWIN}
  Result := 'macos-' + {$I %FPCTARGETCPU%};
  {$ELSE}
  Result := 'linux-' + {$I %FPCTARGETCPU%};
  {$ENDIF}{$ENDIF}{$ENDIF}
end;

function CompareVersions(const A, B: string): Integer;
var
  PA, PB, QA, QB: string;
  SA, SB: TStringArray;
  I, X, Y: Integer;
begin
  PA := A; QA := '';
  if Pos('-', A) > 0 then
  begin
    PA := Copy(A, 1, Pos('-', A) - 1);
    QA := Copy(A, Pos('-', A) + 1, MaxInt);
  end;
  PB := B; QB := '';
  if Pos('-', B) > 0 then
  begin
    PB := Copy(B, 1, Pos('-', B) - 1);
    QB := Copy(B, Pos('-', B) + 1, MaxInt);
  end;
  if (PA <> '') and (PA[1] in ['v', 'V']) then Delete(PA, 1, 1);
  if (PB <> '') and (PB[1] in ['v', 'V']) then Delete(PB, 1, 1);
  SA := PA.Split(['.']);
  SB := PB.Split(['.']);
  for I := 0 to Max(Length(SA), Length(SB)) - 1 do
  begin
    if I < Length(SA) then X := StrToIntDef(SA[I], 0) else X := 0;
    if I < Length(SB) then Y := StrToIntDef(SB[I], 0) else Y := 0;
    if X <> Y then
      Exit(Sign(X - Y));
  end;
  { a release is newer than its betas }
  if (QA = '') and (QB <> '') then Exit(1);
  if (QA <> '') and (QB = '') then Exit(-1);
  if QA = QB then Exit(0);
  SA := QA.Split(['.']);
  SB := QB.Split(['.']);
  for I := 0 to Max(Length(SA), Length(SB)) - 1 do
  begin
    if I >= Length(SA) then Exit(-1);
    if I >= Length(SB) then Exit(1);
    if TryStrToInt(SA[I], X) and TryStrToInt(SB[I], Y) then
    begin
      if X <> Y then Exit(Sign(X - Y));
    end
    else if SA[I] <> SB[I] then
      Exit(Sign(CompareStr(SA[I], SB[I])));
  end;
  Result := 0;
end;

function UpdateFromManifest(const Json, CurrentVersion: string; out Info: TUpdateInfo): Boolean;
var
  D: TJSONData;
  O, Files, F: TJSONObject;
begin
  Info := Default(TUpdateInfo);
  try
    D := GetJSON(Json);
  except
    raise EUpdateError.Create('the update file is not JSON');
  end;
  try
    if not (D is TJSONObject) then
      raise EUpdateError.Create('the update file is not an object');
    O := TJSONObject(D);
    Info.Version := O.Get('version', '');
    Info.Notes := O.Get('notes', '');
    if Info.Version = '' then
      raise EUpdateError.Create('the update file has no "version"');
    Files := O.Get('files', TJSONObject(nil));
    if Files = nil then
      Exit(False);
    F := Files.Get(UpdatePlatform, TJSONObject(nil));
    if F = nil then
      Exit(False);
    Info.Url := F.Get('url', '');
    Info.Sha256 := LowerCase(F.Get('sha256', ''));
    Result := (Info.Url <> '') and (CompareVersions(Info.Version, CurrentVersion) > 0);
  finally
    D.Free;
  end;
end;

function CheckForUpdate(const ManifestUrl, CurrentVersion: string; out Info: TUpdateInfo): Boolean;
var
  R: THttpResponse;
begin
  R := HttpGet(ManifestUrl);
  R.RaiseForStatus;
  Result := UpdateFromManifest(R.Body, CurrentVersion, Info);
end;

function DownloadUpdate(const Info: TUpdateInfo; OnProgress: THttpProgressEvent): string;
var
  C: THttpClient;
  Name: string;
begin
  if Info.Sha256 = '' then
    raise EUpdateError.Create('the update has no sha256: it is not installed unchecked');
  Name := Info.Url;
  if Pos('?', Name) > 0 then
    SetLength(Name, Pos('?', Name) - 1);
  Name := Copy(Name, LastDelimiter('/', Name) + 1, MaxInt);
  if Name = '' then
    Name := 'update';
  {$IFDEF ANDROID}
  { the app's files: the file provider gives them to the installer }
  Result := JoinPath([HomeDir, 'updates', Name]);
  {$ELSE}
  Result := JoinPath([GetTempDir, 'pastel-update-' + IntToStr(GetProcessID), Name]);
  {$ENDIF}
  ForceDirectories(ExtractFileDir(Result));
  C := THttpClient.Create;
  try
    C.OnProgress := OnProgress;
    C.Timeout := 120000;
    C.Download(Info.Url, Result);
  finally
    C.Free;
  end;
  if LowerCase(Sha256File(Result)) <> Info.Sha256 then
  begin
    DeleteFile(Result);
    raise EUpdateError.Create('the downloaded update is not the one the update file names (its SHA-256 differs)');
  end;
end;

function InstallUpdate(const FileName: string): Boolean;
var
  Ext, Target: string;
  P: TProcess;
begin
  Result := False;
  Ext := LowerCase(ExtractFileExt(FileName));
  {$IFDEF ANDROID}
  if Ext <> '.apk' then
    raise EUpdateError.Create('an Android app updates from an .apk');
  Result := OpenUrl(FileName);
  {$ELSE}
  P := TProcess.Create(nil);
  try
    {$IFDEF WINDOWS}
    if (Ext = '.exe') or (Ext = '.msi') then
    begin
      if Ext = '.msi' then
      begin
        P.Executable := 'msiexec';
        P.Parameters.AddStrings(['/i', FileName, '/passive']);
      end
      else
      begin
        { Pastel's installer (NSIS): silent, it starts the app again when done }
        P.Executable := FileName;
        P.Parameters.Add('/S');
      end;
      P.Execute;
      Exit(True);
    end;
    {$ELSE}
    Target := GetEnv('APPIMAGE');
    if (Ext = '.appimage') and (Target <> '') then
    begin
      { the running AppImage replaced by the new one, which starts }
      DeleteFile(Target + '.old');
      if not RenameFile(Target, Target + '.old') then
        raise EUpdateError.CreateFmt('%s cannot be replaced (no permission to its folder?)', [Target]);
      if not RenameFile(FileName, Target) then
      begin
        RenameFile(Target + '.old', Target);
        raise EUpdateError.CreateFmt('%s cannot be replaced', [Target]);
      end;
      fpChmod(Target, &755);
      DeleteFile(Target + '.old');
      P.Executable := Target;
      P.Execute;
      Exit(True);
    end;
    {$ENDIF}
    { anything else (a .deb, a .zip): the system's app for it }
    Result := OpenUrl(FileName);
  finally
    P.Free;
  end;
  {$ENDIF}
end;

end.
