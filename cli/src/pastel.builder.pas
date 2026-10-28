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
{ Folder with the Pastel framework units, '' if it cannot be found. }
function FrameworkDir: string;
function BinutilsHint(const T: TTarget): string;
function SplitOptions(const S: string): TStringArray;

implementation

uses
  Process, Pastel.Console, Pastel.Codegen, Pastel.Inspect;

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
        Result := DeleteFile(Base + SR.Name) and Result;
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
  Host, MissingTarget, HaveBinutils: Boolean;
  BinPrefix, GenDir, Framework: string;
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
  OutDir := 'build' + PathDelim + Opts.Target.Name + PathDelim + Profile;
  UnitDir := OutDir + PathDelim + 'units';
  ForceDirectories(Project.Root + UnitDir);
  ExePath := OutDir + PathDelim + Project.Name + Opts.Target.ExeExt;
  Host := IsHost(Opts.Target);

  Framework := '';
  if Project.Kind = 'app' then
  begin
    Framework := FrameworkDir;
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
    for D in Project.UnitPaths do
      Dirs.Add(SetDirSeparators(D));
    if Gen.Generated > 0 then
      Dirs.Add(GenDir);
    if Framework <> '' then
      Dirs.Add(Framework);
    for D in Dirs do
    begin
      Args.Add('-Fu' + D);
      Args.Add('-Fi' + D);
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
      Args.Add('-g');
      Args.Add('-gl');
      Args.Add('-O-');
      Args.Add('-Ci');
      Args.Add('-Co');
      Args.Add('-Cr');
      Args.Add('-Sa');
    end;
    for D in Project.Defines do
      Args.Add('-d' + D);

    { -vb: full file paths in messages; shortened below to project-relative. }
    Args.Add('-vewnb');
    Args.Add(Project.MainFile);

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
    Lines.Text := CompilerOut;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := StringReplace(Lines[I], Project.Root, '', [rfReplaceAll]);
      if (Pos('Can''t find unit system', Line) > 0) or
         (Pos('can''t be executed', Line) > 0) or
         (Pos('Can''t find unit sysutils', Line) > 0) or
         (Pos('not found, switching to external', Line) > 0) then
        MissingTarget := True;
      if Opts.Verbose then
      begin
        WriteLn(Line);
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
      else if MissingTarget and not Host then
        Hint(Format('this computer cannot build for "%s" yet; run "pastel doctor" to see what is missing',
          [Opts.Target.Name]));
      Exit;
    end;

    Status('Finished', Format('%s in %.2fs%s', [Profile,
      (GetTickCount64 - Started) / 1000,
      BoolToStr(Warnings > 0, Format(', %d warning(s)', [Warnings]), '')]));
    Status('Output', ExePath);
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
