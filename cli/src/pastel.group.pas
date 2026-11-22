{ Pastel - a group of projects (like Delphi's project group): a pastel.toml
  with [group] in the folder that holds them.

    [group]
    projects = ["salon-core", "salon-api", "salon-desk", "salon-phone"]
    run = "salon-desk"

  In that folder "pastel build", "test", "clean" and "check" go through the
  projects in that order; "pastel run" runs the group's run project (or the
  one named: pastel run salon-phone). "pastel new group" writes the file.
  Part of the Pastel project, MIT License. }
unit Pastel.Group;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TProjectGroup = record
    Root: string;               { with a path delimiter }
    Projects: TStringArray;     { folders, relative to Root, in order }
    Run: string;                { the project "pastel run" and F9 run; '' when not set }
  end;

{ True when Dir's pastel.toml is a group's ([group], no [project]). }
function IsGroupRoot(const Dir: string): Boolean;
{ The group of Dir; EGroupError when the file is wrong. }
function LoadGroup(const Dir: string): TProjectGroup;
{ "pastel build/test/clean/check" for every project of the group, with the
  same arguments (Args: the command line after the command). }
function RunGroupCommand(const G: TProjectGroup; const Command: string; const Args: TStringArray): Integer;
{ "pastel run [project] ...": the project named first in Args, else the group's run one. }
function RunGroupRun(const G: TProjectGroup; const Args: TStringArray): Integer;
{ "pastel new group": the projects of the folders below Dir, libraries before
  those that use them, into Dir's pastel.toml. '' or what went wrong. }
function CreateGroupFile(const Dir: string; out Written: TStringArray): string;

type
  EGroupError = class(Exception);

implementation

uses
  Process, Pastel.Toml, Pastel.Console, Pastel.Project;

function IsGroupRoot(const Dir: string): Boolean;
var
  Doc: TTomlDocument;
  F: string;
begin
  Result := False;
  F := IncludeTrailingPathDelimiter(Dir) + ProjectFileName;
  if not FileExists(F) then
    Exit;
  Doc := TTomlDocument.Create;
  try
    try
      Doc.LoadFromFile(F);
      Result := Doc.Has('group.projects') and not Doc.Has('project.name');
    except
      Result := False;
    end;
  finally
    Doc.Free;
  end;
end;

function LoadGroup(const Dir: string): TProjectGroup;
var
  Doc: TTomlDocument;
  P: string;
  Found: Boolean;
begin
  Result := Default(TProjectGroup);
  Result.Root := IncludeTrailingPathDelimiter(ExpandFileName(Dir));
  Doc := TTomlDocument.Create;
  try
    Doc.LoadFromFile(Result.Root + ProjectFileName);
    Result.Projects := Doc.GetArray('group.projects');
    Result.Run := Doc.GetString('group.run', '');
  finally
    Doc.Free;
  end;
  if Length(Result.Projects) = 0 then
    raise EGroupError.Create(ProjectFileName + ': [group] projects lists no project');
  for P in Result.Projects do
    if not FileExists(Result.Root + SetDirSeparators(P) + PathDelim + ProjectFileName) then
      raise EGroupError.CreateFmt('%s: the group''s project "%s" has no %s', [ProjectFileName, P, ProjectFileName]);
  if Result.Run <> '' then
  begin
    Found := False;
    for P in Result.Projects do
      if SameText(P, Result.Run) then
        Found := True;
    if not Found then
      raise EGroupError.CreateFmt('%s: [group] run = "%s" is not one of its projects', [ProjectFileName, Result.Run]);
  end;
end;

{ pastel itself, in Dir, its output shown as it comes }
function RunPastelIn(const Dir: string; const Args: TStringArray): Integer;
var
  P: TProcess;
  A: string;
  I: Integer;
begin
  Flush(Output);
  P := TProcess.Create(nil);
  try
    P.Executable := ParamStr(0);
    for A in Args do
      P.Parameters.Add(A);
    P.CurrentDirectory := Dir;
    for I := 0 to GetEnvironmentVariableCount - 1 do
      P.Environment.Add(GetEnvironmentString(I));
    P.Environment.Add('PASTEL_GROUP=1');
    P.Options := [poWaitOnExit];
    P.InheritHandles := True;
    P.Execute;
    Result := P.ExitStatus;
  finally
    P.Free;
  end;
end;

function KindOf(const Dir: string): string;
var
  Doc: TTomlDocument;
begin
  Doc := TTomlDocument.Create;
  try
    try
      Doc.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + ProjectFileName);
      Result := LowerCase(Doc.GetString('project.type', 'console'));
    except
      Result := '';
    end;
  finally
    Doc.Free;
  end;
end;

function RunGroupCommand(const G: TProjectGroup; const Command: string; const Args: TStringArray): Integer;
var
  P: string;
  Failed: TStringArray;
  T0: QWord;
begin
  Failed := nil;
  T0 := GetTickCount64;
  for P in G.Projects do
  begin
    WriteLn(Bold('== ' + P));
    if RunPastelIn(G.Root + SetDirSeparators(P), Concat([Command], Args)) <> 0 then
      Failed := Concat(Failed, [P]);
    WriteLn;
  end;
  if Length(Failed) > 0 then
  begin
    Fail(Format('%s failed in %d of %d project(s): %s', [Command, Length(Failed), Length(G.Projects),
      string.Join(', ', Failed)]));
    Exit(1);
  end;
  Status('Done', Format('%s: all %d project(s) of the group (%.1fs)', [Command, Length(G.Projects),
    (GetTickCount64 - T0) / 1000]));
  Result := 0;
end;

function RunGroupRun(const G: TProjectGroup; const Args: TStringArray): Integer;
var
  Name, P: string;
  Rest: TStringArray;
  Programs: TStringArray;
begin
  Name := '';
  Rest := Args;
  if (Length(Args) > 0) and (Copy(Args[0], 1, 1) <> '-') then
    for P in G.Projects do
      if SameText(P, Args[0]) or SameText(ExtractFileName(ExcludeTrailingPathDelimiter(SetDirSeparators(P))), Args[0]) then
      begin
        Name := P;
        Rest := Copy(Args, 1, MaxInt);
      end;
  if (Name = '') and (Length(Args) > 0) and (Copy(Args[0], 1, 1) <> '-') then
  begin
    Fail(Format('the group has no project "%s": %s', [Args[0], string.Join(', ', G.Projects)]));
    Hint('arguments for the program go after --: pastel run -- ' + Args[0]);
    Exit(2);
  end;
  if Name = '' then
    Name := G.Run;
  if Name = '' then
  begin
    { one program in the group: that one }
    Programs := nil;
    for P in G.Projects do
      if KindOf(G.Root + SetDirSeparators(P)) <> 'lib' then
        Programs := Concat(Programs, [P]);
    if Length(Programs) = 1 then
      Name := Programs[0]
    else
    begin
      Fail('which project of the group should run? ' + string.Join(', ', Programs));
      Hint(Format('pastel run %s, or [group] run = "%s" in %s', [Programs[0], Programs[0], ProjectFileName]));
      Exit(2);
    end;
  end;
  if KindOf(G.Root + SetDirSeparators(Name)) = 'lib' then
  begin
    Fail(Name + ' is a library: it does not run by itself');
    Exit(2);
  end;
  Result := RunPastelIn(G.Root + SetDirSeparators(Name), Concat(['run'], Rest));
end;

{ the folders a project's path dependencies point at, as full paths }
function PathDependencies(const Dir: string): TStringArray;
var
  L: TStringList;
  Line, V: string;
  I, J: Integer;
begin
  Result := nil;
  L := TStringList.Create;
  try
    L.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + ProjectFileName);
    for Line in L do
    begin
      // name = { path = "../x" } with no git: a project next to this one
      if (Pos('git', Line) > 0) or (Pos('path', Line) = 0) or (Trim(Line) = '') or (Trim(Line)[1] = '#') then
        Continue;
      I := Pos('path', Line);
      I := Pos('"', Line, I);
      if I = 0 then
        Continue;
      J := Pos('"', Line, I + 1);
      if J = 0 then
        Continue;
      V := Copy(Line, I + 1, J - I - 1);
      Result := Concat(Result, [ExcludeTrailingPathDelimiter(ExpandFileName(IncludeTrailingPathDelimiter(Dir) +
        SetDirSeparators(V)))]);
    end;
  finally
    L.Free;
  end;
end;

function CreateGroupFile(const Dir: string; out Written: TStringArray): string;
var
  Root, D, S: string;
  SR: TSearchRec;
  Names, Ordered: TStringList;
  Deps: array of TStringArray;
  I, J, Before: Integer;
  Ready: Boolean;
  Text: TStringList;
  RunName: string;
begin
  Written := nil;
  Root := IncludeTrailingPathDelimiter(ExpandFileName(Dir));
  if FileExists(Root + ProjectFileName) then
    Exit('there is a ' + ProjectFileName + ' here already');
  Names := TStringList.Create;
  Ordered := TStringList.Create;
  Text := TStringList.Create;
  try
    Names.Sorted := True;
    if FindFirst(Root + '*', faDirectory, SR) = 0 then
    begin
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') and ((SR.Attr and faDirectory) <> 0) and
           FileExists(Root + SR.Name + PathDelim + ProjectFileName) then
          Names.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;
    if Names.Count = 0 then
      Exit('no project in the folders here (folders with a ' + ProjectFileName + ')');
    SetLength(Deps, Names.Count);
    for I := 0 to Names.Count - 1 do
      Deps[I] := PathDependencies(Root + Names[I]);
    { libraries first: a project after those of the group it uses }
    Names.Sorted := False;
    while Ordered.Count < Names.Count do
    begin
      Before := Ordered.Count;
      { a round: those whose projects came in earlier rounds, by name }
      for I := 0 to Names.Count - 1 do
      begin
        if Ordered.IndexOf(Names[I]) >= 0 then
          Continue;
        Ready := True;
        for D in Deps[I] do
          for J := 0 to Names.Count - 1 do
            if (J <> I) and SameFileName(D, ExcludeTrailingPathDelimiter(Root + Names[J])) and
               ((Ordered.IndexOf(Names[J]) < 0) or (Ordered.IndexOf(Names[J]) >= Before)) then
              Ready := False;
        if Ready then
          Ordered.Add(Names[I]);
      end;
      if Ordered.Count = Before then
      begin
        { projects that use each other: as they are }
        for I := 0 to Names.Count - 1 do
          if Ordered.IndexOf(Names[I]) < 0 then
            Ordered.Add(Names[I]);
      end;
    end;
    { F9: the first desktop app, else the first program }
    RunName := '';
    for S in Ordered do
      if (RunName = '') and (KindOf(Root + S) = 'app') then
        RunName := S;
    for S in Ordered do
      if (RunName = '') and (KindOf(Root + S) <> 'lib') then
        RunName := S;
    Text.Add('# A group of projects (like Delphi''s project group). In this folder');
    Text.Add('# "pastel build", "test", "clean" and "check" go through them in this order;');
    Text.Add('# "pastel run" (F9) runs "run", "pastel run <project>" another one.');
    Text.Add('');
    Text.Add('[group]');
    S := '';
    for I := 0 to Ordered.Count - 1 do
    begin
      if I > 0 then
        S := S + ', ';
      S := S + '"' + Ordered[I] + '"';
    end;
    Text.Add('projects = [' + S + ']');
    if RunName <> '' then
      Text.Add('run = "' + RunName + '"');
    Text.SaveToFile(Root + ProjectFileName);
    Written := Ordered.ToStringArray;
    Result := '';
  finally
    Text.Free;
    Ordered.Free;
    Names.Free;
  end;
end;

end.
