{ Pastel - "pastel package": a release build in an archive, ready to hand out.

    pastel package                     for this computer
    pastel package --target windows    a .zip for Windows
    pastel package --all               every platform in pastel.toml

  dist/myapp-1.2.0-linux.tar.gz contains the folder myapp-1.2.0-linux/ with
  the program, README and LICENSE files, and what [package] include lists:

    [package]
    include = ["config.example.toml", "assets"]
    [package.windows]
    include = ["libs/windows/SDL2.dll"]

  Next to every archive is a .sha256 file ("sha256sum -c" checks it).
  Part of the Pastel project, MIT License. }
unit Pastel.Package;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Project, Pastel.Targets;

{ Builds and packs; the archive's path, or '' after an error (reported). }
function PackageProject(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;

{ "pastel package deb": a Debian/Ubuntu package; the .deb's path or ''. }
function PackageDeb(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;

{ "pastel package docker": a folder with a Dockerfile, built into an image
  when docker is installed; the folder or ''. }
function PackageDocker(Project: TPastelProject; const Target: TTarget; Verbose: Boolean; BuildImage: Boolean = True): string;
{ A Windows installer (NSIS): installs for the user, a Start menu entry,
  an uninstaller. Needs makensis (Linux: sudo apt install nsis). }
function PackageInstaller(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
{ A Linux AppImage of a desktop app: one file that runs on most Linux
  systems. appimagetool is downloaded into ~/.pastel/tools the first time. }
function PackageAppImage(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;

{ Lower-case hex SHA-256 of a file. }
type
  TTargetArray = array of TTarget;

{ Android: an installable .apk in dist/, signed (with a debug key unless
  [package.android] keystore names the release key), with the app built for
  every target given (lib/arm64-v8a, lib/armeabi-v7a...). Debug: a debug build. }
function PackageApk(Project: TPastelProject; const Targets: TTargetArray; Verbose: Boolean; Debug: Boolean = False): string;
{ Google Play: an Android App Bundle (.aab) in dist/ with every CPU, signed with
  [package.android] keystore. Needs aapt2 (Android's build tools 28 or newer)
  and bundletool (PASTEL_BUNDLETOOL, or ~/.pastel/android/bundletool.jar). }
function PackageAab(Project: TPastelProject; const Targets: TTargetArray; Verbose: Boolean): string;
{ The Android targets of an .apk: the one named (android-arm), or, for
  "android" and none, the project's Android platforms ([targets] platforms),
  where "android" means every Android CPU this computer can build for. }
function ApkTargets(Project: TPastelProject; const Name: string): TTargetArray;
{ This computer can build for the Android target ("pastel doctor --install android" was run). }
function AndroidTargetReady(const T: TTarget): Boolean;
{ The app's id on Android ([package.android] id, or dev.pastel.<name>). }
function AndroidAppId(Project: TPastelProject): string;
function FileSha256(const FileName: string): string;

type
  TAndroidJar = record
    Path: string;
    Api: Integer;
  end;
  TAndroidJars = array of TAndroidJar;

{ The platforms (android.jar) of the Android SDKs, the newest first. }
function AndroidJars: TAndroidJars;
{ An Android build tool (aapt, d8, zipalign...) of the newest build tools, '' when there is none. }
function AndroidTool(const Name: string): string;
{ The Android SDK folders here ($ANDROID_HOME, $ANDROID_SDK_ROOT, ~/Android/Sdk...), with a path delimiter. }
function AndroidSdkDirs: TStringArray;
{ bundletool's jar (PASTEL_BUNDLETOOL, ~/.pastel/android/bundletool*.jar, the SDK); '' when there is none. }
function FindBundletool: string;

implementation

uses
  Classes, {$IFDEF UNIX}BaseUnix,{$ENDIF} StrUtils,
  DateUtils, libtar, zstream, zipper,
  Math, Pastel.Console, Pastel.Builder, Pastel.Crypto, Pastel.AndroidLibs, Pastel.Runtime, Pastel.WIcon, Pastel.Http, Pastel.Files,
  Pastel.JavaGen, Process;

function FileSha256(const FileName: string): string;
begin
  Result := Sha256File(FileName);
end;

{ ---------------- collecting the files ---------------- }

type
  TEntry = record
    Source: string;    { absolute path }
    Name: string;      { path inside the archive, with / }
    Executable: Boolean;
  end;
  TEntries = array of TEntry;

procedure AddEntry(var Entries: TEntries; const Source, Name: string; Executable: Boolean);
var
  E: TEntry;
begin
  for E in Entries do
    if E.Name = Name then
      Exit;
  SetLength(Entries, Length(Entries) + 1);
  Entries[High(Entries)].Source := Source;
  Entries[High(Entries)].Name := Name;
  Entries[High(Entries)].Executable := Executable;
end;

function IsExecutableFile(const FileName: string): Boolean;
{$IFDEF UNIX}
var
  St: Stat;
begin
  Result := (fpStat(FileName, St) = 0) and ((St.st_mode and &111) <> 0);
end;
{$ELSE}
begin
  Result := False;
end;
{$ENDIF}

procedure AddFolder(var Entries: TEntries; const Dir, Prefix: string);
var
  SR: TSearchRec;
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Base + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        AddFolder(Entries, Base + SR.Name, Prefix + SR.Name + '/')
      else
        AddEntry(Entries, Base + SR.Name, Prefix + SR.Name, IsExecutableFile(Base + SR.Name));
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ "assets", "docs/*.md", "libs/SDL2.dll": relative to the project; a folder
  is copied with what it contains and keeps its name. }
procedure AddPattern(var Entries: TEntries; const Root, Pattern: string);
var
  Path, Dir, RelDir: string;
  SR: TSearchRec;
  Found: Boolean;
begin
  Path := Root + SetDirSeparators(Pattern);
  while (Path <> '') and (Path[Length(Path)] = PathDelim) do
    SetLength(Path, Length(Path) - 1);
  if DirectoryExists(Path) then
  begin
    AddFolder(Entries, Path, ExtractFileName(Path) + '/');
    Exit;
  end;
  Dir := ExtractFilePath(Path);
  RelDir := '';   { files land at the top of the package }
  Found := False;
  if FindFirst(Path, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then
      begin
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          AddFolder(Entries, Dir + SR.Name, SR.Name + '/');
          Found := True;
        end;
      end
      else
      begin
        AddEntry(Entries, Dir + SR.Name, RelDir + SR.Name, IsExecutableFile(Dir + SR.Name));
        Found := True;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  if not Found then
    raise EProjectError.CreateFmt('[package] include: "%s" not found', [Pattern]);
end;

procedure AddStandardFiles(var Entries: TEntries; const Root: string);
var
  SR: TSearchRec;
  Upper: string;
begin
  if FindFirst(Root + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then
        Continue;
      Upper := UpperCase(SR.Name);
      if (Copy(Upper, 1, 6) = 'README') or (Copy(Upper, 1, 7) = 'LICENSE') or
         (Copy(Upper, 1, 7) = 'LICENCE') or (Copy(Upper, 1, 9) = 'CHANGELOG') then
        AddEntry(Entries, Root + SR.Name, SR.Name, False);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ ---------------- writing the archive ---------------- }

procedure WriteTarGz(const Entries: TEntries; const Folder, ArchiveName: string);
var
  Tar: TMemoryStream;
  W: TTarWriter;
  Gz: TGZFileStream;
  E: TEntry;
const
  Normal: TTarPermissions = [tpReadByOwner, tpWriteByOwner, tpReadByGroup, tpReadByOther];
  Exec: TTarPermissions = [tpReadByOwner, tpWriteByOwner, tpExecuteByOwner, tpReadByGroup,
    tpExecuteByGroup, tpReadByOther, tpExecuteByOther];
begin
  Tar := TMemoryStream.Create;
  try
    W := TTarWriter.Create(Tar);
    try
      W.UserName := 'root';
      W.GroupName := 'root';
      W.Permissions := Exec;
      W.AddDir(Folder + '/', Now);
      for E in Entries do
      begin
        if E.Executable then
          W.Permissions := Exec
        else
          W.Permissions := Normal;
        W.AddFile(E.Source, Folder + '/' + E.Name);
      end;
      W.Finalize;
    finally
      W.Free;
    end;
    Gz := TGZFileStream.Create(ArchiveName, gzopenwrite);
    try
      Gz.WriteBuffer(Tar.Memory^, Tar.Size);
    finally
      Gz.Free;
    end;
  finally
    Tar.Free;
  end;
end;

procedure WriteZip(const Entries: TEntries; const Folder, ArchiveName: string);
var
  Z: TZipper;
  E: TEntry;
begin
  Z := TZipper.Create;
  try
    Z.FileName := ArchiveName;
    for E in Entries do
      Z.Entries.AddFileEntry(E.Source, Folder + '/' + E.Name);
    Z.ZipAllFiles;
  finally
    Z.Free;
  end;
end;

function SizeText(const FileName: string): string;
var
  SR: TSearchRec;
  N: Int64;
begin
  N := 0;
  if FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    N := SR.Size;
    FindClose(SR);
  end;
  if N < 1024 * 1024 then
    Result := Format('%d KB', [(N + 1023) div 1024])
  else
    Result := FormatFloat('0.0', N / (1024 * 1024)) + ' MB';
end;

{ Builds a release and collects what goes into a package. }
function Collect(Project: TPastelProject; const Target: TTarget; Verbose: Boolean;
  out ExeName: string; out Entries: TEntries): Boolean;
var
  Opts: TBuildOptions;
  ExePath, F: string;
begin
  Result := False;
  Entries := nil;
  ExeName := '';
  if Project.Kind = 'lib' then
  begin
    Fail('a library is used from its source, so there is nothing to package');
    Hint('package the program that uses it');
    Exit;
  end;
  Opts := Default(TBuildOptions);
  Opts.Target := Target;
  Opts.Release := True;
  Opts.Verbose := Verbose;
  if not BuildProject(Project, Opts, ExePath) then
    Exit;
  ExeName := ExtractFileName(ExePath);
  try
    AddEntry(Entries, Project.Root + ExePath, ExeName, True);
    { SDL2.dll and freetype.dll of a Windows app }
    if Project.Kind = 'app' then
      for F in CopyRuntime(Target, ExtractFileDir(Project.Root + ExePath)) do
        AddEntry(Entries, ExtractFilePath(Project.Root + ExePath) + F, F, False);
    { sqlite3.dll of a Windows program with a database }
    if FileExists(ExtractFilePath(Project.Root + ExePath) + 'units' + PathDelim + 'pastel.db.ppu') and
      (CopyWindowsSqlite(Target, ExtractFileDir(Project.Root + ExePath), ExtractFilePath(Project.Root + ExePath) + 'units') <> '') then
      AddEntry(Entries, ExtractFilePath(Project.Root + ExePath) + 'sqlite3.dll', 'sqlite3.dll', False);
    AddStandardFiles(Entries, Project.Root);
    for F in Project.PackageFilesFor(Target.Name) do
      AddPattern(Entries, Project.Root, F);
  except
    on Err: EProjectError do
    begin
      Fail(Err.Message);
      Exit;
    end;
  end;
  Result := True;
end;

procedure WriteChecksum(const Archive: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add(FileSha256(Archive) + '  ' + ExtractFileName(Archive));
    L.SaveToFile(Archive + '.sha256');
  finally
    L.Free;
  end;
end;

function PackageProject(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
var
  ExeName, Folder, Dist, Archive: string;
  Entries: TEntries;
  IsZip: Boolean;
  E: TEntry;
begin
  Result := '';
  if not Collect(Project, Target, Verbose, ExeName, Entries) then
    Exit;
  Folder := Format('%s-%s-%s', [Project.Name, Project.Version, Target.Name]);
  IsZip := (Target.OS = 'win64') or (Target.OS = 'win32');
  Dist := Project.Root + 'dist' + PathDelim;
  ForceDirectories(Dist);
  if IsZip then
    Archive := Dist + Folder + '.zip'
  else
    Archive := Dist + Folder + '.tar.gz';
  if FileExists(Archive) then
    SysUtils.DeleteFile(Archive);
  if IsZip then
    WriteZip(Entries, Folder, Archive)
  else
    WriteTarGz(Entries, Folder, Archive);

  WriteChecksum(Archive);
  if Verbose then
    for E in Entries do
      WriteLn(Dim('             ' + Folder + '/' + E.Name));
  Status('Packaged', Format('dist%s%s (%d file(s), %s)', [PathDelim, ExtractFileName(Archive),
    Length(Entries), SizeText(Archive)]));
  Result := Archive;
end;

{ ---------------- .deb ---------------- }

function DebArch(const Target: TTarget): string;
begin
  if Target.CPU = 'x86_64' then
    Result := 'amd64'
  else if Target.CPU = 'aarch64' then
    Result := 'arm64'
  else if Target.CPU = 'arm' then
    Result := 'armhf'
  else if Target.CPU = 'i386' then
    Result := 'i386'
  else
    Result := '';
end;

{ Debian package names: lower case letters, digits, + - . }
function DebName(const Name: string): string;
begin
  Result := StringReplace(LowerCase(Name), '_', '-', [rfReplaceAll]);
end;

function IsService(Project: TPastelProject): Boolean;
begin
  Result := Project.Kind = 'service';
end;

{ an ar archive member: the format of .deb files }
procedure ArMember(Dest: TStream; const Name: string; Data: TStream);
var
  Header: string;
  Pad: Byte;
begin
  Header := Format('%-16s%-12d%-6d%-6d%-8s%-10d`'#10, [Name, DateTimeToUnix(Now, False), 0, 0,
    '100644', Data.Size]);
  Dest.WriteBuffer(Header[1], Length(Header));
  Data.Position := 0;
  Dest.CopyFrom(Data, Data.Size);
  if Data.Size mod 2 = 1 then
  begin
    Pad := 10;
    Dest.WriteBuffer(Pad, 1);
  end;
end;

{ a gzip-compressed copy (zstream has no gzip in memory, so via a file) }
function GzipStream(Tar: TMemoryStream): TMemoryStream;
var
  Gz: TGZFileStream;
  Tmp: string;
begin
  Tmp := GetTempFileName(GetTempDir, 'pastel-deb');
  Gz := TGZFileStream.Create(Tmp, gzopenwrite);
  try
    Gz.WriteBuffer(Tar.Memory^, Tar.Size);
  finally
    Gz.Free;
  end;
  Result := TMemoryStream.Create;
  try
    Result.LoadFromFile(Tmp);
  finally
    SysUtils.DeleteFile(Tmp);
  end;
end;

function FileSizeOf(const FileName: string): Int64;
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;

{ A link of [package] links: "shop://" or "https://shop.example.com/app";
  its scheme (lower case), host and path. False: not one. }
function SplitLink(const Link: string; out Scheme, Host, Path: string): Boolean;
var
  P, I: Integer;
  Rest: string;
begin
  Scheme := '';
  Host := '';
  Path := '';
  P := Pos('://', Link);
  if P < 2 then
    Exit(False);
  Scheme := LowerCase(Copy(Link, 1, P - 1));
  for I := 1 to Length(Scheme) do
    if not (Scheme[I] in ['a'..'z', '0'..'9', '+', '-', '.']) or ((I = 1) and not (Scheme[I] in ['a'..'z'])) then
      Exit(False);
  Rest := Copy(Link, P + 3, MaxInt);
  P := Pos('/', Rest);
  if P > 0 then
  begin
    Host := Copy(Rest, 1, P - 1);
    Path := Copy(Rest, P, MaxInt);
  end
  else
    Host := Rest;
  if Path = '/' then
    Path := '';
  { the web's links need the site }
  Result := ((Scheme <> 'http') and (Scheme <> 'https')) or (Host <> '');
end;

{ The schemes of [package] links that are the app's own (not http/https): computers register them. }
function OwnSchemes(Project: TPastelProject): TStringArray;
var
  L, Scheme, Host, Path: string;
begin
  Result := nil;
  for L in Project.Links do
    if SplitLink(L, Scheme, Host, Path) and (Scheme <> 'http') and (Scheme <> 'https') and
      (IndexStr(Scheme, Result) < 0) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Scheme;
    end;
end;

{ the menu entry of a desktop app (freedesktop .desktop file) }
function DesktopEntry(Project: TPastelProject; const Exec, Icon: string): string;
var
  Schemes: TStringArray;
  S: string;
begin
  Schemes := OwnSchemes(Project);
  Result := '[Desktop Entry]' + #10 +
    'Type=Application' + #10 +
    'Name=' + Project.Title + #10;
  if Project.Description <> '' then
    Result := Result + 'Comment=' + Project.Description + #10;
  if Length(Schemes) > 0 then
    Result := Result + 'Exec=' + Exec + ' %u' + #10
  else
    Result := Result + 'Exec=' + Exec + #10;
  Result := Result +
    'Icon=' + Icon + #10 +
    'Terminal=false' + #10 +
    'StartupWMClass=' + ExtractFileName(Exec) + #10 +
    'Categories=Utility;' + #10;
  { the app's links (shop://...) open it: the browser asks the desktop which app has the scheme }
  if Length(Schemes) > 0 then
  begin
    Result := Result + 'MimeType=';
    for S in Schemes do
      Result := Result + 'x-scheme-handler/' + S + ';';
    Result := Result + #10;
  end;
end;

function PackageDeb(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
const
  Normal: TTarPermissions = [tpReadByOwner, tpWriteByOwner, tpReadByGroup, tpReadByOther];
  Exec: TTarPermissions = [tpReadByOwner, tpWriteByOwner, tpExecuteByOwner, tpReadByGroup,
    tpExecuteByGroup, tpReadByOther, tpExecuteByOther];
var
  ExeName, Pkg, Arch, Dir, Dist, Archive, UnitFile, ConfigFile, Depends, Desc, Line, IconPng: string;
  Entries: TEntries;
  E: TEntry;
  Data, Control, DataGz, ControlGz, Deb: TMemoryStream;
  W: TTarWriter;
  Size: Int64;
  Dirs: TStringList;
  Scripts: array[0..2] of string;
  I: Integer;

  procedure AddDirs(const Path: string);
  var
    Parts: TStringArray;
    P, Acc: string;
    K: Integer;
  begin
    Parts := Path.Split(['/']);
    Acc := '.';
    for K := 0 to High(Parts) - 1 do
    begin
      P := Parts[K];
      if P = '' then
        Continue;
      Acc := Acc + '/' + P;
      if Dirs.IndexOf(Acc) < 0 then
      begin
        Dirs.Add(Acc);
        W.Permissions := Exec;
        W.AddDir(Acc + '/', Now);
      end;
    end;
  end;

  procedure AddFile(const Source, Path: string; Executable: Boolean);
  begin
    AddDirs(Path);
    if Executable then
      W.Permissions := Exec
    else
      W.Permissions := Normal;
    W.AddFile(Source, '.' + Path);
    Inc(Size, FileSizeOf(Source));
  end;

  procedure AddText(TarW: TTarWriter; const Content, Path: string; Executable: Boolean);
  begin
    if Executable then
      TarW.Permissions := Exec
    else
      TarW.Permissions := Normal;
    TarW.AddString(Content, Path, Now);
  end;

begin
  Result := '';
  Arch := DebArch(Target);
  if (Target.OS <> 'linux') or (Arch = '') then
  begin
    Fail(Format('a .deb is for Linux; "%s" is not a Linux target', [Target.Name]));
    Hint('use: pastel package deb --target linux-arm64');
    Exit;
  end;
  if (Project.Version = '') or not (Project.Version[1] in ['0'..'9']) then
  begin
    Fail(Format('a .deb needs a version that starts with a digit, not "%s"', [Project.Version]));
    Exit;
  end;
  if not Collect(Project, Target, Verbose, ExeName, Entries) then
    Exit;

  Pkg := DebName(Project.Name);
  Dir := '/opt/' + Project.Name + '/';
  UnitFile := Project.Root + 'deploy' + PathDelim + Project.Name + '.service';
  ConfigFile := Project.Root + 'config.example.toml';
  Size := 0;
  Data := TMemoryStream.Create;
  Control := TMemoryStream.Create;
  Dirs := TStringList.Create;
  DataGz := nil;
  ControlGz := nil;
  Deb := nil;
  try
    { the files }
    W := TTarWriter.Create(Data);
    try
      W.UserName := 'root';
      W.GroupName := 'root';
      W.Permissions := Exec;
      W.AddDir('./', Now);
      for E in Entries do
        AddFile(E.Source, Dir + E.Name, E.Executable);
      if IsService(Project) and FileExists(UnitFile) then
        AddFile(UnitFile, '/usr/lib/systemd/system/' + Project.Name + '.service', False);
      if IsService(Project) and FileExists(ConfigFile) then
        AddFile(ConfigFile, '/etc/' + Project.Name + '/config.toml', False);
      if not IsService(Project) then
      begin
        AddDirs('/usr/bin/x');
        W.AddSymbolicLink('./usr/bin/' + Project.Name, Dir + ExeName, Now);
      end;
      { a desktop app: in the applications menu, with its icon }
      if Project.Kind = 'app' then
      begin
        W.Permissions := Normal;
        AddDirs('/usr/share/applications/x');
        W.AddString(DesktopEntry(Project, Project.Name, Project.Name), './usr/share/applications/' + Project.Name + '.desktop', Now);
        IconPng := Project.Root + 'build' + PathDelim + 'icon-256.png';
        if not FileExists(Project.Root + 'assets' + PathDelim + 'icon.png') or
          (WriteSizedPng(Project.Root + 'assets' + PathDelim + 'icon.png', IconPng, 256) <> '') then
          WriteDefaultIcon(IconPng);
        AddFile(IconPng, '/usr/share/icons/hicolor/256x256/apps/' + Project.Name + '.png', False);
      end;
      W.Finalize;
    finally
      W.Free;
    end;

    { what dpkg needs to know }
    Depends := 'libc6';
    if Project.Kind = 'app' then
      Depends := Depends + ', libsdl2-2.0-0, libfreetype6';
    for Line in Project.DebDepends do
      Depends := Depends + ', ' + Line;
    Desc := Project.Description;
    if Desc = '' then
      Desc := Project.Name;
    Line := Project.Maintainer;
    if Line = '' then
      Line := Project.Name + ' maintainers <root@localhost>';
    W := TTarWriter.Create(Control);
    try
      W.UserName := 'root';
      W.GroupName := 'root';
      W.Permissions := Exec;
      W.AddDir('./', Now);
      AddText(W,
        'Package: ' + Pkg + #10 +
        'Version: ' + Project.Version + #10 +
        'Architecture: ' + Arch + #10 +
        'Maintainer: ' + Line + #10 +
        'Installed-Size: ' + IntToStr((Size + 1023) div 1024) + #10 +
        'Depends: ' + Depends + #10 +
        'Section: misc' + #10 +
        'Priority: optional' + #10 +
        'Description: ' + Desc + #10 +
        ' Made with Pastel. Installed in ' + Dir + #10, './control', False);
      if IsService(Project) then
      begin
        if FileExists(ConfigFile) then
          AddText(W, '/etc/' + Project.Name + '/config.toml' + #10, './conffiles', False);
        if FileExists(UnitFile) then
        begin
          Scripts[0] := '#!/bin/sh' + #10 + 'set -e' + #10 +
            'if [ "$1" = configure ] && [ -d /run/systemd/system ]; then' + #10 +
            '  systemctl daemon-reload' + #10 +
            '  systemctl enable ' + Project.Name + '.service >/dev/null 2>&1 || true' + #10 +
            '  if [ -n "$2" ]; then' + #10 +
            '    systemctl try-restart ' + Project.Name + '.service || true' + #10 +
            '  else' + #10 +
            '    echo "' + Project.Name + ' is installed. Check /etc/' + Project.Name +
            '/config.toml, then: sudo systemctl start ' + Project.Name + '"' + #10 +
            '  fi' + #10 + 'fi' + #10;
          Scripts[1] := '#!/bin/sh' + #10 + 'set -e' + #10 +
            'if [ "$1" = remove ] && [ -d /run/systemd/system ]; then' + #10 +
            '  systemctl disable --now ' + Project.Name + '.service >/dev/null 2>&1 || true' + #10 +
            'fi' + #10;
          Scripts[2] := '#!/bin/sh' + #10 + 'set -e' + #10 +
            'if [ -d /run/systemd/system ]; then' + #10 +
            '  systemctl daemon-reload || true' + #10 + 'fi' + #10;
          AddText(W, Scripts[0], './postinst', True);
          AddText(W, Scripts[1], './prerm', True);
          AddText(W, Scripts[2], './postrm', True);
        end;
      end;
      W.Finalize;
    finally
      W.Free;
    end;

    DataGz := GzipStream(Data);
    ControlGz := GzipStream(Control);
    Deb := TMemoryStream.Create;
    Line := '!<arch>' + #10;
    Deb.WriteBuffer(Line[1], Length(Line));
    Control.Clear;
    Line := '2.0' + #10;
    Control.WriteBuffer(Line[1], Length(Line));
    ArMember(Deb, 'debian-binary', Control);
    ArMember(Deb, 'control.tar.gz', ControlGz);
    ArMember(Deb, 'data.tar.gz', DataGz);

    Dist := Project.Root + 'dist' + PathDelim;
    ForceDirectories(Dist);
    Archive := Dist + Format('%s_%s_%s.deb', [Pkg, Project.Version, Arch]);
    Deb.SaveToFile(Archive);
    WriteChecksum(Archive);
  finally
    Data.Free;
    Control.Free;
    Dirs.Free;
    DataGz.Free;
    ControlGz.Free;
    Deb.Free;
  end;
  if Verbose then
    for I := 0 to High(Entries) do
      WriteLn(Dim('             ' + Dir + Entries[I].Name));
  Status('Packaged', Format('dist%s%s (%s)', [PathDelim, ExtractFileName(Archive), SizeText(Archive)]));
  if IsService(Project) then
    Hint(Format('install: sudo apt install ./dist/%s; settings in /etc/%s/config.toml',
      [ExtractFileName(Archive), Project.Name]))
  else
    Hint(Format('install: sudo apt install ./dist/%s; then run: %s', [ExtractFileName(Archive), Project.Name]));
  Result := Archive;
end;

{ ---------------- docker ---------------- }

function ReadFile(const FileName: string): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure CopyFile(const Source, Dest: string; Executable: Boolean);
var
  F: TFileStream;
  M: TMemoryStream;
begin
  M := TMemoryStream.Create;
  try
    M.LoadFromFile(Source);
    F := TFileStream.Create(Dest, fmCreate);
    try
      F.CopyFrom(M, 0);
    finally
      F.Free;
    end;
  finally
    M.Free;
  end;
  {$IFDEF UNIX}
  if Executable then
    FpChmod(Dest, &755);
  {$ENDIF}
end;

function PackageDocker(Project: TPastelProject; const Target: TTarget; Verbose, BuildImage: Boolean): string;
var
  ExeName, Dist, Dir, Env, Packages, Docker, F: string;
  Entries: TEntries;
  E: TEntry;
  L: TStringList;
  HasWeb: Boolean;
  Code: Integer;
begin
  Result := '';
  if Target.OS <> 'linux' then
  begin
    Fail(Format('container images run Linux programs; "%s" is not a Linux target', [Target.Name]));
    Hint('use: pastel package docker --target linux-arm64');
    Exit;
  end;
  if not Collect(Project, Target, Verbose, ExeName, Entries) then
    Exit;
  Dist := Project.Root + 'dist' + PathDelim;
  Dir := Dist + 'docker-' + Target.Name + PathDelim;
  if DirectoryExists(Dir) then
    DeleteTree(Dir);
  for E in Entries do
  begin
    F := Dir + 'app' + PathDelim + SetDirSeparators(E.Name);
    ForceDirectories(ExtractFileDir(F));
    CopyFile(E.Source, F, E.Executable);
  end;

  Env := UpperCase(StringReplace(Project.Name, '-', '_', [rfReplaceAll]));
  Packages := 'ca-certificates tzdata';
  for F in Project.DebDepends do
    Packages := Packages + ' ' + F;
  HasWeb := FileExists(Project.Root + 'config.toml') and
    (Pos('[server]', ReadFile(Project.Root + 'config.toml')) > 0);
  L := TStringList.Create;
  try
    L.Add('# Made by "pastel package docker". Build: docker build -t ' + DebName(Project.Name) + ' .');
    L.Add('FROM ' + Project.DockerBase);
    L.Add('RUN apt-get update && apt-get install -y --no-install-recommends ' + Packages +
      ' && rm -rf /var/lib/apt/lists/*');
    L.Add('RUN useradd --system --home-dir /var/lib/' + Project.Name + ' --create-home app');
    L.Add('COPY app/ /opt/' + Project.Name + '/');
    L.Add('WORKDIR /var/lib/' + Project.Name);
    L.Add('USER app');
    L.Add('# settings come from environment variables: docker run -e ' + Env + '_LOG_LEVEL=debug ...');
    L.Add('ENV ' + Env + '_LOG_FORMAT=json');
    if HasWeb then
    begin
      L.Add('ENV ' + Env + '_SERVER_ADDRESS=0.0.0.0');
      L.Add('EXPOSE 8080');
      L.Add('HEALTHCHECK CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080"]');
    end;
    L.Add('VOLUME /var/lib/' + Project.Name);
    L.Add('ENTRYPOINT ["/opt/' + Project.Name + '/' + ExeName + '"]');
    L.SaveToFile(Dir + 'Dockerfile');
    L.Clear;
    L.Add('*.sha256');
    L.SaveToFile(Dir + '.dockerignore');
  finally
    L.Free;
  end;
  Status('Prepared', Format('dist%sdocker-%s%sDockerfile', [PathDelim, Target.Name, PathDelim]));
  Result := Dir;

  if not BuildImage then
  begin
    Hint(Format('build it with: docker build -t %s:%s dist/docker-%s', [DebName(Project.Name), Project.Version, Target.Name]));
    Exit;
  end;
  Docker := ExeSearch('docker', GetEnvironmentVariable('PATH'));
  if Docker = '' then
  begin
    Hint('docker is not installed here; build the image elsewhere with:');
    Hint(Format('  docker build -t %s:%s dist/docker-%s', [DebName(Project.Name), Project.Version, Target.Name]));
    Exit;
  end;
  WriteLn(Dim('             docker build -t ' + DebName(Project.Name) + ':' + Project.Version + ' ...'));
  Code := ExecuteProcess(Docker, ['build', '-q', '-t', DebName(Project.Name) + ':' + Project.Version,
    '-t', DebName(Project.Name) + ':latest', Dir]);
  if Code <> 0 then
  begin
    Fail(Format('docker build failed (exit code %d); the Dockerfile is in dist/docker-%s', [Code, Target.Name]));
    Exit('');
  end;
  Status('Image', DebName(Project.Name) + ':' + Project.Version);
  if HasWeb then
    Hint(Format('run: docker run -p 8080:8080 %s', [DebName(Project.Name)]))
  else
    Hint(Format('run: docker run %s', [DebName(Project.Name)]));
end;

{ ---------------- Windows installer ---------------- }

function FindTool(const Name: string): string;
begin
  Result := ExeSearch(Name, GetEnvironmentVariable('PATH'));
end;

function NsisQuote(const S: string): string;
begin
  Result := '"' + StringReplace(StringReplace(S, '$', '$$', [rfReplaceAll]), '"', '$\"', [rfReplaceAll]) + '"';
end;

function PackageInstaller(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
var
  ExeName, Dist, Script, Scheme, Nsi, Ico, Setup, Dir, LastDir, Key, Out_: string;
  Entries: TEntries;
  E: TEntry;
  Args: TStringList;
  Code: Integer;
begin
  Result := '';
  if (Target.OS <> 'win64') and (Target.OS <> 'win32') then
  begin
    Fail(Format('an installer is for Windows; "%s" is not a Windows target', [Target.Name]));
    Hint('use: pastel package installer --target windows');
    Exit;
  end;
  if FindTool('makensis') = '' then
  begin
    Fail('makensis (NSIS) is needed to make a Windows installer');
    {$IFDEF LINUX}
    Hint('install it with: sudo apt install nsis');
    {$ELSE}
    Hint('install NSIS from https://nsis.sourceforge.io');
    {$ENDIF}
    Exit;
  end;
  if not Collect(Project, Target, Verbose, ExeName, Entries) then
    Exit;
  Dist := Project.Root + 'dist' + PathDelim;
  ForceDirectories(Dist);
  Setup := Dist + Format('%s-%s-%s-setup.exe', [Project.Name, Project.Version, Target.Name]);
  Ico := '';
  if FileExists(Project.Root + 'assets' + PathDelim + 'icon.png') then
  begin
    Ico := Project.Root + 'build' + PathDelim + 'installer.ico';
    if WriteIco(Project.Root + 'assets' + PathDelim + 'icon.png', Ico) <> '' then
      Ico := '';
  end;
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + Project.Name;
  Script := 'Unicode true' + LineEnding +
    'SetCompressor /SOLID lzma' + LineEnding +
    'Name ' + NsisQuote(Project.Title) + LineEnding +
    'OutFile ' + NsisQuote(Setup) + LineEnding +
    'InstallDir "$LOCALAPPDATA\Programs\' + Project.Name + '"' + LineEnding +
    'RequestExecutionLevel user' + LineEnding +
    'BrandingText "Made with Pastel"' + LineEnding;
  if Ico <> '' then
    Script := Script + 'Icon ' + NsisQuote(Ico) + LineEnding + 'UninstallIcon ' + NsisQuote(Ico) + LineEnding;
  Script := Script +
    'Page directory' + LineEnding + 'Page instfiles' + LineEnding +
    'UninstPage uninstConfirm' + LineEnding + 'UninstPage instfiles' + LineEnding + LineEnding +
    'Section' + LineEnding;
  LastDir := '?';
  for E in Entries do
  begin
    Dir := ExtractFilePath(StringReplace(E.Name, '/', '\', [rfReplaceAll]));
    if Dir <> LastDir then
    begin
      Script := Script + '  SetOutPath ' + NsisQuote('$INSTDIR\' + ExcludeTrailingBackslash(Dir)) + LineEnding;
      LastDir := Dir;
    end;
    Script := Script + '  File ' + NsisQuote(E.Source) + LineEnding;
  end;
  Script := Script +
    '  SetOutPath "$INSTDIR"' + LineEnding +
    '  WriteUninstaller "$INSTDIR\uninstall.exe"' + LineEnding +
    '  CreateShortCut ' + NsisQuote('$SMPROGRAMS\' + Project.Title + '.lnk') + ' "$INSTDIR\' + ExeName + '"' + LineEnding +
    '  WriteRegStr HKCU "' + Key + '" "DisplayName" ' + NsisQuote(Project.Title) + LineEnding +
    '  WriteRegStr HKCU "' + Key + '" "DisplayVersion" ' + NsisQuote(Project.Version) + LineEnding +
    '  WriteRegStr HKCU "' + Key + '" "DisplayIcon" "$INSTDIR\' + ExeName + '"' + LineEnding +
    '  WriteRegStr HKCU "' + Key + '" "UninstallString" "$INSTDIR\uninstall.exe"' + LineEnding +
    '  WriteRegStr HKCU "' + Key + '" "InstallLocation" "$INSTDIR"' + LineEnding +
    '  WriteRegDWORD HKCU "' + Key + '" "NoModify" 1' + LineEnding +
    '  WriteRegDWORD HKCU "' + Key + '" "NoRepair" 1' + LineEnding;
  if Project.Maintainer <> '' then
    Script := Script + '  WriteRegStr HKCU "' + Key + '" "Publisher" ' + NsisQuote(Project.Maintainer) + LineEnding;
  { the app's links (shop://...): Windows starts it with the address }
  for Scheme in OwnSchemes(Project) do
    Script := Script +
      '  WriteRegStr HKCU "Software\Classes\' + Scheme + '" "" ' + NsisQuote('URL:' + Project.Title) + LineEnding +
      '  WriteRegStr HKCU "Software\Classes\' + Scheme + '" "URL Protocol" ""' + LineEnding +
      '  WriteRegStr HKCU "Software\Classes\' + Scheme + '\DefaultIcon" "" "$INSTDIR\' + ExeName + ',0"' + LineEnding +
      '  WriteRegStr HKCU "Software\Classes\' + Scheme + '\shell\open\command" "" ''"$INSTDIR\' + ExeName +
      '" "%1"''' + LineEnding;
  Script := Script + 'SectionEnd' + LineEnding + LineEnding +
    'Section "Uninstall"' + LineEnding +
    '  Delete ' + NsisQuote('$SMPROGRAMS\' + Project.Title + '.lnk') + LineEnding +
    '  RMDir /r "$INSTDIR"' + LineEnding +
    '  DeleteRegKey HKCU "' + Key + '"' + LineEnding;
  for Scheme in OwnSchemes(Project) do
    Script := Script + '  DeleteRegKey HKCU "Software\Classes\' + Scheme + '"' + LineEnding;
  Script := Script + 'SectionEnd' + LineEnding;
  Nsi := Project.Root + 'build' + PathDelim + 'installer.nsi';
  with TStringList.Create do
  try
    Text := Script;
    SaveToFile(Nsi);
  finally
    Free;
  end;
  if FileExists(Setup) then
    SysUtils.DeleteFile(Setup);
  Args := TStringList.Create;
  try
    Args.Add('-V2');
    Args.Add(Nsi);
    Code := RunCapture(FindTool('makensis'), Args, Project.Root, Out_);
  finally
    Args.Free;
  end;
  if (Code <> 0) or not FileExists(Setup) then
  begin
    Fail('makensis could not make the installer:');
    WriteLn(Out_);
    Exit;
  end;
  WriteChecksum(Setup);
  Status('Packaged', Format('dist%s%s (%s)', [PathDelim, ExtractFileName(Setup), SizeText(Setup)]));
  Hint('it installs for the user (no administrator needed), with a Start menu entry and an uninstaller');
  Result := Setup;
end;

{ ---------------- AppImage ---------------- }

function ToolsDir: string;
begin
  Result := GetEnvironmentVariable('PASTEL_CACHE');
  if Result = '' then
    Result := IncludeTrailingPathDelimiter(GetUserDir) + '.pastel';
  Result := IncludeTrailingPathDelimiter(Result) + 'tools' + PathDelim;
end;

{ the system's copy of a library ('libSDL2-2.0.so.0'), '' when not found }
function FindLibrary(const Name: string): string;
var
  D: string;
begin
  for D in TStringArray.Create('/usr/lib/x86_64-linux-gnu/', '/usr/lib/aarch64-linux-gnu/', '/usr/lib64/', '/usr/lib/', '/lib/x86_64-linux-gnu/') do
    if FileExists(D + Name) then
      Exit(D + Name);
  Result := '';
end;

function PackageAppImage(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
var
  ExeName, Arch, AppDir, Tool, Runtime, Dist, Image, Lib, Out_, Url: string;
  Entries: TEntries;
  E: TEntry;
  Args, Env: TStringList;
  Code: Integer;
  P: TProcess;
begin
  Result := '';
  if Target.OS <> 'linux' then
  begin
    Fail(Format('an AppImage is for Linux; "%s" is not a Linux target', [Target.Name]));
    Exit;
  end;
  if Project.Kind <> 'app' then
  begin
    Fail('an AppImage is for desktop apps; use "pastel package deb" for services and tools');
    Exit;
  end;
  if Target.CPU = 'x86_64' then Arch := 'x86_64' else Arch := 'aarch64';
  if not Collect(Project, Target, Verbose, ExeName, Entries) then
    Exit;
  { the tools, once }
  ForceDirectories(ToolsDir);
  Tool := FindTool('appimagetool');
  try
    if Tool = '' then
    begin
      Tool := ToolsDir + 'appimagetool-x86_64.AppImage';
      if not FileExists(Tool) then
      begin
        Url := 'https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage';
        Status('Downloading', Url);
        HttpDownload(Url, Tool + '.part');
        RenameFile(Tool + '.part', Tool);
      end;
      {$IFDEF UNIX}
      FpChmod(Tool, &755);
      {$ENDIF}
    end;
    Runtime := ToolsDir + 'runtime-' + Arch;
    if not FileExists(Runtime) then
    begin
      Url := 'https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-' + Arch;
      Status('Downloading', Url);
      HttpDownload(Url, Runtime + '.part');
      RenameFile(Runtime + '.part', Runtime);
    end;
  except
    on Ex: Exception do
    begin
      Fail('could not download the AppImage tools: ' + Ex.Message);
      Exit;
    end;
  end;
  { the AppDir: the program in usr/bin, its menu entry and icon at the top }
  AppDir := Project.Root + 'build' + PathDelim + Project.Name + '.AppDir' + PathDelim;
  DeleteTree(ExcludeTrailingPathDelimiter(AppDir));
  ForceDirectories(AppDir + 'usr' + PathDelim + 'bin');
  for E in Entries do
  begin
    ForceDirectories(ExtractFileDir(AppDir + 'usr/bin/' + E.Name));
    CopyFile(E.Source, AppDir + 'usr/bin/' + E.Name, E.Executable);
  end;
  { SDL2 and FreeType go along: not every system has them }
  if Target.Name = HostTarget.Name then
  begin
    ForceDirectories(AppDir + 'usr' + PathDelim + 'lib');
    for Lib in ['libSDL2-2.0.so.0', 'libfreetype.so.6'] do
      if FindLibrary(Lib) <> '' then
        CopyFile(FindLibrary(Lib), AppDir + 'usr/lib/' + Lib, False);
  end;
  with TStringList.Create do
  try
    Text := '#!/bin/sh' + LineEnding +
      'HERE="$(dirname "$(readlink -f "$0")")"' + LineEnding +
      'export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' + LineEnding +
      'exec "$HERE/usr/bin/' + ExeName + '" "$@"' + LineEnding;
    SaveToFile(AppDir + 'AppRun');
    Text := DesktopEntry(Project, Project.Name, Project.Name);
    SaveToFile(AppDir + Project.Name + '.desktop');
  finally
    Free;
  end;
  {$IFDEF UNIX}
  FpChmod(AppDir + 'AppRun', &755);
  {$ENDIF}
  if FileExists(Project.Root + 'assets' + PathDelim + 'icon.png') then
    WriteSizedPng(Project.Root + 'assets' + PathDelim + 'icon.png', AppDir + Project.Name + '.png', 256)
  else
    WriteDefaultIcon(AppDir + Project.Name + '.png');
  Dist := Project.Root + 'dist' + PathDelim;
  ForceDirectories(Dist);
  Image := Dist + Format('%s-%s-%s.AppImage', [Project.Name, Project.Version, Arch]);
  if FileExists(Image) then
    SysUtils.DeleteFile(Image);
  P := TProcess.Create(nil);
  Args := TStringList.Create;
  Env := TStringList.Create;
  try
    P.Executable := Tool;
    P.Parameters.Add('--no-appstream');
    P.Parameters.Add('--runtime-file');
    P.Parameters.Add(Runtime);
    P.Parameters.Add(ExcludeTrailingPathDelimiter(AppDir));
    P.Parameters.Add(Image);
    for Code := 0 to GetEnvironmentVariableCount - 1 do
      P.Environment.Add(GetEnvironmentString(Code));
    P.Environment.Add('ARCH=' + Arch);
    P.Environment.Add('APPIMAGE_EXTRACT_AND_RUN=1');
    P.CurrentDirectory := Project.Root;
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    Out_ := '';
    while P.Running or (P.Output.NumBytesAvailable > 0) do
    begin
      if P.Output.NumBytesAvailable > 0 then
      begin
        SetLength(Url, P.Output.NumBytesAvailable);
        SetLength(Url, P.Output.Read(Url[1], Length(Url)));
        Out_ := Out_ + Url;
      end
      else
        Sleep(20);
    end;
    Code := P.ExitStatus;
  finally
    P.Free;
    Args.Free;
    Env.Free;
  end;
  if (Code <> 0) or not FileExists(Image) then
  begin
    Fail('appimagetool could not make the AppImage:');
    WriteLn(Out_);
    Exit;
  end;
  {$IFDEF UNIX}
  FpChmod(Image, &755);
  {$ENDIF}
  WriteChecksum(Image);
  Status('Packaged', Format('dist%s%s (%s)', [PathDelim, ExtractFileName(Image), SizeText(Image)]));
  Hint(Format('run it on any Linux: chmod +x %s && ./%s', [ExtractFileName(Image), ExtractFileName(Image)]));
  Result := Image;
end;

{ ---- Android ---- }

function AndroidAppId(Project: TPastelProject): string;
var
  C: Char;
  N: string;
begin
  if Project.AndroidId <> '' then
    Exit(Project.AndroidId);
  N := '';
  for C in LowerCase(Project.Name) do
    if C in ['a'..'z', '0'..'9'] then
      N := N + C
    else if C in ['-', '_'] then
      N := N + '_';
  if (N = '') or (N[1] in ['0'..'9', '_']) then
    N := 'app' + N;
  Result := 'dev.pastel.' + N;
end;

{ the Android SDK folder: $ANDROID_HOME, $ANDROID_SDK_ROOT, ~/Android/Sdk or the one of the Linux packages }
function AndroidSdkDirs: TStringArray;
var
  D: string;
begin
  Result := nil;
  for D in TStringArray.Create(GetEnvironmentVariable('ANDROID_HOME'), GetEnvironmentVariable('ANDROID_SDK_ROOT'),
    GetUserDir + 'Android' + PathDelim + 'Sdk', GetEnvironmentVariable('LOCALAPPDATA') + PathDelim + 'Android' + PathDelim + 'Sdk',
    '/usr/lib/android-sdk') do
    if (D <> '') and DirectoryExists(D) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := IncludeTrailingPathDelimiter(D);
    end;
end;

{ '34.0.0' -> 340000 for comparing build-tools folders }
function VersionNumber(const S: string): Int64;
var
  P: TStringArray;
  I: Integer;
begin
  Result := 0;
  P := S.Split(['.', '-']);
  for I := 0 to 2 do
  begin
    Result := Result * 1000;
    if I < Length(P) then
      Result := Result + StrToIntDef(P[I], 0);
  end;
end;

{ a tool of the SDKs' newest build-tools, else on the PATH }
function AndroidTool(const Name: string): string;
var
  Sdk, Best: string;
  SR: TSearchRec;
  Ext: string;
begin
  {$IFDEF WINDOWS}
  Ext := '.exe';
  if (Name = 'apksigner') or (Name = 'd8') then Ext := '.bat';
  {$ELSE}
  Ext := '';
  {$ENDIF}
  { the newest build tools of every SDK first (an old aapt on the PATH, as
    Ubuntu's packages have, cannot read today's platforms), then the PATH }
  Result := '';
  Best := '';
  for Sdk in AndroidSdkDirs do
    if FindFirst(Sdk + 'build-tools' + PathDelim + '*', faDirectory, SR) = 0 then
    begin
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') and FileExists(Sdk + 'build-tools' + PathDelim + SR.Name + PathDelim + Name + Ext) and
          ((Best = '') or (VersionNumber(SR.Name) > VersionNumber(Best))) then
        begin
          Best := SR.Name;
          Result := Sdk + 'build-tools' + PathDelim + SR.Name + PathDelim + Name + Ext;
        end;
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  if Result = '' then
    Result := ExeSearch(Name + Ext, GetEnvironmentVariable('PATH'));
end;

function AndroidJars: TAndroidJars;
var
  Sdk: string;
  SR: TSearchRec;
  N, I, J: Integer;
  T: TAndroidJar;
begin
  Result := nil;
  for Sdk in AndroidSdkDirs do
    if FindFirst(Sdk + 'platforms' + PathDelim + 'android-*', faDirectory, SR) = 0 then
    begin
      repeat
        N := StrToIntDef(Copy(SR.Name, 9, MaxInt), 0);
        if (N > 0) and FileExists(Sdk + 'platforms' + PathDelim + SR.Name + PathDelim + 'android.jar') then
        begin
          T.Path := Sdk + 'platforms' + PathDelim + SR.Name + PathDelim + 'android.jar';
          T.Api := N;
          Result := Concat(Result, [T]);
        end;
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
  for I := 1 to High(Result) do
    for J := I downto 1 do
      if Result[J].Api > Result[J - 1].Api then
      begin
        T := Result[J];
        Result[J] := Result[J - 1];
        Result[J - 1] := T;
      end;
end;

{ The newest platform the build tools can read: older aapt/aapt2 (Ubuntu's
  packages) cannot read the resources of Android 15 and newer. A tiny app that
  uses one of the platform's themes tells. }
function UsableAndroidJar(const Tool, Work: string; Two: Boolean; const Jars: TAndroidJars; out Api: Integer): string;
var
  Dir, Output: string;
  I: Integer;
  L, Args: TStringList;
begin
  Result := '';
  Api := 0;
  Dir := Work + 'probe' + PathDelim;
  ForceDirectories(Dir);
  L := TStringList.Create;
  Args := TStringList.Create;
  try
    L.Text := '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.pastel.probe">' +
      '<application android:theme="@android:style/Theme.DeviceDefault"/></manifest>';
    L.SaveToFile(Dir + 'AndroidManifest.xml');
    for I := 0 to High(Jars) do
    begin
      Args.Clear;
      if Two then
        Args.AddStrings(['link', '-o', 'probe.apk', '-I', Jars[I].Path, '--manifest', 'AndroidManifest.xml'])
      else
        Args.AddStrings(['package', '-f', '-M', 'AndroidManifest.xml', '-I', Jars[I].Path, '-F', 'probe.apk']);
      if (RunCapture(Tool, Args, Dir, Output) = 0) and FileExists(Dir + 'probe.apk') then
      begin
        Api := Jars[I].Api;
        Exit(Jars[I].Path);
      end;
      DeleteFile(Dir + 'probe.apk');
    end;
  finally
    Args.Free;
    L.Free;
    DeleteTree(ExcludeTrailingPathDelimiter(Dir));
  end;
end;

function XmlText(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '\''', [rfReplaceAll]);
end;

{ 1.2.3 -> 10203 }
function VersionCode(const Version: string): Integer;
var
  P: TStringArray;
  I: Integer;
begin
  Result := 0;
  P := Version.Split(['.', '-', '+']);
  for I := 0 to 2 do
  begin
    Result := Result * 100;
    if I < Length(P) then
      Result := Result + Min(99, StrToIntDef(P[I], 0));
  end;
  Result := Max(1, Result);
end;

{ the files under Dir, relative to it }
function FindAllFilesIn(const Dir: string): TStringArray;

  procedure Walk(const Rel: string);
  var
    SR: TSearchRec;
  begin
    if FindFirst(Dir + Rel + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        if (SR.Attr and faDirectory) <> 0 then
          Walk(Rel + SR.Name + PathDelim)
        else
          Result := Concat(Result, [Rel + SR.Name]);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

begin
  Result := nil;
  Walk('');
end;

function AndroidTargetReady(const T: TTarget): Boolean;
var
  Fpc: string;
begin
  Fpc := FindFpc;
  Result := (T.OS = 'android') and (Fpc <> '') and AndroidLibsReady(T) and CrossCompilerReady(Fpc, T) and
    FileExists(UserRtlDir(Fpc, T) + 'system.ppu');
end;

function ApkTargets(Project: TPastelProject; const Name: string): TTargetArray;

  procedure AddTarget(const T: TTarget);
  var
    X: TTarget;
  begin
    for X in Result do
      if X.Name = T.Name then
        Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := T;
  end;

  procedure AddReady;
  var
    I, Before: Integer;
  begin
    Before := Length(Result);
    for I := Low(KnownTargets) to High(KnownTargets) do
      if (KnownTargets[I].OS = 'android') and AndroidTargetReady(KnownTargets[I]) then
        AddTarget(KnownTargets[I]);
    if Length(Result) = Before then
      for I := Low(KnownTargets) to High(KnownTargets) do
        if KnownTargets[I].Name = 'android-arm64' then
          AddTarget(KnownTargets[I]);     { building says what is missing }
  end;

var
  T: TTarget;
  P: string;
  Any: Boolean;
begin
  Result := nil;
  if (Name <> '') and not SameText(Name, 'android') then
  begin
    { one, or several: --target android-arm64,android-arm }
    for P in Name.Split([',']) do
      if SameText(Trim(P), 'android') then
        AddReady
      else if FindTarget(Trim(P), T) then
        AddTarget(T);
    Exit;
  end;
  Any := False;
  for P in Project.Platforms do
    if SameText(P, 'android') then
    begin
      AddReady;
      Any := True;
    end
    else if FindTarget(P, T) and (T.OS = 'android') then
    begin
      AddTarget(T);
      Any := True;
    end;
  if not Any then
    AddReady;
end;

{ a jar of bundletool: PASTEL_BUNDLETOOL, or bundletool*.jar in ~/.pastel/android/ or the Android SDK }
function FindBundletool: string;
var
  Dir: string;
  SR: TSearchRec;
begin
  Result := GetEnvironmentVariable('PASTEL_BUNDLETOOL');
  if (Result <> '') and FileExists(Result) then
    Exit;
  Result := '';
  for Dir in Concat([PastelHome + 'android' + PathDelim], AndroidSdkDirs) do
    if FindFirst(Dir + 'bundletool*.jar', faAnyFile, SR) = 0 then
    begin
      Result := Dir + SR.Name;
      FindClose(SR);
      Exit;
    end;
end;

{ src/java/**/*.java with Pastel's activity (framework/android/java), Extra (the
  libraries' R classes) and the libraries' jars -> Work/classes.dex (classes2.dex...),
  with d8 (build tools 28 and newer) or dx; '' or what went wrong }
function DexProjectJava(Project: TPastelProject; const Jar, Work: string; const LibJars, Extra: TStringArray;
  MinApi: Integer): string;
var
  Src, Classes_, D8, Dx, Output, F: string;
  Args: TStringList;
  Zip: TZipper;
  Files: TStringArray;
begin
  Src := ExpandFileName(IncludeTrailingPathDelimiter(FrameworkDir) + '..' + PathDelim + 'android' + PathDelim + 'java');
  Classes_ := Work + 'java' + PathDelim;
  { framework/android/stubs.jar: Android's newer classes Pastel's Java uses (compiled against, not put in) }
  Result := CompileJava(Project.Root, Jar, Classes_, Concat(ListFiles(Src, '*.java', True), Extra),
    Concat([ExpandFileName(Src + PathDelim + '..' + PathDelim + 'stubs.jar')], LibJars));
  if Result <> '' then
    Exit;
  if Length(LibJars) > 0 then
    Status('Dexing', Format('the app''s Java with Pastel''s and %d library jar(s)', [Length(LibJars)]))
  else
    Status('Dexing', 'the app''s Java (src/java) with Pastel''s');
  for F in ListFiles(Work, 'classes*.dex', False) do
    DeleteFile(F);
  Args := TStringList.Create;
  try
    D8 := AndroidTool('d8');
    if D8 <> '' then
    begin
      { d8 takes a jar of the classes }
      Zip := TZipper.Create;
      try
        Zip.FileName := Work + 'java.jar';
        Files := ListFiles(Classes_, '*.class', True);
        for F in Files do
          Zip.Entries.AddFileEntry(F, StringReplace(ExtractRelativePath(Classes_, F), PathDelim, '/', [rfReplaceAll]));
        Zip.ZipAllFiles;
      finally
        Zip.Free;
      end;
      Args.AddStrings(['--min-api', IntToStr(MinApi), '--lib', Jar, '--output', Work, Work + 'java.jar']);
      Args.AddStrings(LibJars);
      if RunCapture(D8, Args, Work, Output) <> 0 then
        Exit('d8: ' + Trim(Output));
    end
    else
    begin
      Dx := AndroidTool('dx');
      if Dx = '' then
        Dx := ExeSearch('dalvik-exchange', GetEnvironmentVariable('PATH'));
      if Dx = '' then
        Exit('the Java files in src/java need d8 (Android''s build tools 28 or newer) or dx');
      if Length(LibJars) > 0 then
      begin
        { more than 64K methods in classes2.dex... }
        Args.AddStrings(['--dex', '--multi-dex', '--min-sdk-version=' + IntToStr(MinApi), '--output=' +
          ExcludeTrailingPathDelimiter(Work), Classes_]);
        Args.AddStrings(LibJars);
      end
      else
        Args.AddStrings(['--dex', '--min-sdk-version=' + IntToStr(MinApi), '--output=' + Work + 'classes.dex', Classes_]);
      if RunCapture(Dx, Args, Work, Output) <> 0 then
      begin
        if Length(LibJars) > 0 then
          Exit('dx cannot dex these libraries (newer Java): they need d8 (Android''s build tools 28 or newer; ' +
            'pastel setup android --yes): ' +
            Trim(Output));
        Exit('dx: ' + Trim(Output));
      end;
    end;
  finally
    Args.Free;
  end;
  if not FileExists(Work + 'classes.dex') then
    Result := 'the Java was not turned into classes.dex';
end;

{ #RGB, #RRGGBB or #AARRGGBB }
function IsHexColor(const S: string): Boolean;
var
  I: Integer;
begin
  Result := (Length(S) in [4, 7, 9]) and (S[1] = '#');
  if Result then
    for I := 2 to Length(S) do
      if not (S[I] in ['0'..'9', 'a'..'f', 'A'..'F']) then
        Exit(False);
end;

{ The site's part of an app link (https://shop.example.com/app opens the app, not the
  browser): dist/assetlinks.json with the key's fingerprint, for the site's
  /.well-known/assetlinks.json. }
procedure WriteAssetLinks(Project: TPastelProject; const Keytool, Keystore, Alias, Pass, Dist: string);
var
  Args: TStringList;
  Out_, Line, Finger, Json, L, Scheme, Host, Path: string;
  Hosts: TStringArray;
begin
  Finger := '';
  Args := TStringList.Create;
  try
    Args.AddStrings(['-list', '-v', '-keystore', Keystore, '-alias', Alias, '-storepass', Pass]);
    if RunCapture(Keytool, Args, Dist, Out_) = 0 then
      for Line in Out_.Split([#10]) do
        if Pos('SHA256:', Trim(Line)) = 1 then
          Finger := Trim(Copy(Trim(Line), 8, MaxInt));
  finally
    Args.Free;
  end;
  if Finger = '' then
  begin
    Hint('app links: the key''s SHA-256 could not be read (keytool -list -v); assetlinks.json is not written');
    Exit;
  end;
  Json := '[{' + LineEnding +
    '  "relation": ["delegate_permission/common.handle_all_urls"],' + LineEnding +
    '  "target": {' + LineEnding +
    '    "namespace": "android_app",' + LineEnding +
    '    "package_name": "' + AndroidAppId(Project) + '",' + LineEnding +
    '    "sha256_cert_fingerprints": ["' + Finger + '"]' + LineEnding +
    '  }' + LineEnding + '}]' + LineEnding;
  with TStringList.Create do
  try
    Text := Json;
    SaveToFile(Dist + 'assetlinks.json');
  finally
    Free;
  end;
  Hosts := nil;
  for L in Project.Links do
    if SplitLink(L, Scheme, Host, Path) and ((Scheme = 'http') or (Scheme = 'https')) and (IndexStr(Host, Hosts) < 0) then
    begin
      SetLength(Hosts, Length(Hosts) + 1);
      Hosts[High(Hosts)] := Host;
    end;
  Status('Written', 'dist/assetlinks.json (the key''s fingerprint, for app links)');
  for Host in Hosts do
    Hint(Format('put it at https://%s/.well-known/assetlinks.json: then the links open the app, not the browser ' +
      '(Google Play''s key: its fingerprint from Play Console, in the same file)', [Host]));
end;

function PackageAndroid(Project: TPastelProject; const Targets: TTargetArray; Verbose, Debug, Bundle: Boolean): string;
const
  Densities: array[0..4] of record Name: string; Size: Integer; end = (
    (Name: 'mdpi'; Size: 48), (Name: 'hdpi'; Size: 72), (Name: 'xhdpi'; Size: 96),
    (Name: 'xxhdpi'; Size: 144), (Name: 'xxxhdpi'; Size: 192));
var
  Opts: TBuildOptions;
  Target: TTarget;
  Abis, Libs: TStringArray;
  Lib, Perms, Perm: string;
  HasArm32: Boolean;
  SoPath, Work, Res, Aapt, Zipalign, Signer, Keytool, Jar, Keystore, Alias, Pass, Icon, Orientation, Dist, Output,
    Unaligned, Aligned, Err, Manifest, Dex, Aapt2, Bundletool, Java, JarSigner, Kind, Module, F: string;
  Api, I, TargetSdk: Integer;
  Jars: TAndroidJars;
  Splash, Colors, Theme, Back, Bars, AppAttrs, IconBack, Shares, WorkTypes, WorkService, LibraryParts: string;
  LinkScheme, LinkHost, LinkPath, PipAttrs: string;
  WebLinks: Boolean;
  ALibs: TAndroidLibraries;
  ALib: TAndroidLibrary;
  LibRes: Boolean;
  LPerms, LQueries, Packages, Linked, Gs: string;
  MinSdk, LMin, N, NeedApi: Integer;
  NeedBy: string;
  RFiles, LinkArgs, PushJava: TStringArray;
  Unzip: TUnZipper;
  Zip: TZipper;
  Files: TStringArray;
  Args: TStringList;
  L: TStringList;

  function Run(const Tool: string; const A: array of string; const Dir: string): Boolean;
  var
    S: string;
  begin
    Args.Clear;
    for S in A do
      Args.Add(S);
    if Verbose then
      WriteLn('  ', Tool, ' ', StringReplace(Args.Text, LineEnding, ' ', [rfReplaceAll]));
    Result := RunCapture(Tool, Args, Dir, Output) = 0;
    if not Result then
      Fail(Format('%s did not work: %s', [ExtractFileName(Tool), Trim(Output)]));
  end;

  procedure Save(const FileName, Text: string);
  begin
    L.Text := Text;
    ForceDirectories(ExtractFileDir(FileName));
    L.SaveToFile(FileName);
  end;

begin
  Result := '';
  if Bundle then Kind := '.aab' else Kind := '.apk';
  if Length(Targets) = 0 then
  begin
    Fail('no Android target to build the ' + Kind + ' for');
    Exit;
  end;
  for Target in Targets do
    if Target.OS <> 'android' then
    begin
      Fail(Format('an .apk is for Android; "%s" is not an Android target', [Target.Name]));
      Hint('pastel package apk (for every Android CPU set up), or --target android-arm64, android-arm, android-x86_64, android-x86');
      Exit;
    end;
  if Project.Kind <> 'app' then
  begin
    Fail('an ' + Kind + ' is made of an app project');
    Exit;
  end;
  if Bundle then
  begin
    { Google Play's bundle: aapt2, bundletool, Java (and jarsigner), a platform; a release key }
    Aapt2 := AndroidTool('aapt2');
    Bundletool := FindBundletool;
    Java := ExeSearch({$IFDEF WINDOWS}'java.exe'{$ELSE}'java'{$ENDIF}, GetEnvironmentVariable('PATH'));
    JarSigner := ExeSearch({$IFDEF WINDOWS}'jarsigner.exe'{$ELSE}'jarsigner'{$ENDIF}, GetEnvironmentVariable('PATH'));
    Jars := AndroidJars;
    if (Aapt2 = '') or (Bundletool = '') or (Java = '') or (JarSigner = '') or (Length(Jars) = 0) then
    begin
      Fail('making an .aab needs aapt2 (Android''s build tools 28 or newer), bundletool, Java with jarsigner and a platform (android.jar)');
      if Aapt2 = '' then
        {$IFDEF LINUX}
        Hint('aapt2: sudo apt install google-android-build-tools-34.0.0-installer (or Android Studio''s SDK, with ANDROID_HOME)');
        {$ELSE}
        Hint('aapt2: Android Studio''s SDK Manager, "Android SDK Build-Tools"; set ANDROID_HOME');
        {$ENDIF}
      if Bundletool = '' then
        Hint('bundletool: download bundletool-all-<version>.jar from https://github.com/google/bundletool/releases into ' +
          PastelHome + 'android' + PathDelim + ' (or set PASTEL_BUNDLETOOL)');
      if (Java = '') or (JarSigner = '') then
        Hint('Java: sudo apt install default-jdk-headless (or the JDK of Android Studio on the PATH)');
      Exit;
    end;
    if Project.AndroidKeystore = '' then
    begin
      Fail('Google Play needs the app signed with your own key: [package.android] keystore and alias in pastel.toml');
      Hint('make one once: keytool -genkeypair -keystore keys/upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000');
      Exit;
    end;
  end
  else
  begin
    { the tools: Android's build tools and a platform (android.jar) }
    Aapt := AndroidTool('aapt');
    Zipalign := AndroidTool('zipalign');
    Signer := AndroidTool('apksigner');
    Keytool := ExeSearch({$IFDEF WINDOWS}'keytool.exe'{$ELSE}'keytool'{$ENDIF}, GetEnvironmentVariable('PATH'));
    Jars := AndroidJars;
    if (Aapt = '') or (Zipalign = '') or (Signer = '') or (Keytool = '') or (Length(Jars) = 0) then
    begin
      Fail('making an .apk needs Android''s build tools (aapt, zipalign, apksigner), a platform (android.jar) and Java (keytool)');
      {$IFDEF LINUX}
      Hint('on Ubuntu, Mint, Debian: sudo apt install aapt zipalign apksigner android-sdk-platform-23 default-jdk-headless');
      {$ELSE}
      Hint('install Android Studio (or its command-line tools) and set ANDROID_HOME; Java comes with it');
      {$ENDIF}
      Exit;
    end;
  end;
  Work := Project.Root + 'build' + PathDelim + 'android' + PathDelim + Copy(Kind, 2, 3) + PathDelim;
  DeleteTree(ExcludeTrailingPathDelimiter(Work));
  { the platform the resources are made against: the newest the build tools read }
  if Bundle then
    Jar := UsableAndroidJar(Aapt2, Work, True, Jars, Api)
  else
    Jar := UsableAndroidJar(Aapt, Work, False, Jars, Api);
  if Jar = '' then
  begin
    Fail(Format('Android''s build tools (%s) cannot read any of the platforms (android.jar) installed',
      [ExtractFileName(Aapt + Aapt2)]));
    Hint('Android Studio''s SDK Manager: "Android SDK Build-Tools" 36 and "Android 16 (API 36)"; set ANDROID_HOME');
    Exit;
  end;
  if Api < Jars[0].Api then
    Hint(Format('the build tools read Android platforms up to %d, not %d: newer build tools (35 or later) use the newest',
      [Api, Jars[0].Api]));
  { the Android version the app is made for: Google Play asks for a recent one (36
    since August 2026); it needs a platform of Android 13 (33) or newer here }
  TargetSdk := Project.AndroidTargetSdk;
  if TargetSdk <= 0 then
    if Api >= 33 then
      TargetSdk := 36
    else
      TargetSdk := Max(23, Api);
  if Bundle and (Api < 33) then
  begin
    Fail(Format('Google Play needs apps made for Android 16 (API 36); the newest platform here is %d', [Api]));
    Hint('Android Studio''s SDK Manager: "Android 16 (API 36)" (platforms;android-36) and Build-Tools 36; set ANDROID_HOME');
    Exit;
  end;
  { the program, as lib/<abi>/libmain.so for every CPU }
  Abis := nil;
  Libs := nil;
  HasArm32 := False;
  for Target in Targets do
  begin
    Opts := Default(TBuildOptions);
    Opts.Target := Target;
    Opts.Release := not Debug;
    Opts.Verbose := Verbose;
    if not BuildProject(Project, Opts, SoPath) then
      Exit;
    ForceDirectories(Work + 'lib' + PathDelim + AndroidAbi(Target));
    CopyFile(Project.Root + SoPath, Work + 'lib' + PathDelim + AndroidAbi(Target) + PathDelim + 'libmain.so', False);
    Abis := Concat(Abis, [AndroidAbi(Target)]);
    { an app with a database carries SQLite (Android does not let apps load the phone's) }
    if FileExists(Project.Root + ExtractFilePath(SoPath) + 'units' + PathDelim + 'pastel.db.ppu') then
    begin
      Lib := ExpandFileName(IncludeTrailingPathDelimiter(FrameworkDir) + '..' + PathDelim + 'android' + PathDelim + 'lib' +
        PathDelim + AndroidAbi(Target) + PathDelim + 'libsqlite3.so');
      if not FileExists(Lib) then
      begin
        Fail('SQLite for Android is missing: ' + Lib);
        Exit;
      end;
      CopyFile(Lib, Work + 'lib' + PathDelim + AndroidAbi(Target) + PathDelim + 'libsqlite3.so', False);
      Libs := Concat(Libs, ['lib/' + AndroidAbi(Target) + '/libsqlite3.so']);
    end;
    HasArm32 := HasArm32 or (Target.CPU = 'arm');
  end;
  { [package.android] libraries: from Maven or the project's .aar/.jar files }
  Err := ResolveAndroidLibraries(Project, Project.Root + 'build' + PathDelim + 'android' + PathDelim, ALibs);
  if Err <> '' then
  begin
    Fail(Err);
    Exit;
  end;
  LibRes := False;
  Packages := '';
  for ALib in ALibs do
  begin
    if ALib.Res <> '' then
    begin
      LibRes := True;
      if (ALib.PackageName <> AndroidAppId(Project)) and (Pos(':' + ALib.PackageName + ':', ':' + Packages + ':') = 0) then
      begin
        if Packages <> '' then
          Packages := Packages + ':';
        Packages := Packages + ALib.PackageName;
      end;
    end;
    if ALib.Dir = '' then
      Continue;
    { their native libraries, for the CPUs of the app }
    for I := 0 to High(Abis) do
      if DirectoryExists(ALib.Dir + 'jni' + PathDelim + Abis[I]) then
        for F in ListFiles(ALib.Dir + 'jni' + PathDelim + Abis[I], '*.so', False) do
          if not FileExists(Work + 'lib' + PathDelim + Abis[I] + PathDelim + ExtractFileName(F)) then
          begin
            CopyFile(F, Work + 'lib' + PathDelim + Abis[I] + PathDelim + ExtractFileName(F), False);
            Libs := Concat(Libs, ['lib/' + Abis[I] + '/' + ExtractFileName(F)]);
          end;
    { their assets }
    if ALib.Assets <> '' then
      for F in FindAllFilesIn(IncludeTrailingPathDelimiter(ALib.Assets)) do
      begin
        ForceDirectories(ExtractFileDir(Work + 'assets' + PathDelim + F));
        CopyFile(IncludeTrailingPathDelimiter(ALib.Assets) + F, Work + 'assets' + PathDelim + F, False);
      end;
  end;
  if Length(ALibs) > 0 then
  begin
    Files := nil;
    for ALib in ALibs do
      Files := Concat(Files, [ALib.Name]);
    Status('Libraries', Format('%d for Android: %s', [Length(ALibs), string.Join(', ', Files)]));
    if LibRes and (AndroidTool('aapt2') = '') then
    begin
      Fail('the libraries'' resources need aapt2 (Android''s build tools 28 or newer)');
      Hint('Android Studio''s SDK Manager: "Android SDK Build-Tools"; set ANDROID_HOME (or: pastel setup android)');
      Exit;
    end;
    if LibRes then
      Aapt2 := AndroidTool('aapt2');
    { a library made against a newer Android than the platform here: its resources do not link }
    NeedApi := 0;
    NeedBy := '';
    for ALib in ALibs do
      if ALib.CompileSdk > NeedApi then
      begin
        NeedApi := ALib.CompileSdk;
        NeedBy := ALib.Name;
      end;
    if NeedApi > Api then
    begin
      Fail(Format('%s is made against Android %d (API %d) or newer; the newest Android platform here is API %d',
        [NeedBy, NeedApi, NeedApi, Api]));
      Hint('pastel setup android --yes installs Android 16 (API 36) and its build tools (Android''s licenses accepted)');
      Exit;
    end;
    if AndroidTool('d8') = '' then
      Hint('the libraries are dexed with dx: newer ones (Java 8 code) need d8 - Android''s build tools 28 or ' +
        'newer (pastel setup android --yes)');
  end;
  Res := Work + 'res' + PathDelim;
  L := TStringList.Create;
  Args := TStringList.Create;
  try
    { the name and the icon, as Android resources }
    Save(Res + 'values' + PathDelim + 'strings.xml',
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<resources><string name="app_name">' + XmlText(Project.Title) + '</string></resources>');
    Icon := Project.Root + 'assets' + PathDelim + 'icon.png';
    if not FileExists(Icon) then
    begin
      WriteDefaultIcon(Work + 'icon.png');
      Icon := Work + 'icon.png';
    end;
    Splash := Project.AndroidSplash;
    if (Splash <> '') and not IsHexColor(Splash) then
    begin
      Fail(Format('[package.android] splash: "%s" is not a color like "#1E1B2E"', [Splash]));
      Exit;
    end;
    IconBack := IconBackColor(Icon);
    for I := Low(Densities) to High(Densities) do
    begin
      ForceDirectories(Res + 'mipmap-' + Densities[I].Name);
      Err := WriteSizedPng(Icon, Res + 'mipmap-' + Densities[I].Name + PathDelim + 'ic_launcher.png', Densities[I].Size);
      { Android 8 and newer: the icon in layers, in the shape the phone uses (circle, squircle...) }
      if (Err = '') and (Api >= 26) then
        Err := WriteAdaptiveForeground(Icon, Res + 'mipmap-' + Densities[I].Name + PathDelim + 'ic_launcher_foreground.png',
          Densities[I].Size * 108 div 48, IconBack <> '');
      { the small icon of notifications: white, the shape of the picture (or assets/notification.png) }
      if Err = '' then
        if FileExists(Project.Root + 'assets' + PathDelim + 'notification.png') then
          Err := WriteSizedPng(Project.Root + 'assets' + PathDelim + 'notification.png',
            Res + 'drawable-' + Densities[I].Name + PathDelim + 'ic_stat_pastel.png', Densities[I].Size div 2)
        else
          Err := WriteStatusIcon(Icon, Res + 'drawable-' + Densities[I].Name + PathDelim + 'ic_stat_pastel.png',
            Densities[I].Size div 2, IconBack);
      if Err <> '' then
      begin
        Fail('assets/icon.png: ' + Err);
        Exit;
      end;
    end;
    { Android TV's home screen shows a banner: the icon on a dark band }
    Err := WriteTvBanner(Icon, Res + 'drawable-xhdpi' + PathDelim + 'banner.png');
    if Err <> '' then
    begin
      Fail('assets/icon.png: ' + Err);
      Exit;
    end;
    if IconBack = '' then
      IconBack := '#FFFFFF';
    Colors := '<color name="pastel_icon_back">' + IconBack + '</color>';
    if Splash <> '' then
      Colors := Colors + '<color name="pastel_splash">' + Splash + '</color>';
    Save(Res + 'values' + PathDelim + 'colors.xml',
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding + '<resources>' + Colors + '</resources>');
    { Firebase's google-services.json, as the values its libraries read }
    Gs := GoogleServicesXml(Project.Root, AndroidAppId(Project), Err);
    if Err <> '' then
    begin
      Fail(Err);
      Exit;
    end;
    if Gs <> '' then
      Save(Res + 'values' + PathDelim + 'google-services.xml', Gs);
    if Api >= 26 then
      Save(Res + 'mipmap-anydpi-v26' + PathDelim + 'ic_launcher.xml',
        '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">' +
        '<background android:drawable="@color/pastel_icon_back"/>' +
        '<foreground android:drawable="@mipmap/ic_launcher_foreground"/></adaptive-icon>');
    { the window's theme: the phone's own look, light or dark as the phone is set
      (Android 10 and newer), with the status bar's icons to match }
    Theme := '@android:style/Theme.NoTitleBar';
    if Api >= 29 then
    begin
      Theme := '@style/PastelTheme';
      Back := '';
      if Splash <> '' then
        Back := '<item name="android:windowBackground">@color/pastel_splash</item>';
      Save(Res + 'values' + PathDelim + 'styles.xml', '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
        '<resources><style name="PastelTheme" parent="@android:style/Theme.Holo.Light.NoActionBar">' + Back +
        '</style></resources>');
      Save(Res + 'values-v21' + PathDelim + 'styles.xml', '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
        '<resources><style name="PastelTheme" parent="@android:style/Theme.Material.Light.NoActionBar">' + Back +
        '</style></resources>');
      Bars := '<item name="android:windowLightStatusBar">@bool/pastel_light_bars</item>' +
        '<item name="android:windowLightNavigationBar">@bool/pastel_light_bars</item>' + Back;
      Save(Res + 'values' + PathDelim + 'bools.xml', '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
        '<resources><bool name="pastel_light_bars">true</bool></resources>');
      Save(Res + 'values-night' + PathDelim + 'bools.xml', '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
        '<resources><bool name="pastel_light_bars">false</bool></resources>');
      Save(Res + 'values-v29' + PathDelim + 'styles.xml', '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
        '<resources><style name="PastelTheme" parent="@android:style/Theme.DeviceDefault.DayNight">' +
        '<item name="android:windowActionBar">false</item><item name="android:windowNoTitle">true</item>' + Bars +
        '</style></resources>');
      { Android 12 and newer show the icon while the app starts: on the splash color }
      if (Api >= 31) and (Splash <> '') then
        Save(Res + 'values-v31' + PathDelim + 'styles.xml', '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
          '<resources><style name="PastelTheme" parent="@android:style/Theme.DeviceDefault.DayNight">' +
          '<item name="android:windowActionBar">false</item><item name="android:windowNoTitle">true</item>' + Bars +
          '<item name="android:windowSplashScreenBackground">@color/pastel_splash</item></style></resources>');
    end;
    { plain http:// only in a debug build (hot reload) or when the project asks for it }
    if Debug or Project.AndroidCleartext then
      AppAttrs := ' android:usesCleartextTraffic="true"'
    else
      AppAttrs := ' android:usesCleartextTraffic="false"';
    if Project.AndroidBackup then
      AppAttrs := AppAttrs + ' android:allowBackup="true"'
    else
      AppAttrs := AppAttrs + ' android:allowBackup="false"';
    AppAttrs := AppAttrs + ' android:supportsRtl="true"';
    { Back on Android 13 and newer: the system's back callback (PastelActivity
      gives it to Pascal), as Android 16 wants - not the Back key, which it no
      longer sends to apps made for it }
    if Api >= 33 then
      AppAttrs := AppAttrs + LineEnding + '      android:enableOnBackInvokedCallback="true"';
    Orientation := Project.AndroidOrientation;
    if Orientation = '' then
      Orientation := 'unspecified';
    { what the app may use beyond the network and vibration ([package.android] permissions) }
    Perms := '';
    for Perm in Project.AndroidPermissions do
      case LowerCase(Perm) of
        'location':
          Perms := Perms + '  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>' + LineEnding;
        'notifications':
          { scheduled notifications are given again after the phone restarted }
          Perms := Perms + '  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>' + LineEnding;
        'camera':
          Perms := Perms + '  <uses-permission android:name="android.permission.CAMERA"/>' + LineEnding;
        'microphone':
          Perms := Perms + '  <uses-permission android:name="android.permission.RECORD_AUDIO"/>' + LineEnding;
        'contacts':
          Perms := Perms + '  <uses-permission android:name="android.permission.READ_CONTACTS"/>' + LineEnding;
        'calendar':
          Perms := Perms + '  <uses-permission android:name="android.permission.READ_CALENDAR"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.WRITE_CALENDAR"/>' + LineEnding;
        'phone':
          Perms := Perms + '  <uses-permission android:name="android.permission.CALL_PHONE"/>' + LineEnding;
        'storage':
          { the gallery on Android 9 and older (newer ones need nothing) }
          Perms := Perms + '  <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>' + LineEnding;
        'nfc':
          { Pastel.Sensors' TNfcReader; phones without NFC can still install the app }
          Perms := Perms + '  <uses-permission android:name="android.permission.NFC"/>' + LineEnding +
            '  <uses-feature android:name="android.hardware.nfc" android:required="false"/>' + LineEnding;
        'install_updates':
          { Pastel.Updater: the app installs a newer .apk of its own (not for apps of Google Play) }
          Perms := Perms + '  <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>' + LineEnding;
        'biometric':
          { Authenticate: the fingerprint, the face (no question to the user) }
          Perms := Perms + '  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.USE_FINGERPRINT"/>' + LineEnding;
        'bluetooth':
          { Android 12 and newer ask; older ones give it with the app (and need the place for a scan) }
          Perms := Perms +
            '  <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>' + LineEnding +
            '  <uses-permission android:name="android.permission.BLUETOOTH_SCAN"' +
            StrUtils.IfThen(Api >= 31, ' android:usesPermissionFlags="neverForLocation"', '') + '/>' + LineEnding;
      else
        begin
          Fail(Format('[package.android] permissions: "%s" is not one Pastel knows (location, notifications, camera, ' +
            'microphone, contacts, calendar, phone, storage, bluetooth, biometric, install_updates, nfc)', [Perm]));
          Exit;
        end;
      end;
    LibraryParts := '';
    { work when the app is not on the screen ([package.android] background) }
    WorkTypes := '';
    for Perm in Project.AndroidBackground do
      case LowerCase(Perm) of
        'jobs':
          { jobs that come back after the phone restarted }
          if Pos('RECEIVE_BOOT_COMPLETED', Perms) = 0 then
            Perms := Perms + '  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>' + LineEnding;
        'data_sync', 'media_playback', 'location', 'connected_device':
          begin
            case LowerCase(Perm) of
              'data_sync': F := 'dataSync';
              'media_playback': F := 'mediaPlayback';
              'location': F := 'location';
            else
              F := 'connectedDevice';
            end;
            if WorkTypes <> '' then
              WorkTypes := WorkTypes + '|';
            WorkTypes := WorkTypes + F;
            Perms := Perms + '  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_' + UpperCase(Perm) + '"/>' + LineEnding;
          end;
      else
        begin
          Fail(Format('[package.android] background: "%s" is not one Pastel knows (jobs, data_sync, media_playback, ' +
            'location, connected_device)', [Perm]));
          Exit;
        end;
      end;
    WorkService := '';
    if WorkTypes <> '' then
    begin
      Perms := Perms + '  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>' + LineEnding;
      WorkService := '    <service android:name="dev.pastel.PastelWork" android:exported="false"' +
        StrUtils.IfThen(Api >= 29, ' android:foregroundServiceType="' + WorkTypes + '"', '') + '/>' + LineEnding;
    end;
    { what the libraries' manifests add }
    LibraryManifests(ALibs, AndroidAppId(Project), Perms + '"android.permission.INTERNET" "android.permission.VIBRATE"',
      LPerms, LibraryParts, LQueries, LMin);
    { Firebase's messaging among them: Pastel's push service (Pastel.Push) }
    PushJava := nil;
    if JarsHaveClass(LibraryJars(ALibs), 'com/google/firebase/messaging/FirebaseMessagingService.class') then
    begin
      PushJava := ListFiles(ExpandFileName(IncludeTrailingPathDelimiter(FrameworkDir) + '..' + PathDelim + 'android' +
        PathDelim + 'push'), '*.java', True);
      LibraryParts := LibraryParts +
        '    <service android:name="dev.pastel.PastelPushService" android:exported="false">' + LineEnding +
        '      <intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT"/></intent-filter>' + LineEnding +
        '    </service>' + LineEnding;
    end;
    { Google's code scanner among them: Pastel's scanner (Pastel.Device's ScanBarcode) }
    if JarsHaveClass(LibraryJars(ALibs), 'com/google/mlkit/vision/codescanner/GmsBarcodeScanning.class') then
      PushJava := Concat(PushJava, ListFiles(ExpandFileName(IncludeTrailingPathDelimiter(FrameworkDir) + '..' +
        PathDelim + 'android' + PathDelim + 'scanner'), '*.java', True));
    Perms := Perms + LPerms;
    MinSdk := Max(19, LMin);
    if Api < 30 then
      LQueries := '';
    { in other apps' share menu: one or many of these kinds }
    Shares := '';
    WebLinks := False;
    for Perm in Project.AndroidReceiveShares do
    begin
      if Pos('/', Perm) = 0 then
      begin
        Fail(Format('[package.android] receive_shares: "%s" is not a kind like "text/plain" or "image/*"', [Perm]));
        Exit;
      end;
      Shares := Shares +
        '      <intent-filter>' + LineEnding +
        '        <action android:name="android.intent.action.SEND"/>' + LineEnding +
        '        <action android:name="android.intent.action.SEND_MULTIPLE"/>' + LineEnding +
        '        <category android:name="android.intent.category.DEFAULT"/>' + LineEnding +
        '        <data android:mimeType="' + XmlText(Perm) + '"/>' + LineEnding +
        '      </intent-filter>' + LineEnding;
    end;
    { links that open the app: its own scheme (shop://), or its site's addresses (verified with assetlinks.json) }
    for Perm in Project.Links do
    begin
      if not SplitLink(Perm, LinkScheme, LinkHost, LinkPath) then
      begin
        Fail(Format('[package] links: "%s" is not a link like "shop://" or "https://shop.example.com/app"', [Perm]));
        Exit;
      end;
      if (LinkScheme = 'http') or (LinkScheme = 'https') then
      begin
        Shares := Shares + '      <intent-filter android:autoVerify="true">' + LineEnding;
        WebLinks := True;
      end
      else
        Shares := Shares + '      <intent-filter>' + LineEnding;
      Shares := Shares +
        '        <action android:name="android.intent.action.VIEW"/>' + LineEnding +
        '        <category android:name="android.intent.category.DEFAULT"/>' + LineEnding +
        '        <category android:name="android.intent.category.BROWSABLE"/>' + LineEnding +
        '        <data android:scheme="' + XmlText(LinkScheme) + '"';
      if LinkHost <> '' then
        Shares := Shares + ' android:host="' + XmlText(LinkHost) + '"';
      if LinkPath <> '' then
        Shares := Shares + ' android:pathPrefix="' + XmlText(LinkPath) + '"';
      Shares := Shares + '/>' + LineEnding + '      </intent-filter>' + LineEnding;
    end;
    { video in a small window over other apps }
    if Project.AndroidPip then
      PipAttrs := LineEnding + '        android:supportsPictureInPicture="true" android:resizeableActivity="true"'
    else
      PipAttrs := '';
    { a NativeActivity: no Java code, Android loads libmain.so }
    Manifest :=
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android"' + LineEnding +
      '    package="' + AndroidAppId(Project) + '"' + LineEnding +
      '    android:versionCode="' + IntToStr(VersionCode(Project.Version)) + '"' + LineEnding +
      '    android:versionName="' + XmlText(Project.Version) + '">' + LineEnding +
      '  <uses-sdk android:minSdkVersion="' + IntToStr(MinSdk) + '" android:targetSdkVersion="' + IntToStr(TargetSdk) + '"/>' + LineEnding +
      '  <uses-permission android:name="android.permission.INTERNET"/>' + LineEnding +
      '  <uses-permission android:name="android.permission.VIBRATE"/>' + LineEnding + Perms +
      { TVs and TV boxes: no touch screen needed, a place on Android TV's home screen }
      '  <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>' + LineEnding +
      '  <uses-feature android:name="android.software.leanback" android:required="false"/>' + LineEnding + LQueries +
      '  <application android:label="@string/app_name" android:icon="@mipmap/ic_launcher"' + LineEnding +
      '      android:banner="@drawable/banner"' + LineEnding +
      '      android:hasCode="true" android:extractNativeLibs="true"' + AppAttrs + LineEnding +
      '      android:theme="' + Theme + '">' + LineEnding +
      '    <activity android:name="dev.pastel.PastelActivity" android:label="@string/app_name"' + LineEnding +
      '        android:exported="true" android:launchMode="singleTask"' + LineEnding +
      '        android:screenOrientation="' + XmlText(Orientation) + '"' + LineEnding +
      '        android:windowSoftInputMode="adjustResize"' + PipAttrs + LineEnding +
      '        android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboard|keyboardHidden|uiMode|locale">' + LineEnding +
      '      <meta-data android:name="android.app.lib_name" android:value="main"/>' + LineEnding +
      '      <intent-filter>' + LineEnding +
      '        <action android:name="android.intent.action.MAIN"/>' + LineEnding +
      '        <category android:name="android.intent.category.LAUNCHER"/>' + LineEnding +
      '        <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>' + LineEnding +
      '      </intent-filter>' + LineEnding + Shares +
      '    </activity>' + LineEnding +
      { the app's files for the camera app and for sharing (Pastel.Device) }
      { notifications at a time (Pastel.Notifications): the alarm, and the phone's restart }
      '    <receiver android:name="dev.pastel.PastelNotifications" android:exported="false">' + LineEnding +
      '      <intent-filter>' + LineEnding +
      '        <action android:name="android.intent.action.BOOT_COMPLETED"/>' + LineEnding +
      '        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>' + LineEnding +
      '      </intent-filter>' + LineEnding +
      '    </receiver>' + LineEnding +
      '    <provider android:name="dev.pastel.PastelFiles" android:authorities="' + AndroidAppId(Project) + '.files"' + LineEnding +
      '        android:exported="false" android:grantUriPermissions="true"/>' + LineEnding +
      '    <service android:name="dev.pastel.PastelJob" android:permission="android.permission.BIND_JOB_SERVICE"' + LineEnding +
      '        android:exported="false"/>' + LineEnding +
      WorkService +
      LibraryParts +
      '  </application>' + LineEnding +
      '</manifest>';
    Save(Work + 'AndroidManifest.xml', Manifest);
    { Pastel's activity: a NativeActivity that also passes on the letters the on-screen keyboard types }
    Dex := ExpandFileName(IncludeTrailingPathDelimiter(FrameworkDir) + '..' + PathDelim + 'android' + PathDelim + 'classes.dex');
    if not FileExists(Dex) then
    begin
      Fail('Pastel''s Android activity is missing: ' + Dex);
      Exit;
    end;
    CopyFile(Dex, Work + 'classes.dex', False);
    { the libraries' resources with the app's (aapt2), and R classes for their code }
    RFiles := nil;
    if LibRes then
    begin
      if Bundle then
        Linked := 'linked.apk'
      else
        Linked := 'unaligned.apk';
      if not Run(Aapt2, ['compile', '--dir', 'res', '-o', 'res.zip'], Work) then
        Exit;
      LinkArgs := ['link', '-o', Linked, '-I', Jar, '--manifest', 'AndroidManifest.xml', '--auto-add-overlay',
        '--java', 'gen', '--extra-packages', Packages];
      if Bundle then
        LinkArgs := Concat(LinkArgs, ['--proto-format']);
      if DirectoryExists(Work + 'assets') then
        LinkArgs := Concat(LinkArgs, ['-A', 'assets']);
      N := 0;
      for ALib in ALibs do
        if ALib.Res <> '' then
        begin
          if not Run(Aapt2, ['compile', '--dir', ALib.Res, '-o', 'lib' + IntToStr(N) + '.zip'], Work) then
            Exit;
          { the first as the base, the others over it, the app's over all }
          if N > 0 then
            LinkArgs := Concat(LinkArgs, ['-R']);
          LinkArgs := Concat(LinkArgs, ['lib' + IntToStr(N) + '.zip']);
          Inc(N);
        end;
      LinkArgs := Concat(LinkArgs, ['-R', 'res.zip']);
      if not Run(Aapt2, LinkArgs, Work) then
        Exit;
      RFiles := ListFiles(Work + 'gen', '*.java', True);
    end;
    { the project's own Java (src/java) and the libraries: compiled with Pastel's activity into the app's classes.dex }
    if (Length(ProjectJavaFiles(Project.Root)) > 0) or (Length(ALibs) > 0) then
    begin
      Err := DexProjectJava(Project, Jar, Work, LibraryJars(ALibs), Concat(RFiles, PushJava), MinSdk);
      if Err <> '' then
      begin
        Fail(Err);
        Exit;
      end;
    end;
    if Bundle then
    begin
      Status('Packing', Format('the .aab for Google Play (%s, Android %d; %s)', [AndroidAppId(Project), TargetSdk,
        string.Join(', ', Abis)]));
      { the resources in the bundle's (protocol buffer) form }
      if not LibRes then
      begin
        if not Run(Aapt2, ['compile', '--dir', 'res', '-o', 'res.zip'], Work) then
          Exit;
        LinkArgs := ['link', '--proto-format', '-o', 'linked.apk', '-I', Jar, '--manifest', 'AndroidManifest.xml',
          '--auto-add-overlay'];
        if DirectoryExists(Work + 'assets') then
          LinkArgs := Concat(LinkArgs, ['-A', 'assets']);
        if not Run(Aapt2, Concat(LinkArgs, ['res.zip']), Work) then
          Exit;
      end;
      { the base module: manifest/, res/, resources.pb, dex/, lib/ }
      Module := Work + 'base' + PathDelim;
      Unzip := TUnZipper.Create;
      try
        Unzip.FileName := Work + 'linked.apk';
        Unzip.OutputPath := Module;
        Unzip.UnZipAllFiles;
      finally
        Unzip.Free;
      end;
      ForceDirectories(Module + 'manifest');
      RenameFile(Module + 'AndroidManifest.xml', Module + 'manifest' + PathDelim + 'AndroidManifest.xml');
      ForceDirectories(Module + 'dex');
      for F in ListFiles(Work, 'classes*.dex', False) do
        CopyFile(F, Module + 'dex' + PathDelim + ExtractFileName(F), False);
      for I := 0 to High(Abis) do
      begin
        ForceDirectories(Module + 'lib' + PathDelim + Abis[I]);
        CopyFile(Work + 'lib' + PathDelim + Abis[I] + PathDelim + 'libmain.so',
          Module + 'lib' + PathDelim + Abis[I] + PathDelim + 'libmain.so', False);
      end;
      for I := 0 to High(Libs) do
        CopyFile(Work + StringReplace(Libs[I], '/', PathDelim, [rfReplaceAll]),
          Module + StringReplace(Libs[I], '/', PathDelim, [rfReplaceAll]), False);
      Zip := TZipper.Create;
      try
        Zip.FileName := Work + 'base.zip';
        Files := FindAllFilesIn(Module);
        for F in Files do
          Zip.Entries.AddFileEntry(Module + F, StringReplace(F, PathDelim, '/', [rfReplaceAll]));
        Zip.ZipAllFiles;
      finally
        Zip.Free;
      end;
      Dist := Project.Root + 'dist' + PathDelim;
      ForceDirectories(Dist);
      Result := Dist + Project.Name + '-' + Project.Version + '.aab';
      DeleteFile(Result);
      if not Run(Java, ['-jar', Bundletool, 'build-bundle', '--modules=' + Work + 'base.zip', '--output=' + Result], Work) then
      begin
        Result := '';
        Exit;
      end;
      Keystore := ExpandFileName(Project.Root + Project.AndroidKeystore);
      Alias := Project.AndroidAlias;
      Pass := GetEnvironmentVariable('PASTEL_KEYSTORE_PASSWORD');
      if not FileExists(Keystore) or (Alias = '') or (Pass = '') then
      begin
        Fail('signing with ' + Project.AndroidKeystore + ' needs the file, [package.android] alias and the password in PASTEL_KEYSTORE_PASSWORD');
        Result := '';
        Exit;
      end;
      if not Run(JarSigner, ['-keystore', Keystore, '-storepass', Pass, '-keypass', Pass, '-sigalg', 'SHA256withRSA',
        '-digestalg', 'SHA-256', Result, Alias], Work) then
      begin
        Result := '';
        Exit;
      end;
      Status('Packed', Format('%s (%s)', [ExtractRelativePath(Project.Root, Result), SizeText(Result)]));
      Hint('upload it in the Google Play Console (Release > Production > Create new release); Play makes the .apk for each phone');
      Exit;
    end;
    Unaligned := Work + 'unaligned.apk';
    Aligned := Work + 'aligned.apk';
    if MinSdk = 19 then
      F := 'Android 4.4'
    else
      F := 'API ' + IntToStr(MinSdk);
    Status('Packing', Format('the .apk (%s, %s and newer, made for %d; %s)', [AndroidAppId(Project), F, TargetSdk,
      string.Join(', ', Abis)]));
    if not LibRes then
    begin
      LinkArgs := ['package', '-f', '-M', 'AndroidManifest.xml', '-S', 'res', '-I', Jar, '-F', 'unaligned.apk'];
      if DirectoryExists(Work + 'assets') then
        LinkArgs := Concat(LinkArgs, ['-A', 'assets']);
      if not Run(Aapt, LinkArgs, Work) then
        Exit;
    end;
    for F in ListFiles(Work, 'classes*.dex', False) do
      if not Run(Aapt, ['add', 'unaligned.apk', ExtractFileName(F)], Work) then
        Exit;
    for I := 0 to High(Abis) do
      if not Run(Aapt, ['add', 'unaligned.apk', 'lib/' + Abis[I] + '/libmain.so'], Work) then
        Exit;
    for I := 0 to High(Libs) do
      if not Run(Aapt, ['add', 'unaligned.apk', Libs[I]], Work) then
        Exit;
    if not Run(Zipalign, ['-p', '-f', '4', Unaligned, Aligned], Work) then
      Exit;
    { the key: the project's release key, or a debug key made once }
    if Project.AndroidKeystore <> '' then
    begin
      Keystore := ExpandFileName(Project.Root + Project.AndroidKeystore);
      Alias := Project.AndroidAlias;
      Pass := GetEnvironmentVariable('PASTEL_KEYSTORE_PASSWORD');
      if not FileExists(Keystore) or (Alias = '') or (Pass = '') then
      begin
        Fail('signing with ' + Project.AndroidKeystore + ' needs the file, [package.android] alias and the password in PASTEL_KEYSTORE_PASSWORD');
        Exit;
      end;
    end
    else
    begin
      Keystore := PastelHome + 'android' + PathDelim + 'debug.keystore';
      Alias := 'androiddebugkey';
      Pass := 'android';
      if not FileExists(Keystore) then
      begin
        ForceDirectories(ExtractFileDir(Keystore));
        if not Run(Keytool, ['-genkeypair', '-keystore', Keystore, '-storepass', Pass, '-keypass', Pass, '-alias', Alias,
          '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000', '-dname', 'CN=Pastel Debug,O=Pastel,C=US'], Work) then
          Exit;
      end;
    end;
    Dist := Project.Root + 'dist' + PathDelim;
    ForceDirectories(Dist);
    Result := Dist + Project.Name + '-' + Project.Version;
    if Debug then
      Result := Result + '-debug';
    Result := Result + '.apk';
    if not Run(Signer, ['sign', '--ks', Keystore, '--ks-pass', 'pass:' + Pass, '--key-pass', 'pass:' + Pass,
      '--ks-key-alias', Alias, '--out', Result, Aligned], Work) then
    begin
      Result := '';
      Exit;
    end;
    DeleteFile(Result + '.idsig');
    Status('Packed', Format('%s (%s)', [ExtractRelativePath(Project.Root, Result), SizeText(Result)]));
    if WebLinks then
      WriteAssetLinks(Project, Keytool, Keystore, Alias, Pass, Dist);
    if Project.AndroidKeystore = '' then
      Hint('signed with a debug key: fine for phones you install it on; Google Play needs [package.android] keystore');
    if Api < 33 then
      Hint(Format('made for Android %d (the newest platform here): new phones run it in an older mode; ' +
        'Android 16''s platform (API 36) and Build-Tools 36 from Android Studio''s SDK Manager make it current', [TargetSdk]));
    if not HasArm32 then
      Hint('older phones and TV boxes (ARM 32-bit) cannot run it: "pastel doctor --install android" sets up android-arm too');
    Hint('install it: adb install -r ' + ExtractRelativePath(Project.Root, Result) + '  (or copy it to the phone and open it)');
  finally
    Args.Free;
    L.Free;
  end;
end;

function PackageApk(Project: TPastelProject; const Targets: TTargetArray; Verbose: Boolean; Debug: Boolean): string;
begin
  Result := PackageAndroid(Project, Targets, Verbose, Debug, False);
end;

function PackageAab(Project: TPastelProject; const Targets: TTargetArray; Verbose: Boolean): string;
begin
  Result := PackageAndroid(Project, Targets, Verbose, False, True);
end;

end.
