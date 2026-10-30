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
  end;

function FindFpc: string;
function FpcVersion(const Fpc: string): string;
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
function SplitOptions(const S: string): TStringArray;

implementation

uses
  Process, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Pastel.Console, Pastel.Codegen, Pastel.Inspect;

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

function IsNoise(const Line: string): Boolean;
begin
  Result := (Pos('Compilation aborted', Line) > 0) or
            (Pos('returned an error exitcode', Line) > 0) or
            (Pos('errors compiling module, stopping', Line) > 0);
end;

function BuildProject(Project: TPastelProject; const Opts: TBuildOptions;
  out ExePath: string): Boolean;
var
  Fpc, Profile, OutDir, UnitDir, CompilerOut, Line, D, Opt: string;
  Args, Dirs, Lines: TStringList;
  Code, Errors, Warnings, I: Integer;
  Started: QWord;
  Host, MissingTarget, MissingPackages, HaveBinutils: Boolean;
  BinPrefix, GenDir, Framework, LibMain: string;
  LibCheck: Boolean;
  LibUnits: Integer;
  Gen: TCodegenResult;
  Issues: TIssues;
begin
  Result := False;
  ExePath := '';
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
  { check .pform files first: the compiler cannot see mistakes in them }
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
  try
    Args.Add('-P' + Opts.Target.CPU);
    Args.Add('-T' + Opts.Target.OS);
    for Opt in SplitOptions(Opts.Target.Options) do
      Args.Add(Opt);
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
    for D in Dirs do
    begin
      Args.Add('-Fu' + D);
      Args.Add('-Fi' + D);
    end;
    ForgetStaleUnits(Project.Root, Dirs, UnitDir);

    { threads, UTF-8 strings and console on every platform }
    if Framework <> '' then
      Args.Add('-FaPastel.Startup,Pastel.ErrorExit');
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
    if Opts.MainFile <> '' then
      Args.Add(Opts.MainFile)
    else if LibCheck then
      Args.Add(LibMain)
    else
      Args.Add(Project.MainFile);

    if not Opts.Quiet then
      Status('Compiling', Format('%s v%s (%s, %s)',
        [Project.Name, Project.Version, Opts.Target.Name, Profile]));
    if Opts.Verbose then
      WriteLn(Dim('             ' + Fpc + ' ' + StringReplace(Trim(Args.Text),
        LineEnding, ' ', [rfReplaceAll])));

    Started := GetTickCount64;
    Code := RunCapture(Fpc, Args, Project.Root, CompilerOut);

    Errors := 0;
    Warnings := 0;
    MissingTarget := False;
    MissingPackages := False;
    Lines.Text := CompilerOut;
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
      if (Pos('Error:', Line) > 0) or (Pos('Fatal:', Line) > 0) then
      begin
        Inc(Errors);
        WriteLn(Red(Line));
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
      if not HaveBinutils then
        Hint(BinutilsHint(Opts.Target))
      else if MissingPackages and not Host then
        Hint(Format('the compiler for "%s" has only the basic units, not FPC''s packages (fcl-json, fcl-web, fcl-db); ' +
          'fpcupdeluxe installs a complete cross-compiler', [Opts.Target.Name]))
      else if MissingTarget and not Host then
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
    Result := True;
  finally
    Args.Free;
    Dirs.Free;
    Lines.Free;
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

end.
