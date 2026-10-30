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

{ Lower-case hex SHA-256 of a file. }
function FileSha256(const FileName: string): string;

implementation

uses
  Classes, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  DateUtils, libtar, zstream, zipper,
  Pastel.Console, Pastel.Builder, Pastel.Crypto;

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

function PackageDeb(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
const
  Normal: TTarPermissions = [tpReadByOwner, tpWriteByOwner, tpReadByGroup, tpReadByOther];
  Exec: TTarPermissions = [tpReadByOwner, tpWriteByOwner, tpExecuteByOwner, tpReadByGroup,
    tpExecuteByGroup, tpReadByOther, tpExecuteByOther];
var
  ExeName, Pkg, Arch, Dir, Dist, Archive, UnitFile, ConfigFile, Depends, Desc, Line: string;
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
      W.Finalize;
    finally
      W.Free;
    end;

    { what dpkg needs to know }
    Depends := 'libc6';
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

end.
