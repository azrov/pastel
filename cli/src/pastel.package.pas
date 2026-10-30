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

{ Lower-case hex SHA-256 of a file. }
function FileSha256(const FileName: string): string;

implementation

uses
  Classes, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  libtar, zstream, zipper,
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

function PackageProject(Project: TPastelProject; const Target: TTarget; Verbose: Boolean): string;
var
  Opts: TBuildOptions;
  ExePath, Folder, Dist, Archive, F, Hash: string;
  Entries: TEntries;
  IsZip: Boolean;
  L: TStringList;
  E: TEntry;
begin
  Result := '';
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

  Folder := Format('%s-%s-%s', [Project.Name, Project.Version, Target.Name]);
  IsZip := (Target.OS = 'win64') or (Target.OS = 'win32');
  Entries := nil;
  try
    AddEntry(Entries, Project.Root + ExePath, ExtractFileName(ExePath), True);
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

  Hash := FileSha256(Archive);
  L := TStringList.Create;
  try
    L.Add(Hash + '  ' + ExtractFileName(Archive));
    L.SaveToFile(Archive + '.sha256');
  finally
    L.Free;
  end;
  if Verbose then
    for E in Entries do
      WriteLn(Dim('             ' + Folder + '/' + E.Name));
  Status('Packaged', Format('dist%s%s (%d file(s), %s)', [PathDelim, ExtractFileName(Archive),
    Length(Entries), SizeText(Archive)]));
  Result := Archive;
end;

end.
