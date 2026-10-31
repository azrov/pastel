{ Pastel - controls of the project itself (src/controls/).

  A unit in src/controls/ that registers a control:

    unit StarRating;
    ...
    initialization
      RegisterControl(TStarRating);
    end.

  can be used in .pform files like the built-in controls. "pastel build"
  finds the unit for the generated form code. "pastel schema", "check" and
  "preview" (and so the VS Code designer and its toolbox) need the real
  class: they run a copy of the pastel tool that is compiled together with
  the project's controls (build/designer/), made again when a control
  changes.
  Part of the Pastel project, MIT License. }
unit Pastel.CustomCtl;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ ClassName=UnitName for every control registered in Root/src/controls; nil when there are none. }
function ProjectControls(const Root: string): TStringList;
function HasProjectControls(const Root: string): Boolean;
{ The pastel tool with the project's controls, built when missing or out of
  date; '' with Err set when it cannot be built. }
function EnsureDesignerHost(const Root: string; out Err: string): string;
{ Runs the command line again with that tool, when this is not it already and
  the project at Root (or the current folder) has controls. True when it ran;
  ExitCode is its exit code then. }
function RunInDesignerHost(const Root: string; out ExitCode: Integer): Boolean;
{ This program is such a copy. }
function IsDesignerHost: Boolean;

implementation

uses
  Math, Process, RegExpr, Pastel.Files, Pastel.Builder, Pastel.Project;

const
  HostEnv = 'PASTEL_DESIGNER_HOST';

function ControlsDir(const Root: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Root) + 'src' + PathDelim + 'controls';
end;

function ControlFiles(const Root: string): TStringArray;
begin
  if DirectoryExists(ControlsDir(Root)) then
    Result := ListFiles(ControlsDir(Root), '*.pas', False)
  else
    Result := nil;
end;

function ProjectControls(const Root: string): TStringList;
var
  F, Text, UnitName: string;
  R: TRegExpr;
begin
  Result := nil;
  R := TRegExpr.Create('\bRegister(Control|NonVisual)\s*\(\s*(T\w+)\s*\)');
  R.ModifierI := True;
  try
    for F in ControlFiles(Root) do
    begin
      Text := ReadText(F);
      UnitName := UnitNameOf(F);
      if UnitName = '' then
        Continue;
      if R.Exec(Text) then
        repeat
          if Result = nil then
            Result := TStringList.Create;
          Result.Values[R.Match[2]] := UnitName;
        until not R.ExecNext;
    end;
  finally
    R.Free;
  end;
end;

function HasProjectControls(const Root: string): Boolean;
var
  L: TStringList;
begin
  L := ProjectControls(Root);
  Result := L <> nil;
  L.Free;
end;

function IsDesignerHost: Boolean;
begin
  Result := GetEnvironmentVariable(HostEnv) = '1';
end;

function HostPath(const Root: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Root) + 'build' + PathDelim + 'designer' + PathDelim + 'pastel-designer'
  {$IFDEF WINDOWS} + '.exe'{$ENDIF};
end;

function NewestSource(const Root: string): LongInt;
var
  F: string;
  Project: TPastelProject;
  Dir: string;
begin
  Result := FileAge(ParamStr(0));
  for F in ControlFiles(Root) do
    Result := Max(Result, FileAge(F));
  { the units the controls use may live anywhere in src/ }
  Project := TPastelProject.Load(Root);
  try
    for Dir in ProjectUnitDirs(Project) do
      for F in ListFiles(Dir, '*.pas', False) do
        Result := Max(Result, FileAge(F));
  finally
    Project.Free;
  end;
end;

function EnsureDesignerHost(const Root: string; out Err: string): string;
var
  Controls: TStringList;
  Fpc, Framework, CliDir, OutDir, Units, Output: string;
  Args: TStringList;
  Project: TPastelProject;
  Dir: string;
  I: Integer;
begin
  Err := '';
  Result := HostPath(Root);
  if FileExists(Result) and (FileAge(Result) >= NewestSource(Root)) then
    Exit;
  Framework := FrameworkDir;
  CliDir := ExpandFileName(IncludeTrailingPathDelimiter(Framework) + '..' + PathDelim + '..' + PathDelim + 'cli');
  if (Framework = '') or not FileExists(CliDir + PathDelim + 'pastel.pas') then
  begin
    Err := 'the sources of the pastel tool (cli/) were not found next to the framework; ' +
      'the project''s own controls cannot be shown';
    Exit('');
  end;
  Fpc := FindFpc;
  if Fpc = '' then
  begin
    Err := 'the Free Pascal compiler (fpc) was not found';
    Exit('');
  end;
  Controls := ProjectControls(Root);
  Args := TStringList.Create;
  Project := TPastelProject.Load(Root);
  try
    Units := 'Pastel.Startup';
    if Controls <> nil then
      for I := 0 to Controls.Count - 1 do
        if Pos(',' + Controls.ValueFromIndex[I] + ',', ',' + Units + ',') = 0 then
          Units := Units + ',' + Controls.ValueFromIndex[I];
    OutDir := ExtractFileDir(Result);
    ForceDirectories(OutDir + PathDelim + 'units');
    Args.Add('-Mobjfpc');
    Args.Add('-Sh');
    Args.Add('-vew');
    Args.Add('-Fa' + Units);
    Args.Add('-FU' + OutDir + PathDelim + 'units');
    Args.Add('-Fu' + CliDir + PathDelim + 'src');
    Args.Add('-Fu' + Framework);
    for Dir in ProjectUnitDirs(Project) do
      Args.Add('-Fu' + Dir);
    Args.Add('-o' + Result);
    Args.Add(CliDir + PathDelim + 'pastel.pas');
    { stderr: stdout may be JSON for an editor }
    WriteLn(StdErr, 'Building the designer with the project''s controls (build/designer/)');
    if RunCapture(Fpc, Args, Root, Output) <> 0 then
    begin
      Err := 'the project''s controls do not compile:' + LineEnding + Trim(Output);
      Result := '';
    end;
  finally
    Project.Free;
    Args.Free;
    Controls.Free;
  end;
end;

function RunInDesignerHost(const Root: string; out ExitCode: Integer): Boolean;
var
  R, Host, Err: string;
  P: TProcess;
  I: Integer;
begin
  Result := False;
  ExitCode := 0;
  if IsDesignerHost then
    Exit;
  R := Root;
  if R = '' then
    R := TPastelProject.FindRoot(GetCurrentDir);
  if (R = '') or not HasProjectControls(R) then
    Exit;
  Host := EnsureDesignerHost(R, Err);
  if Host = '' then
  begin
    WriteLn(StdErr, 'warning: ', Err);
    Exit;    { the built-in controls still work }
  end;
  P := TProcess.Create(nil);
  try
    P.Executable := Host;
    for I := 1 to ParamCount do
      P.Parameters.Add(ParamStr(I));
    for I := 0 to GetEnvironmentVariableCount - 1 do
      P.Environment.Add(GetEnvironmentString(I));
    P.Environment.Add(HostEnv + '=1');
    P.Environment.Add('PASTEL_HOME=' + ExtractFileDir(ExtractFileDir(FrameworkDir)));
    { stdin, stdout and stderr are this program's }
    P.Options := [poWaitOnExit];
    P.Execute;
    ExitCode := P.ExitStatus;
    Result := True;
  finally
    P.Free;
  end;
end;

end.
