{ Pastel - compiling and running projects with the Free Pascal compiler.
  Part of the Pastel project, MIT License. }
unit Pastel.Builder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Project, Pastel.Targets;

type
  TBuildOptions = record
    Target: TTarget;
    Release: Boolean;
    Verbose: Boolean;
    Quiet: Boolean;             { no "Compiling"/"Finished"/"Output" lines }
    { optional overrides, used by "pastel test" }
    Profile: string;            { output folder name, default debug/release }
    MainFile: string;           { program to compile instead of the project's main }
    OutName: string;            { executable name instead of the project name }
    ExtraDirs: TStringArray;    { more unit folders }
    Defines: TStringArray;      { more -d defines }
    { "pastel check file.pas": compile without linking, with OverlayText in
      place of OverlayFile (unsaved editor text); compiler messages go to
      Messages instead of the console }
    CheckOnly: Boolean;
    OverlayFile: string;        { absolute }
    OverlayText: string;
    Messages: TStringList;
  end;

function FindFpc: string;
function FpcVersion(const Fpc: string): string;
{ The Free Pascal sources (rtl/, packages/), for code intelligence; '' if not installed. }
function FpcSourceDir: string;
function RunCapture(const Exe: string; Args: TStrings; const Dir: string;
  out Output: string): Integer;

function BuildProject(Project: TPastelProject; const Opts: TBuildOptions;
  out ExePath: string): Boolean;
function RunProject(Project: TPastelProject; Release, Verbose: Boolean;
  const ProgramArgs: TStringArray): Integer;
procedure CleanProject(Project: TPastelProject);

function DeleteTree(const Dir: string): Boolean;
{ Every folder with units of the project and of its dependencies (absolute
  paths); src/ and its sub-folders, [build] unit_paths, dependencies' src/. }
function ProjectUnitDirs(Project: TPastelProject): TStringArray;
{ The unit name declared in a Pascal file ("unit Foo;"), or '' for programs. }
function UnitNameOf(const FileName: string): string;
{ Names of the units in the project's src/ folders }
function LibraryUnits(Project: TPastelProject): TStringArray;
{ Folder with the Pastel framework units, '' if it cannot be found. }
function FrameworkDir: string;
function BinutilsHint(const T: TTarget): string;
{ the unit to add to "uses" for a routine Delphi programs know (ShowMessage: Pastel.Dialogs), '' if unknown }
function UnitForIdentifier(const Name: string): string;
function SplitOptions(const S: string): TStringArray;

implementation

uses
  Process, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Pastel.Console, Pastel.Codegen, Pastel.Inspect, Pastel.WIcon, Pastel.Runtime, Pastel.CustomCtl, Pastel.Upgrade, Math;

function FrameworkDir: string;
var
  Home: string;
begin
  Home := GetEnvironmentVariable('PASTEL_HOME');
  if Home = '' then
    { bin/pastel -> the repository (or install) folder above it }
    Home := ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0))));
  Result := IncludeTrailingPathDelimiter(Home) + 'framework' + PathDelim + 'src';
  if not FileExists(Result + PathDelim + 'pastel.app.pas') then
    Result := '';
end;

function FindFpc: string;
var
  Exe: string;
begin
  Result := GetEnvironmentVariable('PASTEL_FPC');
  if (Result <> '') and FileExists(Result) then
    Exit;
  {$IFDEF WINDOWS}
  Exe := 'fpc.exe';
  {$ELSE}
  Exe := 'fpc';
  {$ENDIF}
  Result := ExeSearch(Exe, GetEnvironmentVariable('PATH'));
end;

function RunCapture(const Exe: string; Args: TStrings; const Dir: string;
  out Output: string): Integer;
var
  Proc: TProcess;
  Buf: array[0..4095] of Char;
  N: LongInt;
  Chunk: string;
begin
  Output := '';
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := Exe;
    Proc.Parameters.Assign(Args);
    if Dir <> '' then
      Proc.CurrentDirectory := Dir;
    Proc.Options := [poUsePipes, poStderrToOutPut];
    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        Output := E.Message;
        Exit(-1);
      end;
    end;
    repeat
      N := Proc.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then
      begin
        SetString(Chunk, PChar(@Buf[0]), N);
        Output := Output + Chunk;
      end;
    until N <= 0;
    Proc.WaitOnExit;
    { ExitStatus, not ExitCode: in FPC 3.2.2 ExitCode decodes the value twice on Unix. }
    Result := Proc.ExitStatus;
  finally
    Proc.Free;
  end;
end;

function FpcVersion(const Fpc: string): string;
var
  Args: TStringList;
begin
  Args := TStringList.Create;
  try
    Args.Add('-iV');
    if RunCapture(Fpc, Args, '', Result) <> 0 then
      Result := '';
    Result := Trim(Result);
  finally
    Args.Free;
  end;
end;

function FpcSourceDir: string;
var
  Fpc, Ver, D: string;
  Candidates: array of string;
begin
  Result := GetEnvironmentVariable('FPCDIR');
  if (Result <> '') and DirectoryExists(IncludeTrailingPathDelimiter(Result) + 'rtl') then
    Exit(ExcludeTrailingPathDelimiter(Result));
  Fpc := FindFpc;
  Ver := '';
  if Fpc <> '' then
    Ver := FpcVersion(Fpc);
  Candidates := ['/usr/share/fpcsrc/' + Ver, '/usr/lib/fpc/src', '/usr/local/share/fpcsrc/' + Ver,
    '/usr/local/lib/fpc/src', '/opt/homebrew/share/fpc/source'];
  if Fpc <> '' then
  begin
    { Windows installs and fpcupdeluxe: <root>\bin\<platform>\fpc.exe and <root>\source }
    D := ExtractFileDir(ExtractFileDir(ExtractFileDir(Fpc)));
    Insert(D + PathDelim + 'source', Candidates, 0);
    Insert(ExtractFileDir(D) + PathDelim + 'fpcsrc', Candidates, 0);
  end;
  for D in Candidates do
    if (D <> '') and DirectoryExists(D + PathDelim + 'rtl' + PathDelim + 'objpas') then
      Exit(D);
  Result := '';
end;

function SplitOptions(const S: string): TStringArray;
var
  Parts: TStringArray;
  P: string;
begin
  Result := nil;
  Parts := S.Split([' '], TStringSplitOptions.ExcludeEmpty);
  for P in Parts do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := P;
  end;
end;

function DeleteTree(const Dir: string): Boolean;
var
  SR: TSearchRec;
  Base: string;
begin
  Result := True;
  Base := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Base + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        Result := DeleteTree(Base + SR.Name) and Result
      else
        Result := SysUtils.DeleteFile(Base + SR.Name) and Result;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  Result := RemoveDir(Dir) and Result;
end;

{ Every folder under src/ is searched for units, so people can organise code
  in forms/, models/, services/ without touching any settings. }
procedure CollectSourceDirs(const Root, Rel: string; Dirs: TStrings);
var
  SR: TSearchRec;
begin
  if not DirectoryExists(Root + Rel) then
    Exit;
  Dirs.Add(Rel);
  if FindFirst(Root + Rel + PathDelim + AllFilesMask, faDirectory, SR) = 0 then
  try
    repeat
      if ((SR.Attr and faDirectory) <> 0) and (SR.Name <> '') and (SR.Name[1] <> '.') then
        CollectSourceDirs(Root, Rel + PathDelim + SR.Name, Dirs);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure AddDirs(const Root: string; Project: TPastelProject; Dirs: TStrings);
var
  Rel: TStringList;
  D: string;
begin
  Rel := TStringList.Create;
  try
    CollectSourceDirs(Root, 'src', Rel);
    for D in Rel do
      Dirs.Add(Root + D);
  finally
    Rel.Free;
  end;
  for D in Project.UnitPaths do
    Dirs.Add(ExpandFileName(Root + SetDirSeparators(D)));
end;

{ The compiled units in UnitDir were made from the folders in Sources;
  when the folders change, they are deleted (and so compiled again). }
procedure ForgetUnitsOfOtherSources(const UnitDir, Sources: string);
var
  Stamp, Old: string;
  SR: TSearchRec;
  L: TStringList;
begin
  Stamp := IncludeTrailingPathDelimiter(UnitDir) + 'sources.txt';
  Old := '';
  if FileExists(Stamp) then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(Stamp);
      Old := L.Text;
    finally
      L.Free;
    end;
  end;
  if Old = Sources then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(UnitDir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        DeleteFile(IncludeTrailingPathDelimiter(UnitDir) + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  L := TStringList.Create;
  try
    L.Text := Sources;
    L.SaveToFile(Stamp);
  finally
    L.Free;
  end;
end;

procedure AddDependencies(Project: TPastelProject; Dirs, Seen: TStrings);
var
  D: TDependency;
  Dep: TPastelProject;
begin
  for D in Project.Dependencies do
  begin
    if Seen.IndexOf(D.Root) >= 0 then
      Continue;     { already added, or a cycle }
    Seen.Add(D.Root);
    try
      Dep := TPastelProject.Load(D.Root);
    except
      on E: EProjectError do
        raise EProjectError.CreateFmt('dependency "%s" (%s): %s', [D.Name, D.Path, E.Message]);
    end;
    try
      AddDirs(D.Root, Dep, Dirs);
      AddDependencies(Dep, Dirs, Seen);
    finally
      Dep.Free;
    end;
  end;
end;

function ProjectUnitDirs(Project: TPastelProject): TStringArray;
var
  Dirs, Seen: TStringList;
  I: Integer;
begin
  Result := nil;
  Dirs := TStringList.Create;
  Seen := TStringList.Create;
  try
    Seen.Add(Project.Root);
    AddDirs(Project.Root, Project, Dirs);
    AddDependencies(Project, Dirs, Seen);
    SetLength(Result, Dirs.Count);
    for I := 0 to Dirs.Count - 1 do
      Result[I] := Dirs[I];
  finally
    Dirs.Free;
    Seen.Free;
  end;
end;

{ The name after "unit" at the start of a file, '' when it is not a unit. }
function UnitNameOf(const FileName: string): string;
var
  L: TStringList;
  Line, Low: string;
  I: Integer;
begin
  Result := '';
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for Line in L do
    begin
      Low := LowerCase(Trim(Line));
      if Copy(Low, 1, 5) = 'unit ' then
      begin
        Result := Trim(Copy(Trim(Line), 6, MaxInt));
        I := Pos(';', Result);
        if I > 0 then
          SetLength(Result, I - 1);
        Exit(Trim(Result));
      end;
      if (Copy(Low, 1, 7) = 'program') or (Copy(Low, 1, 7) = 'library') then
        Exit;
    end;
  finally
    L.Free;
  end;
end;

function LibraryUnits(Project: TPastelProject): TStringArray;
var
  Dirs: TStringList;
  D, N: string;
  SR: TSearchRec;
begin
  Result := nil;
  Dirs := TStringList.Create;
  try
    CollectSourceDirs(Project.Root, 'src', Dirs);
    for D in Dirs do
      if FindFirst(Project.Root + D + PathDelim + '*.p*', faAnyFile, SR) = 0 then
      try
        repeat
          if (LowerCase(ExtractFileExt(SR.Name)) <> '.pas') and (LowerCase(ExtractFileExt(SR.Name)) <> '.pp') then
            Continue;
          N := UnitNameOf(Project.Root + D + PathDelim + SR.Name);
          if N = '' then
            Continue;
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := N;
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
  finally
    Dirs.Free;
  end;
end;

{ A library has no program: this one uses every unit, so building it
  compiles them all. }
function WriteLibraryCheck(Project: TPastelProject; const GenDir: string; out Count: Integer): string;
var
  Units: TStringArray;
  Src, U: string;
  L: TStringList;
begin
  Units := LibraryUnits(Project);
  Count := Length(Units);
  if Count = 0 then
    raise EProjectError.Create('this library has no units yet: add one to src/, e.g. src/tools.pas with "unit Tools;"');
  Src := '{ Generated by Pastel: compiles every unit of the library. }' + LineEnding +
    'program ' + StringReplace(Project.Name, '-', '_', [rfReplaceAll]) + '_units;' + LineEnding +
    'uses' + LineEnding;
  for U in Units do
  begin
    if U <> Units[0] then
      Src := Src + ',' + LineEnding;
    Src := Src + '  ' + U;
  end;
  Src := Src + ';' + LineEnding + 'begin' + LineEnding + 'end.' + LineEnding;
  ForceDirectories(Project.Root + GenDir);
  Result := GenDir + PathDelim + 'library_units.pas';
  L := TStringList.Create;
  try
    L.Text := Src;
    L.SaveToFile(Project.Root + Result);
  finally
    L.Free;
  end;
end;

function UnitForIdentifier(const Name: string): string;
const
  Known: array[0..47] of array[0..1] of string = (
    ('ShowMessage', 'Pastel.Dialogs'), ('MessageDlg', 'Pastel.Dialogs'), ('InputBox', 'Pastel.Dialogs'),
    ('InputQuery', 'Pastel.Dialogs'), ('Ask', 'Pastel.Dialogs'), ('OpenFileDialog', 'Pastel.Dialogs'),
    ('SaveFileDialog', 'Pastel.Dialogs'), ('SelectFolderDialog', 'Pastel.Dialogs'), ('mrOk', 'Pastel.Dialogs'),
    ('mrYes', 'Pastel.Dialogs'), ('mrNo', 'Pastel.Dialogs'), ('mrCancel', 'Pastel.Dialogs'),
    ('IntToStr', 'SysUtils'), ('StrToInt', 'SysUtils'), ('StrToIntDef', 'SysUtils'), ('FloatToStr', 'SysUtils'),
    ('StrToFloat', 'SysUtils'), ('Format', 'SysUtils'), ('Trim', 'SysUtils'), ('UpperCase', 'SysUtils'),
    ('LowerCase', 'SysUtils'), ('Now', 'SysUtils'), ('Date', 'SysUtils'), ('Time', 'SysUtils'),
    ('FormatDateTime', 'SysUtils'), ('DateToStr', 'SysUtils'), ('FileExists', 'SysUtils'),
    ('DirectoryExists', 'SysUtils'), ('Exception', 'SysUtils'), ('FreeAndNil', 'SysUtils'),
    ('QuotedStr', 'SysUtils'), ('CompareText', 'SysUtils'), ('Sleep', 'SysUtils'), ('BoolToStr', 'SysUtils'),
    ('TStringList', 'Classes'), ('TStrings', 'Classes'), ('TList', 'Classes'), ('TStream', 'Classes'),
    ('TFileStream', 'Classes'), ('TMemoryStream', 'Classes'), ('Min', 'Math'), ('Max', 'Math'),
    ('Power', 'Math'), ('RoundTo', 'Math'), ('IncDay', 'DateUtils'), ('DaysBetween', 'DateUtils'),
    ('YearOf', 'DateUtils'), ('EncodeDate', 'SysUtils'));
var
  I: Integer;
begin
  Result := '';
  for I := Low(Known) to High(Known) do
    if SameText(Known[I][0], Name) then
      Exit(Known[I][1]);
end;

function BinutilsHint(const T: TTarget): string;
begin
  {$IFDEF LINUX}
  if T.BinutilsPackage <> '' then
    Exit(Format('building for "%s" needs cross binutils: sudo apt install %s',
      [T.Name, T.BinutilsPackage]));
  {$ENDIF}
  Result := Format('building for "%s" needs cross binutils (fpcupdeluxe can install them)',
    [T.Name]);
end;

{ File modification time with sub-second precision (0 if unknown). }
function ModTime(const FileName: string): Int64;
{$IFDEF UNIX}
var
  St: Stat;
begin
  if fpStat(FileName, St) <> 0 then
    Exit(0);
  Result := Int64(St.st_mtime) * 1000000000 + St.st_mtime_nsec;
end;
{$ELSE}
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    Result := Int64(SR.Time) * 1000000000;
    {$IFDEF WINDOWS}
    Result := Int64(SR.FindData.ftLastWriteTime.dwHighDateTime) shl 32 or
      SR.FindData.ftLastWriteTime.dwLowDateTime;
    {$ENDIF}
    FindClose(SR);
  end;
end;
{$ENDIF}

{ Free Pascal compares file times in whole seconds, so a unit saved in the
  same second as its last compile would be skipped. Removing its compiled
  .ppu when the source is newer forces a recompile. }
procedure ForgetStaleUnits(const Root: string; Dirs: TStrings; const UnitDir: string);
var
  D, Ppu, Dir: string;
  SR: TSearchRec;
  SrcTime: Int64;
begin
  for D in Dirs do
  begin
    if D = '' then
      Continue;
    if (D[1] = PathDelim) or ((Length(D) > 1) and (D[2] = ':')) then
      Dir := IncludeTrailingPathDelimiter(D)     { a dependency or the framework }
    else
      Dir := Root + D + PathDelim;
    if FindFirst(Dir + '*.pas', faAnyFile, SR) = 0 then
    try
      repeat
        Ppu := Root + UnitDir + PathDelim + LowerCase(ChangeFileExt(SR.Name, '.ppu'));
        if not FileExists(Ppu) then
          Continue;
        SrcTime := ModTime(Dir + SR.Name);
        if SrcTime > ModTime(Ppu) then
          SysUtils.DeleteFile(Ppu);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

function PascalQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

{ AppInfo: name and version from pastel.toml, available to the program:
    uses AppInfo;  ...  Args.Version := AppVersion; }
procedure WriteAppInfo(Project: TPastelProject; const Dir, Profile, TargetName: string);
var
  Src: string;
  Old: TStringList;
  F: TFileStream;
  FileName: string;
begin
  Src :=
    '{ Generated by Pastel from pastel.toml - do not edit. }' + LineEnding +
    'unit AppInfo;' + LineEnding + LineEnding +
    'interface' + LineEnding + LineEnding +
    'const' + LineEnding +
    '  AppName = ' + PascalQuote(Project.Name) + ';' + LineEnding +
    '  AppVersion = ' + PascalQuote(Project.Version) + ';' + LineEnding +
    '  AppProfile = ' + PascalQuote(Profile) + ';      { debug, release or test }' + LineEnding +
    '  AppTarget = ' + PascalQuote(TargetName) + ';' + LineEnding + LineEnding +
    'implementation' + LineEnding + LineEnding +
    'end.' + LineEnding;
  ForceDirectories(Dir);
  FileName := IncludeTrailingPathDelimiter(Dir) + 'appinfo.pas';
  if FileExists(FileName) then
  begin
    Old := TStringList.Create;
    try
      Old.LoadFromFile(FileName);
      if Old.Text = Src then
        Exit;   { unchanged: keep the compiled unit }
    finally
      Old.Free;
    end;
  end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(Src[1], Length(Src));
  finally
    F.Free;
  end;
end;

procedure WriteIfChanged(const FileName, Src: string);
var
  Old: TStringList;
  F: TFileStream;
begin
  if FileExists(FileName) then
  begin
    Old := TStringList.Create;
    try
      Old.LoadFromFile(FileName);
      if Old.Text = Src then
        Exit;   { unchanged: keep the compiled unit }
    finally
      Old.Free;
    end;
  end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Src <> '' then
      F.WriteBuffer(Src[1], Length(Src));
  finally
    F.Free;
  end;
end;

procedure ListAssets(const Dir, Rel: string; List: TStrings);
var
  SR: TSearchRec;
begin
  if FindFirst(Dir + Rel + AllFilesMask, faAnyFile or faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        ListAssets(Dir, Rel + SR.Name + PathDelim, List)
      else
        List.Add(Rel + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
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

{ ---- Free Pascal packages from their sources ----
  An FPC install often lacks the units of some packages for a cross target
  (fcl-image for Windows...). When the compiler cannot find a unit that is
  in the FPC sources, the package's source folders are added and FPC
  compiles it into the project's build folder, once. }

const
  PlatformDirs: array[0..41] of string = ('unix', 'linux', 'darwin', 'bsd', 'freebsd', 'netbsd', 'openbsd',
    'dragonfly', 'os2', 'emx', 'amiga', 'amicommon', 'aros', 'morphos', 'wince', 'win', 'win16', 'win32',
    'win64', 'winall', 'windows', 'netware', 'netwlibc', 'go32v2', 'msdos', 'dos', 'beos', 'haiku',
    'solaris', 'android', 'qnx', 'wasi', 'wasm', 'nativent', 'symbian', 'embedded', 'macos', 'macosx',
    'atari', 'watcom', 'iphonesim', 'aix');

var
  UnitIndex: TStringList = nil;

{ unit name -> package folder, from FpcSourceDir/packages/*/src }
procedure BuildUnitIndex;

  procedure Scan(const Pkg, Dir: string);
  var
    SR: TSearchRec;
    Ext: string;
  begin
    if FindFirst(Dir + PathDelim + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        if (SR.Attr and faDirectory) <> 0 then
          Scan(Pkg, Dir + PathDelim + SR.Name)
        else
        begin
          Ext := LowerCase(ExtractFileExt(SR.Name));
          { a unit can be in several packages (serial: rtl-extra/src/win, rtl-extra/src/unix,
            morphunits/src): all are kept, PackageForUnit chooses }
          if (Ext = '.pp') or (Ext = '.pas') then
            UnitIndex.Add(LowerCase(ChangeFileExt(SR.Name, '')) + '=' + Pkg + '|' + Dir);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

var
  Src: string;
  SR: TSearchRec;
begin
  if UnitIndex <> nil then
    Exit;
  UnitIndex := TStringList.Create;
  Src := FpcSourceDir;
  if Src = '' then
    Exit;
  Src := Src + PathDelim + 'packages';
  if FindFirst(Src + PathDelim + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) and
        DirectoryExists(Src + PathDelim + SR.Name + PathDelim + 'src') then
        Scan(Src + PathDelim + SR.Name, Src + PathDelim + SR.Name + PathDelim + 'src');
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  UnitIndex.Sorted := True;
end;

function PackageDirs(const Pkg, OS: string): TStringArray; forward;

{ 'win', 'src/unix/x': a folder for some systems only }
function InPlatformDir(const Rel: string): Boolean;
var
  Part, P: string;
begin
  for Part in Rel.Split([PathDelim]) do
    for P in PlatformDirs do
      if LowerCase(Part) = P then
        Exit(True);
  Result := False;
end;

{ the package with the unit for this OS: a folder made for the OS first
  (rtl-extra/src/win), then one for every OS (fcl-json/src) }
function PackageForUnit(const UnitName, OS: string): string;
var
  Pass, I, P: Integer;
  Pkg, Dir, D: string;
begin
  Result := '';
  for Pass := 1 to 2 do
    for I := 0 to UnitIndex.Count - 1 do
      if UnitIndex.Names[I] = LowerCase(UnitName) then
      begin
        P := Pos('|', UnitIndex.ValueFromIndex[I]);
        Pkg := Copy(UnitIndex.ValueFromIndex[I], 1, P - 1);
        Dir := Copy(UnitIndex.ValueFromIndex[I], P + 1, MaxInt);
        if (Pass = 1) <> InPlatformDir(Copy(Dir, Length(Pkg) + 6, MaxInt)) then
          Continue;
        { packages for other systems only (morphunits, arosunits, ...) }
        if (Pass = 2) and ((Pos('units', ExtractFileName(Pkg)) > 0) and
           (Pos('win', ExtractFileName(Pkg)) = 0)) then
          Continue;
        for D in PackageDirs(Pkg, OS) do
          if D = Dir then
            Exit(Pkg);
      end;
end;

{ the unit in "Fatal: Can't find unit X used by Y", '' when there is none }
function MissingUnit(const CompilerOut: string): string;
var
  P, E: Integer;
begin
  Result := '';
  P := Pos('Can''t find unit ', CompilerOut);
  if P = 0 then
    Exit;
  P := P + Length('Can''t find unit ');
  E := P;
  while (E <= Length(CompilerOut)) and (CompilerOut[E] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
    Inc(E);
  Result := Copy(CompilerOut, P, E - P);
end;

{ the package's source folders that belong to the target OS }
function PackageDirs(const Pkg, OS: string): TStringArray;

  function Wanted(const Name: string): Boolean;
  var
    N, P: string;
  begin
    N := LowerCase(Name);
    if (N = 'examples') or (N = 'tests') or (N = 'test') or (N = 'dummy') then
      Exit(False);
    { rtl-objpas: common/ is for the OSes without their own version (not Windows) }
    if (N = 'common') and (Copy(OS, 1, 3) = 'win') then
      Exit(False);
    for P in PlatformDirs do
      if N = P then
      begin
        if Copy(OS, 1, 3) = 'win' then
          Exit((N = 'win') or (N = 'winall') or (N = 'windows') or (N = OS))
        else if OS = 'darwin' then
          Exit((N = 'unix') or (N = 'bsd') or (N = 'darwin'))
        else if (OS = 'linux') or (OS = 'android') then
          Exit((N = 'unix') or (N = 'linux') or (N = OS))
        else
          Exit((N = 'unix') or (N = OS));
      end;
    Result := True;
  end;

  procedure Scan(const Dir: string; var L: TStringArray);
  var
    SR: TSearchRec;
  begin
    SetLength(L, Length(L) + 1);
    L[High(L)] := Dir;
    if FindFirst(Dir + PathDelim + '*', faDirectory, SR) = 0 then
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) and Wanted(SR.Name) then
          Scan(Dir + PathDelim + SR.Name, L);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

begin
  Result := nil;
  Scan(Pkg + PathDelim + 'src', Result);
end;

{ assets/ -> AppAssets: in release builds the bytes, in debug builds the paths.
  False when the project has no assets. }
function WriteAppAssets(Project: TPastelProject; const Dir: string; Embed, Windows: Boolean): Boolean;
var
  AssetDir, Src, Name, Bytes, Res, Err: string;
  Files: TStringList;
  I, J, N: Integer;
  M: TMemoryStream;
  P: PByte;
begin
  AssetDir := Project.Root + 'assets' + PathDelim;
  Result := DirectoryExists(AssetDir);
  if not Result then
    Exit;
  Files := TStringList.Create;
  try
    Files.Sorted := True;
    ListAssets(AssetDir, '', Files);
    Src := '{ Generated by Pastel from assets/ - do not edit. }' + LineEnding +
      'unit AppAssets;' + LineEnding + LineEnding + 'interface' + LineEnding + LineEnding +
      'implementation' + LineEnding + LineEnding + 'uses' + LineEnding + '  Pastel.Assets;' + LineEnding + LineEnding;
    { a Windows program shows assets/icon.png in Explorer and the taskbar }
    if Windows and FileExists(AssetDir + 'icon.png') then
    begin
      Res := IncludeTrailingPathDelimiter(Dir) + 'appicon.res';
      if not FileExists(Res) or (FileAge(Res) < FileAge(AssetDir + 'icon.png')) then
      begin
        Err := WriteIconRes(AssetDir + 'icon.png', Res);
        if Err <> '' then
          raise EProjectError.Create('assets/icon.png: ' + Err);
      end;
      Src := Src + '{$R appicon.res}' + LineEnding + LineEnding;
    end;
    if Embed then
      for I := 0 to Files.Count - 1 do
      begin
        M := TMemoryStream.Create;
        try
          M.LoadFromFile(AssetDir + Files[I]);
          N := M.Size;
          Src := Src + Format('const'#10'  Asset%d: array[0..%d] of Byte = (', [I, Math.Max(0, N - 1)]);
          if N = 0 then
            Src := Src + '0'
          else
          begin
            P := M.Memory;
            Bytes := '';
            for J := 0 to N - 1 do
            begin
              if J > 0 then
                Bytes := Bytes + ',';
              if J mod 24 = 0 then
                Bytes := Bytes + #10'    ';
              Bytes := Bytes + IntToStr(P[J]);
            end;
            Src := Src + Bytes;
          end;
          Src := Src + ');' + LineEnding + LineEnding;
        finally
          M.Free;
        end;
      end;
    Src := Src + 'initialization' + LineEnding;
    for I := 0 to Files.Count - 1 do
    begin
      Name := StringReplace(Files[I], PathDelim, '/', [rfReplaceAll]);
      if Embed then
        Src := Src + Format('  RegisterAsset(%s, @Asset%d, %d);', [PascalQuote(Name), I,
          FileSizeOf(AssetDir + Files[I])]) + LineEnding
      else
        Src := Src + Format('  RegisterAssetFile(%s, %s);', [PascalQuote(Name),
          PascalQuote(AssetDir + Files[I])]) + LineEnding;
    end;
    Src := Src + 'end.' + LineEnding;
    ForceDirectories(Dir);
    WriteIfChanged(IncludeTrailingPathDelimiter(Dir) + 'appassets.pas', Src);
  finally
    Files.Free;
  end;
end;

function IsNoise(const Line: string): Boolean;
begin
  Result := (Pos('Compilation aborted', Line) > 0) or
            (Pos('returned an error exitcode', Line) > 0) or
            (Pos('errors compiling module, stopping', Line) > 0);
end;

procedure WriteOverlay(const FileName, Text: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    if Text <> '' then
      F.WriteBuffer(Text[1], Length(Text));
  finally
    F.Free;
  end;
end;

procedure CopyOverlay(const Source, Dest: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(Source);
    WriteOverlay(Dest, L.Text);
  finally
    L.Free;
  end;
end;

function BuildProject(Project: TPastelProject; const Opts: TBuildOptions;
  out ExePath: string): Boolean;
var
  Fpc, Profile, OutDir, UnitDir, CompilerOut, Line, D, Opt: string;
  Args, Dirs, Lines: TStringList;
  Code, Errors, Warnings, I: Integer;
  Started: QWord;
  Host, MissingTarget, MissingPackages, HaveBinutils: Boolean;
  UnitHints: TStringList;
  NotFound, KnownUnit: string;
  BinPrefix, GenDir, Framework, LibMain, OverlayDir, OverlayMain, MainSrc: string;
  LibCheck, HasAssets: Boolean;
  LibUnits: Integer;
  Gen: TCodegenResult;
  Issues: TIssues;
  Missing, Pkg, PkgFile, FpcSrc: string;
  Pkgs: TStringList;
  Tries, Pkgs0: Integer;
  DesignerHost, HostErr, HostOut: string;
  HostArgs: TStringList;

  procedure AddPackage(const APkg: string);
  var
    PD: string;
    MainArg: string;
  begin
    { before the main file, the last argument }
    MainArg := Args[Args.Count - 1];
    Args.Delete(Args.Count - 1);
    for PD in PackageDirs(APkg, Opts.Target.OS) do
    begin
      Args.Add('-Fu' + PD);
      Args.Add('-Fi' + PD);
    end;
    Args.Add(MainArg);
  end;

begin
  Result := False;
  ExePath := '';
  OverlayMain := '';
  OverlayDir := '';
  MainSrc := '';
  Fpc := FindFpc;
  if Fpc = '' then
  begin
    Fail('the Free Pascal compiler (fpc) was not found');
    {$IFDEF LINUX}
    Hint('install it with "sudo apt install fpc", or run "pastel doctor"');
    {$ELSE}
    Hint('install it from https://www.freepascal.org/download.html, or run "pastel doctor"');
    {$ENDIF}
    Exit;
  end;

  if Opts.Release then Profile := 'release' else Profile := 'debug';
  if Opts.Profile <> '' then
    Profile := Opts.Profile;
  if Opts.CheckOnly then
    Profile := 'check';
  OutDir := 'build' + PathDelim + Opts.Target.Name + PathDelim + Profile;
  UnitDir := OutDir + PathDelim + 'units';
  ForceDirectories(Project.Root + UnitDir);
  if Opts.OutName <> '' then
    ExePath := OutDir + PathDelim + Opts.OutName + Opts.Target.ExeExt
  else
    ExePath := OutDir + PathDelim + Project.Name + Opts.Target.ExeExt;
  Host := IsHost(Opts.Target);

  { every project can use the Pastel units (Pastel.Testing, ...); apps need them }
  Framework := FrameworkDir;
  if Project.Kind = 'app' then
  begin
    if Framework = '' then
    begin
      Fail('the Pastel framework was not found next to the pastel program');
      Hint('set PASTEL_HOME to the folder that contains framework/');
      Exit;
    end;
  end;

  { .pform files -> generated units. Debug builds point at the .pform files
    so the running app can reload them (hot reload). }
  if not Opts.Quiet and not Opts.CheckOnly then
    CheckProjectVersion(Project);
  { check .pform files first: the compiler cannot see mistakes in them }
  if Opts.CheckOnly then
    Issues := nil
  else if HasProjectControls(Project.Root) and not IsDesignerHost then
  begin
    { the project's own controls: checked by a pastel that knows them }
    Issues := nil;
    DesignerHost := EnsureDesignerHost(Project.Root, HostErr);
    if DesignerHost = '' then
    begin
      Fail(HostErr);
      Exit;
    end;
    HostArgs := TStringList.Create;
    try
      HostArgs.Add('check');
      if RunCapture(DesignerHost, HostArgs, Project.Root, HostOut) <> 0 then
      begin
        Write(HostOut);
        Fail(Format('could not compile %s (errors in .pform files)', [Project.Name]));
        Exit;
      end;
    finally
      HostArgs.Free;
    end;
  end
  else
    Issues := CheckProject(Project.Root);
  if Length(Issues) > 0 then
  begin
    PrintIssues(Issues, False);
    Errors := 0;
    for I := 0 to High(Issues) do
      if Issues[I].Severity = 'error' then
        Inc(Errors);
    if Errors > 0 then
    begin
      Fail(Format('could not compile %s (%d error(s) in .pform files)', [Project.Name, Errors]));
      Exit;
    end;
  end;

  GenDir := OutDir + PathDelim + 'gen';
  WriteAppInfo(Project, Project.Root + GenDir, Profile, Opts.Target.Name);
  try
    HasAssets := WriteAppAssets(Project, Project.Root + GenDir, Opts.Release, Opts.Target.OS.StartsWith('win'));
  except
    on E: EProjectError do
    begin
      Fail(E.Message);
      Exit;
    end;
  end;
  LibCheck := (Project.Kind = 'lib') and (Opts.MainFile = '') and (Project.MainFile = '');
  LibUnits := 0;
  if LibCheck then
  begin
    try
      LibMain := WriteLibraryCheck(Project, GenDir, LibUnits);
    except
      on E: EProjectError do
      begin
        Fail(E.Message);
        Exit;
      end;
    end;
    ExePath := OutDir + PathDelim + Project.Name + '-units' + Opts.Target.ExeExt;
  end;
  Gen := GenerateForms(Project.Root, GenDir, not Opts.Release);
  if Gen.Errors > 0 then
  begin
    Fail(Format('could not compile %s (%d error(s) in .pform files)', [Project.Name, Gen.Errors]));
    Exit;
  end;

  Args := TStringList.Create;
  Dirs := TStringList.Create;
  Lines := TStringList.Create;
  UnitHints := TStringList.Create;
  try
    Args.Add('-P' + Opts.Target.CPU);
    Args.Add('-T' + Opts.Target.OS);
    for Opt in SplitOptions(Opts.Target.Options) do
      Args.Add(Opt);
    { the RTL "pastel doctor --install" compiled for this target }
    D := UserRtlDir(Fpc, Opts.Target);
    if (D <> '') and FileExists(D + 'system.ppu') then
      Args.Add('-Fu' + D);
    BinPrefix := FindBinutilsPrefix(Opts.Target, HaveBinutils);
    if BinPrefix <> '' then
      Args.Add('-XP' + BinPrefix);

    if Project.Mode = 'delphi' then
      Args.Add('-Mdelphi')
    else
    begin
      Args.Add('-Mobjfpc');
      Args.Add('-Sh');
    end;

    Args.Add('-FU' + UnitDir);
    Args.Add('-o' + ExePath);

    CollectSourceDirs(Project.Root, 'src', Dirs);
    for D in Opts.ExtraDirs do
      Dirs.Add(D);
    for D in Project.UnitPaths do
      Dirs.Add(SetDirSeparators(D));
    try
      for D in ProjectUnitDirs(Project) do
        if Dirs.IndexOf(D) < 0 then
          if Copy(D, 1, Length(Project.Root)) = Project.Root then
          begin
            if Dirs.IndexOf(Copy(D, Length(Project.Root) + 1, MaxInt)) < 0 then
              Dirs.Add(D);
          end
          else
            Dirs.Add(D);    { dependencies }
    except
      on E: EProjectError do
      begin
        Fail(E.Message);
        Exit;
      end;
    end;
    Dirs.Add(GenDir);
    if Framework <> '' then
      Dirs.Add(Framework);
    { other source folders (another version of a package): the compiled
      units are of the old ones, and may look newer than the new sources }
    ForgetUnitsOfOtherSources(Project.Root + UnitDir, Dirs.Text);
    if Opts.OverlayFile <> '' then
    begin
      { the unsaved text in a folder searched first; the program is copied
        there too, as FPC looks next to the program before the unit paths }
      OverlayDir := OutDir + PathDelim + 'overlay';
      ForceDirectories(Project.Root + OverlayDir);
      MainSrc := Project.MainFile;
      if Opts.MainFile <> '' then
        MainSrc := Opts.MainFile;
      if SameFileName(ExpandFileName(Project.Root + MainSrc), Opts.OverlayFile) then
        WriteOverlay(Project.Root + OverlayDir + PathDelim + ExtractFileName(MainSrc), Opts.OverlayText)
      else
      begin
        CopyOverlay(Project.Root + MainSrc, Project.Root + OverlayDir + PathDelim + ExtractFileName(MainSrc));
        WriteOverlay(Project.Root + OverlayDir + PathDelim + ExtractFileName(Opts.OverlayFile), Opts.OverlayText);
      end;
      Dirs.Insert(0, OverlayDir);
      if Dirs.IndexOf(ExtractFileDir(MainSrc)) < 0 then
        Dirs.Add(ExtractFileDir(MainSrc));
      OverlayMain := OverlayDir + PathDelim + ExtractFileName(MainSrc);
    end;
    for D in Dirs do
    begin
      Args.Add('-Fu' + D);
      Args.Add('-Fi' + D);
    end;
    ForgetStaleUnits(Project.Root, Dirs, UnitDir);

    { threads, UTF-8 strings and console on every platform }
    if Framework <> '' then
    begin
      if HasAssets then
        Args.Add('-FaPastel.Startup,Pastel.ErrorExit,AppAssets')
      else
        Args.Add('-FaPastel.Startup,Pastel.ErrorExit');
    end;
    Args.Add('-dPASTEL');
    if Opts.Release then
    begin
      Args.Add('-dPASTEL_RELEASE');
      { GUI apps on Windows: no console window in release builds }
      if (Project.Kind = 'app') and ((Opts.Target.OS = 'win32') or (Opts.Target.OS = 'win64')) then
        Args.Add('-WG');
      Args.Add('-O2');
      Args.Add('-Xs');
      Args.Add('-CX');
      Args.Add('-XX');
    end
    else
    begin
      Args.Add('-dPASTEL_DEBUG');
      Args.Add('-gw3');   { DWARF 3: gdb shows strings and dynamic arrays as values }
      Args.Add('-gl');
      Args.Add('-O-');
      Args.Add('-Ci');
      Args.Add('-Co');
      Args.Add('-Cr');
      Args.Add('-Sa');
    end;
    for D in Project.Defines do
      Args.Add('-d' + D);
    { [profile.x]; tests are debug builds, so they get the debug settings too }
    for I := 0 to High(ProfileNames) do
      if (ProfileNames[I] = Profile) or ((Profile = 'test') and (ProfileNames[I] = 'debug')) then
      begin
        for D in Project.ProfileDefines[I] do
          Args.Add('-d' + D);
        for D in Project.ProfileOptions[I] do
          Args.Add(D);
      end;
    for D in Opts.Defines do
      Args.Add('-d' + D);

    { -vb: full file paths in messages; shortened below to project-relative. }
    Args.Add('-vewnb');
    if Opts.CheckOnly then
      Args.Add('-Cn');
    if OverlayMain <> '' then
      Args.Add(OverlayMain)
    else if Opts.MainFile <> '' then
      Args.Add(Opts.MainFile)
    else if LibCheck then
      Args.Add(LibMain)
    else
      Args.Add(Project.MainFile);

    if not Opts.Quiet and not Opts.CheckOnly then
    begin
      Status('Compiling', Format('%s v%s (%s, %s)',
        [Project.Name, Project.Version, Opts.Target.Name, Profile]));
    end;
    if Opts.Verbose then
      WriteLn(Dim('             ' + Fpc + ' ' + StringReplace(Trim(Args.Text),
        LineEnding, ' ', [rfReplaceAll])));

    Started := GetTickCount64;
    { packages compiled from the FPC sources in an earlier build }
    PkgFile := Project.Root + UnitDir + PathDelim + 'fpc-packages.txt';
    Pkgs := TStringList.Create;
    Pkgs0 := 0;
    try
      if FileExists(PkgFile) then
        Pkgs.LoadFromFile(PkgFile);
      for Pkg in Pkgs do
        if DirectoryExists(Pkg) then
          AddPackage(Pkg);
      Code := RunCapture(Fpc, Args, Project.Root, CompilerOut);
      Tries := 0;
      while (Code <> 0) and (Tries < 30) do
      begin
        Missing := MissingUnit(CompilerOut);
        if Missing = '' then
          Break;
        BuildUnitIndex;
        Pkg := PackageForUnit(Missing, Opts.Target.OS);
        if (Pkg = '') or (Pkgs.IndexOf(Pkg) >= 0) then
          Break;
        Pkgs.Add(Pkg);
        if not Opts.Quiet and not Opts.CheckOnly then
          Status('Compiling', Format('the Free Pascal package %s for %s from its sources (once)',
            [ExtractFileName(Pkg), Opts.Target.Name]));
        AddPackage(Pkg);
        Code := RunCapture(Fpc, Args, Project.Root, CompilerOut);
        Inc(Tries);
      end;
      Pkgs0 := Pkgs.Count;
      if Pkgs.Count > 0 then
      begin
        ForceDirectories(Project.Root + UnitDir);
        Pkgs.SaveToFile(PkgFile);
      end;
    finally
      Pkgs.Free;
    end;

    Errors := 0;
    Warnings := 0;
    FpcSrc := '';
    if Pkgs0 > 0 then
      FpcSrc := FpcSourceDir;
    MissingTarget := False;
    MissingPackages := False;
    Lines.Text := CompilerOut;
    if Opts.CheckOnly then
    begin
      { messages about the overlay copies are about the real files }
      for I := 0 to Lines.Count - 1 do
      begin
        Line := Lines[I];
        if OverlayMain <> '' then
        begin
          Line := StringReplace(Line, Project.Root + OverlayDir + PathDelim + ExtractFileName(Opts.OverlayFile),
            Opts.OverlayFile, [rfReplaceAll]);
          Line := StringReplace(Line, OverlayDir + PathDelim + ExtractFileName(Opts.OverlayFile),
            Opts.OverlayFile, [rfReplaceAll]);
          Line := StringReplace(Line, OverlayMain, MainSrc, [rfReplaceAll]);
        end;
        if Assigned(Opts.Messages) then
          Opts.Messages.Add(Line);
      end;
      Result := Code = 0;
      Exit;
    end;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := StringReplace(Lines[I], Project.Root, '', [rfReplaceAll]);
      if Copy(Line, 1, 2) = '.' + PathDelim then
        Delete(Line, 1, 2);
      if (Pos('Can''t find unit system', Line) > 0) or
         (Pos('can''t be executed', Line) > 0) or
         (Pos('Can''t find unit sysutils', Line) > 0) or
         (Pos('not found, switching to external', Line) > 0) then
        MissingTarget := True;
      { a cross-compiler with only the RTL: FPC's packages are missing }
      if (Pos('Can''t find unit fpjson', Line) > 0) or (Pos('Can''t find unit fphttpserver', Line) > 0) or
         (Pos('Can''t find unit sqldb', Line) > 0) or (Pos('Can''t find unit process', Line) > 0) then
        MissingPackages := True;
      if Opts.Verbose then
      begin
        WriteLn(Line);
        if Pos('Error:', Line) > 0 then
          Inc(Errors);
        Continue;
      end;
      if IsNoise(Line) then
        Continue;
      { warnings and notes in FPC's own sources are not the project's }
      if (FpcSrc <> '') and (Copy(Line, 1, Length(FpcSrc)) = FpcSrc) and
        (Pos('Error:', Line) = 0) and (Pos('Fatal:', Line) = 0) then
        Continue;
      if (Pos('Error:', Line) > 0) or (Pos('Fatal:', Line) > 0) then
      begin
        Inc(Errors);
        WriteLn(Red(Line));
        { Identifier not found "ShowMessage": say which unit has it }
        if Pos('Identifier not found "', Line) > 0 then
        begin
          NotFound := Copy(Line, Pos('Identifier not found "', Line) + 22, MaxInt);
          NotFound := Copy(NotFound, 1, Pos('"', NotFound) - 1);
          KnownUnit := UnitForIdentifier(NotFound);
          if (KnownUnit <> '') and (UnitHints.IndexOf(NotFound + ' is in ' + KnownUnit) < 0) then
            UnitHints.Add(NotFound + ' is in ' + KnownUnit);
        end;
      end
      else if Pos('Warning:', Line) > 0 then
      begin
        Inc(Warnings);
        WriteLn(Yellow(Line));
      end
      else if Pos('Note:', Line) > 0 then
        WriteLn(Cyan(Line));
    end;

    if Code <> 0 then
    begin
      if Code = -1 then
        Fail('could not start the compiler: ' + CompilerOut)
      else
        Fail(Format('could not compile %s (%d error(s))', [Project.Name, Errors]));
      for I := 0 to UnitHints.Count - 1 do
        Hint(Format('%s: add it to the uses clause of the unit', [UnitHints[I]]));
      if not HaveBinutils then
        Hint(BinutilsHint(Opts.Target))
      else if MissingPackages and not Host then
        Hint(Format('the compiler for "%s" has only the basic units, not FPC''s packages (fcl-json, fcl-web, fcl-db); ' +
          'fpcupdeluxe installs a complete cross-compiler', [Opts.Target.Name]))
      else if MissingTarget and not Host then
        if CanBuildRtl(Opts.Target) then
          Hint(Format('this computer cannot build for "%s" yet; "pastel doctor --install %s" sets it up',
            [Opts.Target.Name, Opts.Target.Name]))
        else
          Hint(Format('this computer cannot build for "%s" yet; run "pastel doctor" to see what is missing',
            [Opts.Target.Name]));
      Exit;
    end;

    if LibCheck then
    begin
      SysUtils.DeleteFile(Project.Root + ExePath);   { only the compiled units matter }
      ExePath := '';
    end;
    if not Opts.Quiet then
    begin
      Status('Finished', Format('%s in %.2fs%s', [Profile,
        (GetTickCount64 - Started) / 1000,
        BoolToStr(Warnings > 0, Format(', %d warning(s)', [Warnings]), '')]));
      if LibCheck then
        Status('Checked', Format('%d unit(s) of the library compile', [LibUnits]))
      else
        Status('Output', ExePath);
    end;
    { a desktop app for Windows needs SDL2.dll and freetype.dll beside it }
    if (Project.Kind = 'app') and not LibCheck and (Length(RuntimeFiles(Opts.Target)) > 0) then
    begin
      if Length(CopyRuntime(Opts.Target, Project.Root + OutDir)) < Length(RuntimeFiles(Opts.Target)) then
        if not Opts.Quiet then
          Hint(Format('the app needs %s next to it on Windows; get them once with: pastel doctor --install %s',
            [string.Join(' and ', RuntimeFiles(Opts.Target)), Opts.Target.Name]));
    end;
    Result := True;
  finally
    Args.Free;
    Dirs.Free;
    Lines.Free;
    UnitHints.Free;
  end;
end;

function RunProject(Project: TPastelProject; Release, Verbose: Boolean;
  const ProgramArgs: TStringArray): Integer;
var
  Opts: TBuildOptions;
  ExePath, A: string;
  Proc: TProcess;
begin
  Opts := Default(TBuildOptions);
  Opts.Target := HostTarget;
  Opts.Release := Release;
  Opts.Verbose := Verbose;
  if not BuildProject(Project, Opts, ExePath) then
    Exit(1);
  Status('Running', ExePath);
  if Project.Kind = 'app' then
    WriteLn(Dim('             edit .pform files while the app runs: changes appear immediately'));
  WriteLn;
  Flush(Output);
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := Project.Root + ExePath;
    for A in ProgramArgs do
      Proc.Parameters.Add(A);
    Proc.Options := [poWaitOnExit];
    Proc.Execute;
    { ExitStatus, not ExitCode: in FPC 3.2.2 ExitCode decodes the value twice on Unix. }
    Result := Proc.ExitStatus;
  finally
    Proc.Free;
  end;
end;

procedure CleanProject(Project: TPastelProject);
var
  Dir: string;
begin
  Dir := Project.Root + 'build';
  if not DirectoryExists(Dir) then
  begin
    Status('Clean', 'nothing to remove');
    Exit;
  end;
  if DeleteTree(Dir) then
    Status('Removed', 'build' + PathDelim)
  else
    Fail('could not remove everything in build' + PathDelim + ' (is the program still running?)');
end;

finalization
  FreeAndNil(UnitIndex);

end.
