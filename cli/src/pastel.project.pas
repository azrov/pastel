{ Pastel - loading and validating pastel.toml.
  Part of the Pastel project, MIT License. }
unit Pastel.Project;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  PastelVersion = '1.0.0';
  ProjectFileName = 'pastel.toml';

{ '0.7' for Pastel 0.7.x: what [project] pastel records. }
function PastelMinor: string;
{ 'my-notes_app' -> 'My Notes App': a title people see, from a project name. }
function TitleFromName(const Name: string): string;

type
  EProjectError = class(Exception);

  TDependency = record
    Name: string;
    Path: string;      { as written in pastel.toml; in a git repository: the folder of the package }
    Root: string;      { absolute, with trailing path delimiter; '' while a package is not resolved }
    Remote: Boolean;   { a package: from the registry or a git repository, not a folder }
    Git: string;       { git = "https://..."; '' for the registry }
    Version: string;   { "^1.2", "~1.2.3", "1.2.3", ">=1.0, <2.0", "*" }
    Branch: string;    { branch = "main" instead of a version }
    Rev: string;       { rev = "a1b2c3d" instead of a version }
    Resolved: string;  { the version used: "1.2.3", "main", a commit }
  end;

  TPastelProject = class
  public
    Root: string;               { project folder, with trailing path delimiter }
    Name: string;
    Version: string;
    Kind: string;               { console, app, service, lib }
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
    Description: string;        { [project] description }
    Title: string;              { [project] title: the name people see; Name when not set }
    PastelFor: string;          { [project] pastel: the Pastel version it is made for ('0.7'); '' in old projects }
    UnknownKeys: TStringArray;  { settings in pastel.toml that Pastel does not know (typos) }
    Maintainer: string;         { [package] maintainer = "Name <mail>" }
    DebDepends: TStringArray;   { [package.deb] depends = ["libsqlite3-0"] }
    DockerBase: string;         { [package.docker] base = "debian:bookworm-slim" }
    function PackageFilesFor(const Target: string): TStringArray;
    class function FindRoot(const StartDir: string): string;
    class function Load(const Dir: string): TPastelProject;
  end;

function IsValidProjectName(const S: string): Boolean;
{ "^1.2", "1.0.0", "*", ">=1.0": a version, not a path. }
function IsVersionSpec(const S: string): Boolean;

var
  { Finds a package (a dependency with Remote) and sets its Root; set by
    Pastel.Packages. ProjectRoot is the folder of the project that needs it. }
  ResolvePackage: procedure(const ProjectRoot: string; var D: TDependency) = nil;
  { False: packages are not looked for (their Root stays ''), e.g. when
    projects are only looked at. }
  ResolvePackages: Boolean = True;

const
  ProfileNames: array[0..2] of string = ('debug', 'release', 'test');

{ 0, 1, 2 for debug, release, test; -1 for other names }
function ProfileIndex(const Name: string): Integer;

implementation

uses
  RegExpr, Pastel.Toml;

function IsVersionSpec(const S: string): Boolean;
begin
  Result := (S <> '') and (S[1] in ['0'..'9', '^', '~', '*', '>', '<', '=']);
end;

function TitleFromName(const Name: string): string;
var
  W: string;
begin
  Result := '';
  for W in Name.Split(['-', '_', ' ']) do
    if W <> '' then
      Result := Result + ' ' + UpCase(W[1]) + Copy(W, 2, MaxInt);
  Result := Trim(Result);
end;

function PastelMinor: string;
var
  P: TStringArray;
begin
  P := string(PastelVersion).Split(['.']);
  Result := P[0] + '.' + P[1];
end;

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
      P.Description := Doc.GetString('project.description', '');
      P.Title := Doc.GetString('project.title', P.Name);
      P.PastelFor := Doc.GetString('project.pastel', '');
      for I := 0 to Doc.Values.Count - 1 do
        if not ExecRegExpr('^(project\.(name|version|pastel|title|description|type)|' +
          'build\.(main|mode|defines|unit_paths)|targets\.platforms|' +
          'profile\.(debug|release|test)\.(defines|options)|' +
          'dependencies\.[^.]+(\.(path|git|version|branch|rev))?|' +
          'package\.(include|maintainer|deb\.depends|docker\.base|[a-z0-9-]+\.include)|' +
          'format\.(indent|keywords))$', Doc.Values[I]) then
        begin
          SetLength(P.UnknownKeys, Length(P.UnknownKeys) + 1);
          P.UnknownKeys[High(P.UnknownKeys)] := Doc.Values[I];
        end;
      P.Maintainer := Doc.GetString('package.maintainer', '');
      P.DebDepends := Doc.GetArray('package.deb.depends');
      P.DockerBase := Doc.GetString('package.docker.base', 'debian:bookworm-slim');
      for Dep in Doc.Keys('package') do
        if (Dep <> 'include') and (Dep <> 'maintainer') and (Dep <> 'deb') and (Dep <> 'docker') then
        begin
          SetLength(P.PackageTargetInclude, Length(P.PackageTargetInclude) + 1);
          P.PackageTargetInclude[High(P.PackageTargetInclude)].Target := Dep;
          P.PackageTargetInclude[High(P.PackageTargetInclude)].Files :=
            Doc.GetArray('package.' + Dep + '.include');
        end;
      for Dep in Doc.Keys('dependencies') do
      begin
        D := Default(TDependency);
        D.Name := Dep;
        if Doc.Has('dependencies.' + Dep + '.git') then
        begin
          { a package in a git repository: git = "...", path = "folder in it" }
          D.Remote := True;
          D.Git := Doc.GetString('dependencies.' + Dep + '.git');
          D.Path := Doc.GetString('dependencies.' + Dep + '.path', '');
        end
        else if Doc.Has('dependencies.' + Dep + '.path') then
          D.Path := Doc.GetString('dependencies.' + Dep + '.path')
        else if Doc.Has('dependencies.' + Dep + '.version') then
          D.Remote := True     { from the registry }
        else if Doc.Find('dependencies.' + Dep) <> nil then
        begin
          D.Path := Doc.GetString('dependencies.' + Dep);
          if IsVersionSpec(D.Path) then
          begin
            D.Remote := True;  { serial = "^1.2": from the registry }
            D.Version := D.Path;
            D.Path := '';
          end;
        end
        else
          raise EProjectError.CreateFmt('%s: dependency "%s" needs a version or a path, e.g. %s = "^1.0" or %s = { path = "../%s" }',
            [ProjectFileName, Dep, Dep, Dep, Dep]);
        if D.Remote then
        begin
          D.Version := Doc.GetString('dependencies.' + Dep + '.version', D.Version);
          D.Branch := Doc.GetString('dependencies.' + Dep + '.branch', '');
          D.Rev := Doc.GetString('dependencies.' + Dep + '.rev', '');
          if (D.Version = '') and (D.Branch = '') and (D.Rev = '') then
            D.Version := '*';
          if (D.Git = '') and ((D.Branch <> '') or (D.Rev <> '')) then
            raise EProjectError.CreateFmt('%s: dependency "%s": branch and rev need a git repository (git = "https://...")',
              [ProjectFileName, Dep]);
          if ResolvePackages and Assigned(ResolvePackage) then
            ResolvePackage(P.Root, D);
        end
        { relative to the project, or a full path }
        else if (D.Path <> '') and ((D.Path[1] in ['/', '\']) or ((Length(D.Path) > 1) and (D.Path[2] = ':'))) then
          D.Root := IncludeTrailingPathDelimiter(ExpandFileName(SetDirSeparators(D.Path)))
        else
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
    if (P.Kind <> 'console') and (P.Kind <> 'app') and (P.Kind <> 'server') and (P.Kind <> 'lib') and
       (P.Kind <> 'service') then
      raise EProjectError.CreateFmt('%s: unknown project type "%s" (console, app, service or lib)',
        [ProjectFileName, P.Kind]);
    if (P.FormatIndent < 1) or (P.FormatIndent > 8) then
      raise EProjectError.CreateFmt('%s: [format] indent must be between 1 and 8', [ProjectFileName]);
    if (P.FormatKeywords <> 'lower') and (P.FormatKeywords <> 'keep') then
      raise EProjectError.CreateFmt('%s: [format] keywords must be "lower" or "keep"', [ProjectFileName]);
    for D in P.Dependencies do
      if D.Remote and (D.Root <> '') and not FileExists(D.Root + ProjectFileName) then
        raise EProjectError.CreateFmt('%s: package "%s": no %s in %s%s',
          [ProjectFileName, D.Name, ProjectFileName, D.Git, BoolToStr(D.Path <> '', ' (' + D.Path + ')', '')])
      else if not D.Remote and not FileExists(D.Root + ProjectFileName) then
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
