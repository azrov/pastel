{ Pastel - "pastel run --watch" and "pastel test --watch": build and run
  again whenever a source file is saved.
  Part of the Pastel project, MIT License. }
unit Pastel.Watch;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ Both run until the user presses Ctrl+C. }
function WatchRun(const Root: string; Release, Verbose: Boolean;
  const ProgramArgs: TStringArray): Integer;
function WatchTests(const Root: string; const Filters: TStringArray;
  Verbose: Boolean): Integer;

implementation

uses
  Classes, Process, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Pastel.Console, Pastel.Project, Pastel.Targets, Pastel.Builder, Pastel.TestCmd;

const
  PollMs = 300;
  SettleMs = 150;   { editors often write a file in several steps }

var
  StopRequested: Boolean = False;

{$IFDEF UNIX}
{ Ctrl+C, a closed terminal or "kill": stop the program we started too,
  instead of leaving it running on its own. }
procedure OnSignal(Sig: cint); cdecl;
begin
  StopRequested := True;
end;

procedure CatchSignals;
begin
  fpSignal(SIGINT, signalhandler(@OnSignal));
  fpSignal(SIGTERM, signalhandler(@OnSignal));
  fpSignal(SIGHUP, signalhandler(@OnSignal));
end;
{$ELSE}
procedure CatchSignals;
begin
end;
{$ENDIF}

{ Every source file with its time and size: "name=time:size", sorted. }
procedure AddFolder(const Dir: string; Recursive, WithForms: Boolean; List: TStrings);
var
  SR: TSearchRec;
  Ext: string;
begin
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + AllFilesMask, faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') or (SR.Name[1] = '.') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        if Recursive and (SR.Name <> 'build') then
          AddFolder(IncludeTrailingPathDelimiter(Dir) + SR.Name, True, WithForms, List);
        Continue;
      end;
      Ext := LowerCase(ExtractFileExt(SR.Name));
      if (Ext = '.pas') or (Ext = '.pp') or (Ext = '.inc') or (Ext = '.lpr') or
         (Ext = '.dpr') or (WithForms and (Ext = '.pform')) then
        List.Add(Format('%s=%d:%d', [IncludeTrailingPathDelimiter(Dir) + SR.Name,
          SR.Time, SR.Size]));
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function Snapshot(const Root: string; WithTests, WithForms: Boolean): TStringList;
var
  Project: TPastelProject;
  D: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Result.Add(Root + ProjectFileName + '=' + IntToStr(FileAge(Root + ProjectFileName)));
  try
    Project := TPastelProject.Load(Root);
    try
      for D in ProjectUnitDirs(Project) do
        AddFolder(D, False, WithForms, Result);
    finally
      Project.Free;
    end;
  except
    on Exception do
      AddFolder(Root + 'src', True, WithForms, Result);   { pastel.toml is broken: watch src/ }
  end;
  if WithTests and DirectoryExists(Root + 'tests') then
    AddFolder(Root + 'tests', True, False, Result);
end;

{ The first file that differs, relative to Root when inside it. }
function FirstChange(Old, New: TStrings; const Root: string; out Count: Integer): string;
var
  I: Integer;
  Name: string;
begin
  Result := '';
  Count := 0;
  for I := 0 to New.Count - 1 do
    if Old.IndexOf(New[I]) < 0 then
    begin
      Inc(Count);
      if Result = '' then
        Result := New.Names[I];
    end;
  for I := 0 to Old.Count - 1 do
  begin
    Name := Old.Names[I];
    if New.IndexOfName(Name) < 0 then
    begin
      Inc(Count);
      if Result = '' then
        Result := Name + ' (deleted)';
    end;
  end;
  if Copy(Result, 1, Length(Root)) = Root then
    Delete(Result, 1, Length(Root));
end;

{ Asks the program to end (SIGTERM, so it can clean up), and stops it if it
  has not after 3 seconds. }
procedure StopChild(Child: TProcess);
{$IFDEF UNIX}
var
  Waited: Integer;
{$ENDIF}
begin
  if (Child = nil) or not Child.Running then
    Exit;
  {$IFDEF UNIX}
  fpKill(Child.ProcessID, SIGTERM);
  Waited := 0;
  while Child.Running and (Waited < 3000) do
  begin
    Sleep(50);
    Inc(Waited, 50);
  end;
  {$ENDIF}
  if Child.Running then
    Child.Terminate(1);
  Child.WaitOnExit;
end;

{ Waits until a file changes, then a moment longer so that a save in
  several steps is seen as one. Child: the running program, reported when
  it ends on its own. }
procedure WaitForChange(const Root: string; WithTests, WithForms: Boolean; Child: TProcess);
var
  Old, New: TStringList;
  What: string;
  Count: Integer;
  Reported: Boolean;
begin
  Reported := Child = nil;
  Old := Snapshot(Root, WithTests, WithForms);
  try
    repeat
      Sleep(PollMs);
      if StopRequested then
      begin
        StopChild(Child);
        WriteLn;
        Halt(130);
      end;
      if not Reported and not Child.Running then
      begin
        Reported := True;
        WriteLn;
        Status('Exited', Format('with code %d; waiting for changes (Ctrl+C to stop)',
          [Child.ExitCode]));
        Flush(Output);
      end;
      New := Snapshot(Root, WithTests, WithForms);
      if New.Text <> Old.Text then
      begin
        Sleep(SettleMs);
        New.Free;
        New := Snapshot(Root, WithTests, WithForms);
        What := FirstChange(Old, New, Root, Count);
        New.Free;
        WriteLn;
        if Count > 1 then
          What := Format('%s and %d more', [What, Count - 1]);
        WriteLn(Dim(StringOfChar('-', 8) + ' ' + FormatDateTime('hh:nn:ss', Now) + ' ' +
          What + ' changed ' + StringOfChar('-', 8)));
        Exit;
      end;
      New.Free;
    until False;
  finally
    Old.Free;
  end;
end;

function WatchRun(const Root: string; Release, Verbose: Boolean;
  const ProgramArgs: TStringArray): Integer;
var
  Project: TPastelProject;
  Opts: TBuildOptions;
  ExePath, A: string;
  Child: TProcess;
  IsApp: Boolean;
begin
  Result := 0;
  Child := nil;
  IsApp := False;
  CatchSignals;
  repeat
    FreeAndNil(Child);
    ExePath := '';
    Project := nil;
    try
      Project := TPastelProject.Load(Root);
    except
      on E: EProjectError do
        Fail(E.Message);
    end;
    if Project <> nil then
    try
      IsApp := Project.Kind = 'app';
      Opts := Default(TBuildOptions);
      Opts.Target := HostTarget;
      Opts.Release := Release;
      Opts.Verbose := Verbose;
      if BuildProject(Project, Opts, ExePath) then
      begin
        Status('Running', ExePath + Dim('  (saving a file builds and runs it again; Ctrl+C stops)'));
        WriteLn;
        Flush(Output);
        Child := TProcess.Create(nil);
        Child.Executable := Project.Root + ExePath;
        for A in ProgramArgs do
          Child.Parameters.Add(A);
        Child.Options := [];
        Child.Execute;
      end
      else
        WriteLn(Dim('             fix the error and save; waiting for changes (Ctrl+C to stop)'));
    finally
      Project.Free;
    end;
    Flush(Output);
    { a running app reloads .pform files itself; only code changes restart it }
    WaitForChange(IncludeTrailingPathDelimiter(Root), False, not IsApp, Child);
    StopChild(Child);
  until False;
end;

function WatchTests(const Root: string; const Filters: TStringArray;
  Verbose: Boolean): Integer;
var
  Project: TPastelProject;
begin
  Result := 0;
  CatchSignals;
  repeat
    Project := nil;
    try
      Project := TPastelProject.Load(Root);
    except
      on E: EProjectError do
        Fail(E.Message);
    end;
    if Project <> nil then
    try
      RunProjectTests(Project, Filters, False, Verbose);
    finally
      Project.Free;
    end;
    WriteLn(Dim('             saving a file runs the tests again (Ctrl+C to stop)'));
    Flush(Output);
    WaitForChange(IncludeTrailingPathDelimiter(Root), True, True, nil);
  until False;
end;

end.
