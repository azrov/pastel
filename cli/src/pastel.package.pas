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
  Pastel.Console, Pastel.Builder;

{ ---------------- SHA-256 ---------------- }

const
  K256: array[0..63] of Cardinal = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);

type
  TSha256 = record
    H: array[0..7] of Cardinal;
    Block: array[0..63] of Byte;
    Used: Integer;
    Total: QWord;
  end;

{$push}{$R-}{$Q-}
function Ror(X: Cardinal; N: Integer): Cardinal; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

procedure Compress(var C: TSha256);
var
  W: array[0..63] of Cardinal;
  A, B, CC, D, E, F, G, H, T1, T2: Cardinal;
  I: Integer;
begin
  for I := 0 to 15 do
    W[I] := (Cardinal(C.Block[I * 4]) shl 24) or (Cardinal(C.Block[I * 4 + 1]) shl 16) or
      (Cardinal(C.Block[I * 4 + 2]) shl 8) or Cardinal(C.Block[I * 4 + 3]);
  for I := 16 to 63 do
    W[I] := (Ror(W[I - 2], 17) xor Ror(W[I - 2], 19) xor (W[I - 2] shr 10)) + W[I - 7] +
      (Ror(W[I - 15], 7) xor Ror(W[I - 15], 18) xor (W[I - 15] shr 3)) + W[I - 16];
  A := C.H[0]; B := C.H[1]; CC := C.H[2]; D := C.H[3];
  E := C.H[4]; F := C.H[5]; G := C.H[6]; H := C.H[7];
  for I := 0 to 63 do
  begin
    T1 := H + (Ror(E, 6) xor Ror(E, 11) xor Ror(E, 25)) + ((E and F) xor ((not E) and G)) + K256[I] + W[I];
    T2 := (Ror(A, 2) xor Ror(A, 13) xor Ror(A, 22)) + ((A and B) xor (A and CC) xor (B and CC));
    H := G; G := F; F := E; E := D + T1;
    D := CC; CC := B; B := A; A := T1 + T2;
  end;
  Inc(C.H[0], A); Inc(C.H[1], B); Inc(C.H[2], CC); Inc(C.H[3], D);
  Inc(C.H[4], E); Inc(C.H[5], F); Inc(C.H[6], G); Inc(C.H[7], H);
end;
{$pop}

procedure ShaInit(out C: TSha256);
begin
  C := Default(TSha256);
  C.H[0] := $6a09e667; C.H[1] := $bb67ae85; C.H[2] := $3c6ef372; C.H[3] := $a54ff53a;
  C.H[4] := $510e527f; C.H[5] := $9b05688c; C.H[6] := $1f83d9ab; C.H[7] := $5be0cd19;
end;

procedure ShaUpdate(var C: TSha256; P: PByte; N: Integer);
begin
  Inc(C.Total, N);
  while N > 0 do
  begin
    C.Block[C.Used] := P^;
    Inc(C.Used);
    Inc(P);
    Dec(N);
    if C.Used = 64 then
    begin
      Compress(C);
      C.Used := 0;
    end;
  end;
end;

function ShaFinal(var C: TSha256): string;
var
  Bits: QWord;
  Pad: Byte;
  I: Integer;
begin
  Bits := C.Total * 8;
  Pad := $80;
  ShaUpdate(C, @Pad, 1);
  Pad := 0;
  while C.Used <> 56 do
    ShaUpdate(C, @Pad, 1);
  for I := 7 downto 0 do
  begin
    Pad := Byte(Bits shr (I * 8));
    ShaUpdate(C, @Pad, 1);
  end;
  Result := '';
  for I := 0 to 7 do
    Result := Result + LowerCase(IntToHex(C.H[I], 8));
end;

function FileSha256(const FileName: string): string;
var
  F: TFileStream;
  C: TSha256;
  Buf: array[0..65535] of Byte;
  N: Integer;
begin
  ShaInit(C);
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Buf[0] := 0;
    repeat
      N := F.Read(Buf, SizeOf(Buf));
      if N > 0 then
        ShaUpdate(C, @Buf[0], N);
    until N <= 0;
  finally
    F.Free;
  end;
  Result := ShaFinal(C);
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
