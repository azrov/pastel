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

  TPastelProject = class
  public
    Root: string;               { project folder, with trailing path delimiter }
    Name: string;
    Version: string;
    Kind: string;               { console, app, server }
    MainFile: string;           { relative to Root }
    Mode: string;               { objfpc or delphi }
    Defines: TStringArray;
    UnitPaths: TStringArray;    { extra unit folders, relative to Root }
    Platforms: TStringArray;    { targets built by "pastel build --all" }
    class function FindRoot(const StartDir: string): string;
    class function Load(const Dir: string): TPastelProject;
  end;

function IsValidProjectName(const S: string): Boolean;

implementation

uses
  Pastel.Toml;

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
    except
      on E: ETomlError do
        raise EProjectError.Create(ProjectFileName + ': ' + E.Message);
    end;

    if P.Name = '' then
      raise EProjectError.Create(ProjectFileName + ': [project] needs a name, e.g. name = "myapp"');
    if not IsValidProjectName(P.Name) then
      raise EProjectError.CreateFmt('%s: invalid project name "%s" (use letters, digits, "-" and "_")',
        [ProjectFileName, P.Name]);
    if (P.Kind <> 'console') and (P.Kind <> 'app') and (P.Kind <> 'server') then
      raise EProjectError.CreateFmt('%s: unknown project type "%s" (console, app or server)',
        [ProjectFileName, P.Kind]);
    if (P.Mode <> 'objfpc') and (P.Mode <> 'delphi') then
      raise EProjectError.CreateFmt('%s: unknown mode "%s" (objfpc or delphi)',
        [ProjectFileName, P.Mode]);
    if not FileExists(P.Root + P.MainFile) then
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
