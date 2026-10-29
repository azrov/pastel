{ Pastel - loading and validating pastel.toml.
  Part of the Pastel project, MIT License. }
unit Pastel.Project;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  PastelVersion = '0.1.0-dev';
  ProjectFileName = 'pastel.toml';

type
  EProjectError = class(Exception);

  TDependency = record
    Name: string;
    Path: string;      { as written in pastel.toml }
    Root: string;      { absolute, with trailing path delimiter }
  end;

  TPastelProject = class
  public
    Root: string;               { project folder, with trailing path delimiter }
    Name: string;
    Version: string;
    Kind: string;               { console, app, server, lib }
    MainFile: string;           { relative to Root }
    Mode: string;               { objfpc or delphi }
    Defines: TStringArray;
    UnitPaths: TStringArray;    { extra unit folders, relative to Root }
    Platforms: TStringArray;    { targets built by "pastel build --all" }
    Dependencies: array of TDependency;   // [dependencies] name = { path = "../x" }
    FormatIndent: Integer;      { [format] indent }
    FormatKeywords: string;     { [format] keywords: lower or keep }
    { [profile.debug], [profile.release], [profile.test]: defines and
      compiler options for one kind of build }
    ProfileDefines: array[0..2] of TStringArray;
    ProfileOptions: array[0..2] of TStringArray;
    { [package] include, and per platform [package.windows] include }
    PackageInclude: TStringArray;
    PackageTargetInclude: array of record Target: string; Files: TStringArray; end;
    function PackageFilesFor(const Target: string): TStringArray;
    class function FindRoot(const StartDir: string): string;
    class function Load(const Dir: string): TPastelProject;
  end;

function IsValidProjectName(const S: string): Boolean;

const
  ProfileNames: array[0..2] of string = ('debug', 'release', 'test');

{ 0, 1, 2 for debug, release, test; -1 for other names }
function ProfileIndex(const Name: string): Integer;

implementation

uses
  Pastel.Toml;

function ProfileIndex(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ProfileNames) do
    if ProfileNames[I] = Name then
      Exit(I);
  Result := -1;
end;

function TPastelProject.PackageFilesFor(const Target: string): TStringArray;
var
  I: Integer;
  F: string;
begin
  Result := Copy(PackageInclude);
  for I := 0 to High(PackageTargetInclude) do
    if PackageTargetInclude[I].Target = Target then
      for F in PackageTargetInclude[I].Files do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := F;
      end;
end;

function IsValidProjectName(const S: string): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and (S[1] in ['A'..'Z', 'a'..'z']);
  if Result then
    for I := 2 to Length(S) do
      if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
        Exit(False);
end;

class function TPastelProject.FindRoot(const StartDir: string): string;
var
  Dir, Parent: string;
begin
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(StartDir));
  repeat
    if FileExists(IncludeTrailingPathDelimiter(Dir) + ProjectFileName) then
      Exit(IncludeTrailingPathDelimiter(Dir));
    Parent := ExtractFileDir(Dir);
    if (Parent = Dir) or (Parent = '') then
      Break;
    Dir := Parent;
  until False;
  Result := '';
end;

class function TPastelProject.Load(const Dir: string): TPastelProject;
var
  Doc: TTomlDocument;
  P: TPastelProject;
  Dep, Opt: string;
  D: TDependency;
  I: Integer;
begin
  P := TPastelProject.Create;
  Doc := TTomlDocument.Create;
  try
    try
      P.Root := IncludeTrailingPathDelimiter(Dir);
      Doc.LoadFromFile(P.Root + ProjectFileName);
      P.Name := Doc.GetString('project.name');
      P.Version := Doc.GetString('project.version', '0.1.0');
      P.Kind := LowerCase(Doc.GetString('project.type', 'console'));
      P.MainFile := SetDirSeparators(Doc.GetString('build.main', 'src/main.pas'));
      P.Mode := LowerCase(Doc.GetString('build.mode', 'objfpc'));
      P.Defines := Doc.GetArray('build.defines');
      P.UnitPaths := Doc.GetArray('build.unit_paths');
      P.Platforms := Doc.GetArray('targets.platforms');
      P.FormatIndent := Doc.GetInt('format.indent', 2);
      P.FormatKeywords := LowerCase(Doc.GetString('format.keywords', 'lower'));
      for Dep in Doc.Keys('profile') do
      begin
        I := ProfileIndex(Dep);
        if I < 0 then
          raise EProjectError.CreateFmt('%s: unknown profile [profile.%s] (debug, release or test)',
            [ProjectFileName, Dep]);
        P.ProfileDefines[I] := Doc.GetArray('profile.' + Dep + '.defines');
        P.ProfileOptions[I] := Doc.GetArray('profile.' + Dep + '.options');
        for Opt in P.ProfileOptions[I] do
          if (Opt = '') or (Opt[1] <> '-') then
            raise EProjectError.CreateFmt('%s: [profile.%s] options are compiler options like "-O3", not "%s"',
              [ProjectFileName, Dep, Opt]);
      end;
      P.PackageInclude := Doc.GetArray('package.include');
      for Dep in Doc.Keys('package') do
        if Dep <> 'include' then
        begin
          SetLength(P.PackageTargetInclude, Length(P.PackageTargetInclude) + 1);
          P.PackageTargetInclude[High(P.PackageTargetInclude)].Target := Dep;
          P.PackageTargetInclude[High(P.PackageTargetInclude)].Files :=
            Doc.GetArray('package.' + Dep + '.include');
        end;
      for Dep in Doc.Keys('dependencies') do
      begin
        D.Name := Dep;
        if Doc.Has('dependencies.' + Dep + '.path') then
          D.Path := Doc.GetString('dependencies.' + Dep + '.path')
        else if Doc.Find('dependencies.' + Dep) <> nil then
          D.Path := Doc.GetString('dependencies.' + Dep)
        else
          raise EProjectError.CreateFmt('%s: dependency "%s" needs a path, e.g. %s = { path = "../%s" }',
            [ProjectFileName, Dep, Dep, Dep]);
        D.Root := IncludeTrailingPathDelimiter(ExpandFileName(P.Root + SetDirSeparators(D.Path)));
        SetLength(P.Dependencies, Length(P.Dependencies) + 1);
        P.Dependencies[High(P.Dependencies)] := D;
      end;
    except
      on E: ETomlError do
        raise EProjectError.Create(ProjectFileName + ': ' + E.Message);
    end;

    if P.Name = '' then
      raise EProjectError.Create(ProjectFileName + ': [project] needs a name, e.g. name = "myapp"');
    if not IsValidProjectName(P.Name) then
      raise EProjectError.CreateFmt('%s: invalid project name "%s" (use letters, digits, "-" and "_")',
        [ProjectFileName, P.Name]);
    if (P.Kind <> 'console') and (P.Kind <> 'app') and (P.Kind <> 'server') and (P.Kind <> 'lib') then
      raise EProjectError.CreateFmt('%s: unknown project type "%s" (console, app, server or lib)',
        [ProjectFileName, P.Kind]);
    if (P.FormatIndent < 1) or (P.FormatIndent > 8) then
      raise EProjectError.CreateFmt('%s: [format] indent must be between 1 and 8', [ProjectFileName]);
    if (P.FormatKeywords <> 'lower') and (P.FormatKeywords <> 'keep') then
      raise EProjectError.CreateFmt('%s: [format] keywords must be "lower" or "keep"', [ProjectFileName]);
    for D in P.Dependencies do
      if not FileExists(D.Root + ProjectFileName) then
        raise EProjectError.CreateFmt('%s: dependency "%s": no %s in "%s"',
          [ProjectFileName, D.Name, ProjectFileName, D.Path]);
    if (P.Mode <> 'objfpc') and (P.Mode <> 'delphi') then
      raise EProjectError.CreateFmt('%s: unknown mode "%s" (objfpc or delphi)',
        [ProjectFileName, P.Mode]);
    if P.Kind = 'lib' then
      P.MainFile := SetDirSeparators(Doc.GetString('build.main', ''))
    else if not FileExists(P.Root + P.MainFile) then
      raise EProjectError.CreateFmt('main file "%s" not found (set [build] main in %s)',
        [P.MainFile, ProjectFileName]);
    Result := P;
  except
    P.Free;
    Doc.Free;
    raise;
  end;
  Doc.Free;
end;

end.
