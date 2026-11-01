(* Pastel - packages: dependencies from the registry or from git repositories.

    [dependencies]
    serial = "^1.2"                                             the registry
    chart = { git = "https://github.com/someone/pastel-chart", version = "^0.3" }
    gpio = { git = "https://github.com/azrov/pastel-extras", path = "gpio", branch = "main" }

  The registry is a git repository with a packages.toml (name -> git, path,
  description); PASTEL_REGISTRY points to another one (a URL or a folder).
  Versions are the repository's tags (v1.2.3). pastel.lock, next to
  pastel.toml, records the exact commit of every package, so every computer
  builds the same code; "pastel update" moves them to the newest allowed.

  Repositories and the code of every version are kept once for all projects
  in the cache (PASTEL_CACHE, or ~/.cache/pastel; on Windows
  %LOCALAPPDATA%\pastel\cache). Building needs no network when they are there.
  Part of the Pastel project, MIT License. *)
unit Pastel.Packages;

{$mode objfpc}{$H+}
{$modeswitch nestedprocvars}

interface

uses
  Classes, SysUtils, Pastel.Project;

type
  EPackageError = class(Exception);

  TVersion = record
    Major, Minor, Patch: Integer;
    Pre: string;         { 'rc.1' in 1.0.0-rc.1 }
    Valid: Boolean;
  end;

  TRegistryEntry = record
    Name, Git, Path, Description: string;
  end;
  TRegistryEntries = array of TRegistryEntry;

{ '1.2.3', 'v1.2', '1.0.0-rc.1' }
function ParseVersion(const S: string): TVersion;
function VersionText(const V: TVersion): string;
{ <0, 0, >0 }
function CompareVersions(const A, B: TVersion): Integer;
{ Whether V is allowed by '^1.2', '~1.2', '1.2.3', '>=1.0, <2.0', '*';
  EPackageError for a constraint that cannot be read. }
function VersionMatches(const V: TVersion; const Constraint: string): Boolean;

{ The folder of the cache. }
function PackageCacheDir: string;
{ The registry's packages; Refresh fetches it again. }
function RegistryEntries(Refresh: Boolean): TRegistryEntries;

{ pastel add <name>[@version] [--git URL] [--path P] [--branch B] }
function RunAdd(const Args: TStringArray; const Git, SubPath, Branch: string): Integer;
{ pastel remove <name> }
function RunRemove(const Args: TStringArray): Integer;
{ pastel update [names]: newest allowed versions; all packages without names }
function RunUpdate(const Args: TStringArray): Integer;
{ pastel search [words] }
function RunSearch(const Args: TStringArray): Integer;
{ pastel deps [--json]: every dependency, also those of dependencies }
function RunDeps(Json: Boolean): Integer;

implementation

uses
  Math, Pastel.Console, Pastel.Toml, Pastel.Process, Pastel.Files, Pastel.Inspect;

const
  LockFileName = 'pastel.lock';
  DefaultRegistry = 'https://github.com/azrov/pastel-packages';

type
  TLockEntry = record
    Name, Git, Path, Version, Commit: string;
  end;

var
  Lock: array of TLockEntry;
  LockLoaded: Boolean = False;
  LockPath: string = '';
  { names resolved in this run: a second dependency on them must agree }
  Resolved: TStringList = nil;
  { 'all' or the names "pastel update" asks for }
  Updating: TStringList = nil;
  Fetched: TStringList = nil;
  RegistryFetched: Boolean = False;
  Quiet: Boolean = False;

{ ---- versions ---- }

function ParseVersion(const S: string): TVersion;
var
  T: string;
  Parts: TStringArray;
  P: Integer;
begin
  Result := Default(TVersion);
  T := Trim(S);
  if (T <> '') and (T[1] in ['v', 'V']) then
    Delete(T, 1, 1);
  P := Pos('-', T);
  if P > 0 then
  begin
    Result.Pre := Copy(T, P + 1, MaxInt);
    T := Copy(T, 1, P - 1);
  end;
  P := Pos('+', T);     { build metadata does not count }
  if P > 0 then
    T := Copy(T, 1, P - 1);
  Parts := T.Split(['.']);
  if (Length(Parts) < 1) or (Length(Parts) > 3) then
    Exit;
  if not TryStrToInt(Parts[0], Result.Major) then
    Exit;
  if (Length(Parts) > 1) and not TryStrToInt(Parts[1], Result.Minor) then
    Exit;
  if (Length(Parts) > 2) and not TryStrToInt(Parts[2], Result.Patch) then
    Exit;
  Result.Valid := (Result.Major >= 0) and (Result.Minor >= 0) and (Result.Patch >= 0);
end;

function VersionText(const V: TVersion): string;
begin
  Result := Format('%d.%d.%d', [V.Major, V.Minor, V.Patch]);
  if V.Pre <> '' then
    Result := Result + '-' + V.Pre;
end;

function ComparePre(const A, B: string): Integer;
var
  PA, PB: TStringArray;
  I, NA, NB: Integer;
begin
  { no pre-release is newer than any pre-release: 1.0.0 > 1.0.0-rc.1 }
  if A = B then Exit(0);
  if A = '' then Exit(1);
  if B = '' then Exit(-1);
  PA := A.Split(['.']);
  PB := B.Split(['.']);
  for I := 0 to Min(High(PA), High(PB)) do
  begin
    if TryStrToInt(PA[I], NA) and TryStrToInt(PB[I], NB) then
      Result := NA - NB
    else
      Result := CompareStr(PA[I], PB[I]);
    if Result <> 0 then
      Exit;
  end;
  Result := Length(PA) - Length(PB);
end;

function CompareVersions(const A, B: TVersion): Integer;
begin
  Result := A.Major - B.Major;
  if Result = 0 then Result := A.Minor - B.Minor;
  if Result = 0 then Result := A.Patch - B.Patch;
  if Result = 0 then Result := ComparePre(A.Pre, B.Pre);
end;

function Ver(Major, Minor, Patch: Integer): TVersion;
begin
  Result := Default(TVersion);
  Result.Major := Major;
  Result.Minor := Minor;
  Result.Patch := Patch;
  Result.Valid := True;
end;

{ one comparison: '^1.2', '>=1.0', '1.2.3' }
function MatchesOne(const V: TVersion; C: string): Boolean;
var
  Op: string;
  W: TVersion;
  Parts: Integer;
  Lo, Hi: TVersion;
begin
  C := Trim(C);
  if (C = '') or (C = '*') then
    Exit(True);
  Op := '';
  while (C <> '') and (C[1] in ['^', '~', '>', '<', '=']) do
  begin
    Op := Op + C[1];
    Delete(C, 1, 1);
  end;
  C := Trim(C);
  W := ParseVersion(C);
  if not W.Valid then
    raise EPackageError.CreateFmt('"%s" is not a version (for example ^1.2, ~1.2.3, 1.2.3, >=1.0)', [Op + C]);
  Parts := Length(C.Split(['.']));
  case Op of
    '^':
      begin
        { the left-most number that is not 0 stays: ^1.2 -> <2.0.0, ^0.3 -> <0.4.0 }
        Lo := W;
        if W.Major > 0 then Hi := Ver(W.Major + 1, 0, 0)
        else if (W.Minor > 0) or (Parts < 3) then Hi := Ver(0, W.Minor + 1, 0)
        else Hi := Ver(0, 0, W.Patch + 1);
        if Parts = 1 then Hi := Ver(W.Major + 1, 0, 0);
        Result := (CompareVersions(V, Lo) >= 0) and (CompareVersions(V, Hi) < 0);
      end;
    '~':
      begin
        { ~1.2.3 and ~1.2 -> <1.3.0; ~1 -> <2.0.0 }
        Lo := W;
        if Parts = 1 then Hi := Ver(W.Major + 1, 0, 0) else Hi := Ver(W.Major, W.Minor + 1, 0);
        Result := (CompareVersions(V, Lo) >= 0) and (CompareVersions(V, Hi) < 0);
      end;
    '>=': Result := CompareVersions(V, W) >= 0;
    '>': Result := CompareVersions(V, W) > 0;
    '<=': Result := CompareVersions(V, W) <= 0;
    '<': Result := CompareVersions(V, W) < 0;
    '', '=':
      if Parts = 3 then
        Result := CompareVersions(V, W) = 0
      else    { 1.2 = any 1.2.x }
        Result := (V.Major = W.Major) and ((Parts = 1) or (V.Minor = W.Minor)) and (V.Pre = '');
  else
    raise EPackageError.CreateFmt('"%s" is not a version comparison (^, ~, >=, >, <=, <, =)', [Op]);
  end;
end;

function VersionMatches(const V: TVersion; const Constraint: string): Boolean;
var
  C: string;
begin
  if not V.Valid then
    Exit(False);
  { pre-releases only when asked for: ^1.0.0-rc.1 }
  if (V.Pre <> '') and (Pos('-', Constraint) = 0) then
    Exit(False);
  Result := True;
  for C in Constraint.Split([',']) do
    if not MatchesOne(V, C) then
      Result := False;   { go on: a bad constraint should be reported }
end;

{ ---- git ---- }

function GitExe: string;
begin
  Result := Which('git');
  if Result = '' then
    raise EPackageError.Create('packages are fetched with git, which is not installed' + LineEnding +
      '  Linux: sudo apt install git     Windows: https://git-scm.com/download/win');
end;

function Git(const Args: array of string; const Dir: string = ''): string;
var
  O: TRunOptions;
  R: TRunResult;
begin
  O := Default(TRunOptions);
  O.Dir := Dir;
  SetLength(O.Env, 2);
  O.Env[0] := 'GIT_TERMINAL_PROMPT=0';     { no password questions: fail instead }
  O.Env[1] := 'LC_ALL=C';
  R := Run(GitExe, Args, O);
  if not R.Ok then
    raise EPackageError.CreateFmt('git %s: %s', [string.Join(' ', Args), Trim(R.Errors + R.Output)]);
  Result := R.Text;
end;

function GitOk(const Args: array of string; const Dir: string = ''): Boolean;
var
  O: TRunOptions;
begin
  O := Default(TRunOptions);
  O.Dir := Dir;
  Result := Run(GitExe, Args, O).Ok;
end;

function PackageCacheDir: string;
begin
  Result := GetEnvironmentVariable('PASTEL_CACHE');
  if Result = '' then
  begin
    {$IFDEF WINDOWS}
    Result := GetEnvironmentVariable('LOCALAPPDATA');
    if Result <> '' then
      Result := JoinPath([Result, 'pastel', 'cache']);
    {$ELSE}
    Result := GetEnvironmentVariable('XDG_CACHE_HOME');
    if Result <> '' then
      Result := JoinPath([Result, 'pastel']);
    {$ENDIF}
    if Result = '' then
      Result := JoinPath([HomeDir, '.cache', 'pastel']);
  end;
  Result := IncludeTrailingPathDelimiter(ExpandFileName(Result));
end;

{ a folder name for a URL: readable, and different for different URLs }
function SafeName(const S: string): string;
var
  I: Integer;
  H: Cardinal;
  T: string;
begin
  H := 2166136261;
  for I := 1 to Length(S) do
    H := (H xor Ord(S[I])) * 16777619;
  T := S;
  I := Pos('://', T);
  if I > 0 then
    Delete(T, 1, I + 2);
  Result := '';
  for I := 1 to Length(T) do
    if T[I] in ['a'..'z', 'A'..'Z', '0'..'9', '-', '.'] then
      Result := Result + T[I]
    else
      Result := Result + '_';
  Result := Copy(Result, Length(Result) - 59, 60) + '-' + IntToHex(H, 8);
end;

{ the local copy of a repository (a mirror), fetched at most once per run when Fetch }
function Mirror(const Url: string; Fetch: Boolean): string;
var
  Tmp: string;
begin
  Result := PackageCacheDir + 'git' + PathDelim + SafeName(Url);
  if not DirectoryExists(Result) then
  begin
    if not Quiet then
      Status('Fetching', Url);
    EnsureDir(ExtractFileDir(Result));
    Tmp := Result + '.tmp';
    if DirectoryExists(Tmp) then
      DeleteDir(Tmp);
    Git(['clone', '--mirror', '--quiet', Url, Tmp]);
    if not RenameFile(Tmp, Result) then
      raise EPackageError.CreateFmt('cannot rename %s', [Tmp]);
    Fetched.Add(Url);
  end
  else if Fetch and (Fetched.IndexOf(Url) < 0) then
  begin
    if not Quiet then
      Status('Updating', Url);
    Git(['fetch', '--quiet', '--prune', '--tags', '--force'], Result);
    Fetched.Add(Url);
  end;
end;

function TagVersions(const MirrorDir: string; out Tags: TStringArray): Integer;
var
  Line: string;
begin
  Tags := nil;
  for Line in Git(['tag', '--list'], MirrorDir).Split([#10]) do
    if ParseVersion(Trim(Line)).Valid then
    begin
      SetLength(Tags, Length(Tags) + 1);
      Tags[High(Tags)] := Trim(Line);
    end;
  Result := Length(Tags);
end;

{ the code of one commit, checked out once into the cache }
function Checkout(const D: TDependency; const Commit: string): string;
var
  M, Tmp: string;
begin
  Result := PackageCacheDir + 'src' + PathDelim + SafeName(D.Git) + PathDelim + Copy(Commit, 1, 12) + PathDelim;
  if DirectoryExists(Result) then
    Exit;
  M := Mirror(D.Git, False);
  if not GitOk(['cat-file', '-e', Commit + '^{commit}'], M) then
    M := Mirror(D.Git, True);
  Tmp := ExcludeTrailingPathDelimiter(Result) + '.tmp';
  if DirectoryExists(Tmp) then
    DeleteDir(Tmp);
  EnsureDir(ExtractFileDir(Tmp));
  Git(['clone', '--quiet', '--no-checkout', M, Tmp]);
  Git(['checkout', '--quiet', Commit], Tmp);
  DeleteDir(JoinPath([Tmp, '.git']));     { only the code }
  if not RenameFile(Tmp, ExcludeTrailingPathDelimiter(Result)) then
    raise EPackageError.CreateFmt('cannot rename %s', [Tmp]);
end;

{ ---- the registry ---- }

function RegistryDir(Refresh: Boolean): string;
var
  Src: string;
begin
  Src := GetEnvironmentVariable('PASTEL_REGISTRY');
  if Src = '' then
    Src := DefaultRegistry;
  { a folder with packages.toml: used as it is }
  if DirectoryExists(Src) and FileExists(JoinPath([Src, 'packages.toml'])) then
    Exit(IncludeTrailingPathDelimiter(ExpandFileName(Src)));
  Result := PackageCacheDir + 'registry' + PathDelim + SafeName(Src) + PathDelim;
  if not DirectoryExists(Result) then
  begin
    if not Quiet then
      Status('Fetching', 'the package list ' + Src);
    EnsureDir(ExtractFileDir(ExcludeTrailingPathDelimiter(Result)));
    Git(['clone', '--quiet', '--depth', '1', Src, ExcludeTrailingPathDelimiter(Result)]);
    RegistryFetched := True;
  end
  else if Refresh and not RegistryFetched then
  begin
    Git(['pull', '--quiet', '--ff-only'], Result);
    RegistryFetched := True;
  end;
end;

function RegistryEntries(Refresh: Boolean): TRegistryEntries;
var
  Doc: TTomlDocument;
  Dir, Name: string;
  E: TRegistryEntry;
begin
  Result := nil;
  Dir := RegistryDir(Refresh);
  Doc := TTomlDocument.Create;
  try
    Doc.LoadFromFile(Dir + 'packages.toml');
    for Name in Doc.Keys('') do
    begin
      E.Name := Name;
      E.Git := Doc.GetString(Name + '.git');
      E.Path := Doc.GetString(Name + '.path', '');
      E.Description := Doc.GetString(Name + '.description', '');
      if E.Git = '' then
        Continue;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := E;
    end;
  finally
    Doc.Free;
  end;
end;

function FindInRegistry(const Name: string; out E: TRegistryEntry): Boolean;

  function Look(Refresh: Boolean): Boolean;
  var
    R: TRegistryEntry;
  begin
    for R in RegistryEntries(Refresh) do
      if SameText(R.Name, Name) then
      begin
        E := R;
        Exit(True);
      end;
    Result := False;
  end;

begin
  Result := Look(False) or Look(True);
end;

{ ---- pastel.lock ---- }

function LockIndex(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Lock) do
    if SameText(Lock[I].Name, Name) then
      Exit(I);
  Result := -1;
end;

procedure LoadLock(const ProjectRoot: string);
var
  Doc: TTomlDocument;
  Name, Root: string;
  E: TLockEntry;
begin
  if LockLoaded then
    Exit;
  LockLoaded := True;
  { the project the command is for; ProjectRoot when none is around }
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if Root = '' then
    Root := ProjectRoot;
  LockPath := IncludeTrailingPathDelimiter(Root) + LockFileName;
  if not FileExists(LockPath) then
    Exit;
  Doc := TTomlDocument.Create;
  try
    try
      Doc.LoadFromFile(LockPath);
    except
      on Ex: Exception do
        raise EPackageError.CreateFmt('%s: %s (delete it and run "pastel update")', [LockFileName, Ex.Message]);
    end;
    for Name in Doc.Keys('package') do
    begin
      E.Name := Name;
      E.Git := Doc.GetString('package.' + Name + '.git');
      E.Path := Doc.GetString('package.' + Name + '.path', '');
      E.Version := Doc.GetString('package.' + Name + '.version', '');
      E.Commit := Doc.GetString('package.' + Name + '.commit');
      SetLength(Lock, Length(Lock) + 1);
      Lock[High(Lock)] := E;
    end;
  finally
    Doc.Free;
  end;
end;

function TomlStr(const S: string): string;
begin
  Result := '"' + StringReplace(StringReplace(S, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) + '"';
end;

procedure SaveLock;
var
  L: TStringList;
  Names: TStringList;
  I, K: Integer;
begin
  if LockPath = '' then
    Exit;
  if Length(Lock) = 0 then
  begin
    DeleteFileIfExists(LockPath);
    Exit;
  end;
  L := TStringList.Create;
  Names := TStringList.Create;
  try
    for I := 0 to High(Lock) do
      Names.AddObject(Lock[I].Name, TObject(PtrInt(I)));
    Names.Sort;
    L.Add('# The exact versions of the packages, written by pastel (add, update).');
    L.Add('# Keep it in git: every computer then builds with the same code.');
    for I := 0 to Names.Count - 1 do
    begin
      K := PtrInt(Names.Objects[I]);
      L.Add('');
      L.Add('[package.' + Lock[K].Name + ']');
      L.Add('version = ' + TomlStr(Lock[K].Version));
      L.Add('git = ' + TomlStr(Lock[K].Git));
      if Lock[K].Path <> '' then
        L.Add('path = ' + TomlStr(Lock[K].Path));
      L.Add('commit = ' + TomlStr(Lock[K].Commit));
    end;
    WriteText(LockPath, L.Text);
  finally
    Names.Free;
    L.Free;
  end;
end;

{ ---- resolving ---- }

function Describe(const D: TDependency): string;
begin
  if D.Rev <> '' then Result := 'rev ' + D.Rev
  else if D.Branch <> '' then Result := 'branch ' + D.Branch
  else Result := D.Version;
end;

{ the locked version still fits what pastel.toml asks for }
function LockFits(const E: TLockEntry; const D: TDependency): Boolean;
begin
  if (E.Git <> D.Git) or (E.Path <> D.Path) then
    Exit(False);
  if D.Rev <> '' then
    Result := E.Version = D.Rev
  else if D.Branch <> '' then
    Result := E.Version = D.Branch
  else
    Result := VersionMatches(ParseVersion(E.Version), D.Version);
end;

procedure Choose(var D: TDependency; out Version, Commit: string);
var
  M, T, Best: string;
  Tags: TStringArray;
  BestV, V: TVersion;
  All: string;
begin
  M := Mirror(D.Git, True);
  if D.Rev <> '' then
  begin
    Version := D.Rev;
    Commit := Git(['rev-parse', D.Rev + '^{commit}'], M);
  end
  else if D.Branch <> '' then
  begin
    Version := D.Branch;
    if not GitOk(['rev-parse', '--verify', '--quiet', 'refs/heads/' + D.Branch], M) then
      raise EPackageError.CreateFmt('package "%s": %s has no branch "%s"', [D.Name, D.Git, D.Branch]);
    Commit := Git(['rev-parse', 'refs/heads/' + D.Branch + '^{commit}'], M);
  end
  else
  begin
    Best := '';
    BestV := Default(TVersion);
    All := '';
    TagVersions(M, Tags);
    for T in Tags do
    begin
      V := ParseVersion(T);
      if All <> '' then All := All + ', ';
      All := All + VersionText(V);
      if VersionMatches(V, D.Version) and ((Best = '') or (CompareVersions(V, BestV) > 0)) then
      begin
        Best := T;
        BestV := V;
      end;
    end;
    if Best = '' then
    begin
      if All = '' then
        raise EPackageError.CreateFmt('package "%s": %s has no versions yet (tags like v1.0.0); ' +
          'use a branch: { git = "%s", branch = "main" }', [D.Name, D.Git, D.Git]);
      raise EPackageError.CreateFmt('package "%s": no version matches "%s" (there are: %s)',
        [D.Name, D.Version, All]);
    end;
    Version := VersionText(BestV);
    Commit := Git(['rev-parse', 'refs/tags/' + Best + '^{commit}'], M);
  end;
end;

procedure DoResolve(const ProjectRoot: string; var D: TDependency);
var
  R: TRegistryEntry;
  I: Integer;
  E: TLockEntry;
  Version, Commit: string;
  Update: Boolean;
begin
  LoadLock(ProjectRoot);
  Update := (Updating.IndexOf('*') >= 0) or (Updating.IndexOf(LowerCase(D.Name)) >= 0);
  I := LockIndex(D.Name);
  if D.Git = '' then
  begin
    { from the registry: the lock knows where it is, unless it is updated }
    if (I >= 0) and ((Resolved.IndexOf(LowerCase(D.Name)) >= 0) or
       (not Update and VersionMatches(ParseVersion(Lock[I].Version), D.Version))) then
    begin
      D.Git := Lock[I].Git;
      D.Path := Lock[I].Path;
    end
    else
    begin
      if not FindInRegistry(D.Name, R) then
        raise EPackageError.CreateFmt('package "%s" is not in the registry; search with "pastel search", ' +
          'or give its repository: %s = { git = "https://..." }', [D.Name, D.Name]);
      D.Git := R.Git;
      D.Path := R.Path;
    end;
  end;
  if Resolved.IndexOf(LowerCase(D.Name)) >= 0 then
  begin
    { needed a second time (by another library): what was chosen must fit }
    if not LockFits(Lock[I], D) then
      raise EPackageError.CreateFmt('package "%s": %s is used, but a library needs %s; ' +
        'change one of the two in pastel.toml', [D.Name, Lock[I].Version, Describe(D)]);
    Version := Lock[I].Version;
    Commit := Lock[I].Commit;
  end
  else if (I >= 0) and not Update and LockFits(Lock[I], D) then
  begin
    Version := Lock[I].Version;
    Commit := Lock[I].Commit;
  end
  else
  begin
    Choose(D, Version, Commit);
    E.Name := D.Name;
    E.Git := D.Git;
    E.Path := D.Path;
    E.Version := Version;
    E.Commit := Commit;
    if (I >= 0) and (Lock[I].Commit <> Commit) and not Quiet then
      Status('Updated', Format('%s %s -> %s', [D.Name, Lock[I].Version, Version]))
    else if (I < 0) and not Quiet then
      Status('Added', Format('%s %s', [D.Name, Version]));
    if I < 0 then
    begin
      SetLength(Lock, Length(Lock) + 1);
      I := High(Lock);
    end;
    Lock[I] := E;
    SaveLock;
  end;
  Resolved.Add(LowerCase(D.Name));
  D.Resolved := Version;
  D.Root := Checkout(D, Commit);
  if D.Path <> '' then
    D.Root := IncludeTrailingPathDelimiter(D.Root + SetDirSeparators(D.Path));
end;

procedure ResolveHook(const ProjectRoot: string; var D: TDependency);
begin
  try
    DoResolve(ProjectRoot, D);
  except
    on E: EPackageError do
      raise EProjectError.Create(E.Message);
    on E: EProcessError do
      raise EProjectError.Create(E.Message);
  end;
end;

{ ---- the dependency tree ---- }

type
  TDepVisit = procedure(const D: TDependency; Depth: Integer) is nested;

procedure Walk(Project: TPastelProject; Visit: TDepVisit; Depth: Integer; Seen: TStrings);
var
  D: TDependency;
  P: TPastelProject;
begin
  for D in Project.Dependencies do
  begin
    Visit(D, Depth);
    if (D.Root = '') or (Seen.IndexOf(D.Root) >= 0) then
      Continue;
    Seen.Add(D.Root);
    P := TPastelProject.Load(D.Root);
    try
      Walk(P, Visit, Depth + 1, Seen);
    finally
      P.Free;
    end;
  end;
end;

{ loads the project (and so resolves every package) and drops locked
  packages nothing needs any more }
function LoadAll(out P: TPastelProject): Boolean;
var
  Root: string;
  Seen: TStringList;
  I: Integer;
  Kept: array of TLockEntry;

  procedure Nothing(const D: TDependency; Depth: Integer);
  begin
  end;

begin
  Result := False;
  P := nil;
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if Root = '' then
  begin
    Fail('no ' + ProjectFileName + ' here or in a folder above');
    Exit;
  end;
  P := TPastelProject.Load(Root);
  Seen := TStringList.Create;
  try
    Walk(P, @Nothing, 0, Seen);
  finally
    Seen.Free;
  end;
  LoadLock(Root);
  Kept := nil;
  for I := 0 to High(Lock) do
    if Resolved.IndexOf(LowerCase(Lock[I].Name)) >= 0 then
    begin
      SetLength(Kept, Length(Kept) + 1);
      Kept[High(Kept)] := Lock[I];
    end
    else if not Quiet then
      Status('Removed', Lock[I].Name + ' ' + Lock[I].Version);
  if Length(Kept) <> Length(Lock) then
  begin
    Lock := Kept;
    SaveLock;
  end;
  Result := True;
end;

{ ---- editing pastel.toml ---- }

{ the lines of [dependencies]: first (the header) and last (its last
  setting, or the header); -1 when there is none }
procedure FindSection(L: TStrings; out First, Last: Integer);
var
  I: Integer;
  T: string;
begin
  First := -1;
  Last := -1;
  for I := 0 to L.Count - 1 do
  begin
    T := Trim(L[I]);
    if First < 0 then
    begin
      if T = '[dependencies]' then
      begin
        First := I;
        Last := I;
      end;
    end
    else if (T <> '') and (T[1] = '[') then
      Break
    else if (T <> '') and (T[1] <> '#') then
      Last := I;
  end;
end;

function DepLine(L: TStrings; First, Last: Integer; const Name: string): Integer;
var
  I, P: Integer;
  T: string;
begin
  for I := First + 1 to Last do
  begin
    T := Trim(L[I]);
    P := Pos('=', T);
    if (P > 0) and SameText(Trim(Copy(T, 1, P - 1)), Name) then
      Exit(I);
  end;
  Result := -1;
end;

procedure SetDependency(const Root, Name, Value: string);
var
  L: TStringList;
  First, Last, I: Integer;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(Root + ProjectFileName);
    FindSection(L, First, Last);
    if First < 0 then
    begin
      if (L.Count > 0) and (Trim(L[L.Count - 1]) <> '') then
        L.Add('');
      L.Add('[dependencies]');
      First := L.Count - 1;
      Last := First;
    end;
    I := DepLine(L, First, Last, Name);
    if I >= 0 then
      L[I] := Name + ' = ' + Value
    else
      L.Insert(Last + 1, Name + ' = ' + Value);
    L.SaveToFile(Root + ProjectFileName);
  finally
    L.Free;
  end;
end;

function RemoveDependency(const Root, Name: string): Boolean;
var
  L: TStringList;
  First, Last, I: Integer;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(Root + ProjectFileName);
    FindSection(L, First, Last);
    I := -1;
    if First >= 0 then
      I := DepLine(L, First, Last, Name);
    Result := I >= 0;
    if Result then
    begin
      L.Delete(I);
      L.SaveToFile(Root + ProjectFileName);
    end;
  finally
    L.Free;
  end;
end;

{ ---- commands ---- }

function Usage(const Msg: string): Integer;
begin
  Fail(Msg);
  Result := 2;
end;

function Guard(E: Exception): Integer;
begin
  Fail(E.Message);
  Result := 1;
end;

function ProjectHere(out Root: string): Boolean;
begin
  Root := TPastelProject.FindRoot(GetCurrentDir);
  Result := Root <> '';
  if not Result then
    Fail('no ' + ProjectFileName + ' here or in a folder above');
  Root := IncludeTrailingPathDelimiter(Root);
end;

function RunAdd(const Args: TStringArray; const Git, SubPath, Branch: string): Integer;
var
  Root, Name, Constraint, Value, Before, LockBefore: string;
  P: TPastelProject;
  D: TDependency;
  At: Integer;
begin
  if Length(Args) <> 1 then
    Exit(Usage('usage: pastel add <name>[@version] [--git URL] [--path folder] [--branch name]'));
  if not ProjectHere(Root) then
    Exit(1);
  Name := Args[0];
  Constraint := '';
  At := Pos('@', Name);
  if At > 0 then
  begin
    Constraint := Copy(Name, At + 1, MaxInt);
    Name := Copy(Name, 1, At - 1);
  end;
  if not IsValidProjectName(Name) then
    Exit(Usage(Format('"%s" is not a package name (letters, digits, "-" and "_")', [Name])));
  Before := ReadText(Root + ProjectFileName);
  LockBefore := '';
  if FileExists(Root + LockFileName) then
    LockBefore := ReadText(Root + LockFileName);
  try
    if (Git = '') and (SubPath <> '') then
    begin
      { a library in a folder on this computer }
      if not FileExists(JoinPath([ExpandFileName(Root + SubPath), ProjectFileName])) then
        Exit(Usage(Format('no %s in %s', [ProjectFileName, SubPath])));
      SetDependency(Root, Name, '{ path = ' + TomlStr(SubPath) + ' }');
      Status('Added', Format('%s (%s)', [Name, SubPath]));
      Exit(0);
    end;
    { find the version now, so pastel.toml gets "^" + the newest one }
    D := Default(TDependency);
    D.Name := Name;
    D.Remote := True;
    D.Git := Git;
    D.Path := SubPath;
    D.Branch := Branch;
    D.Version := Constraint;
    if D.Version = '' then
      D.Version := '*';
    if Branch <> '' then
      D.Version := '';
    Updating.Add(LowerCase(Name));
    DoResolve(Root, D);
    if (Constraint = '') and (Branch = '') then
      Constraint := '^' + D.Resolved;
    if Git = '' then
      Value := TomlStr(Constraint)
    else
    begin
      Value := '{ git = ' + TomlStr(Git);
      if SubPath <> '' then
        Value := Value + ', path = ' + TomlStr(SubPath);
      if Branch <> '' then
        Value := Value + ', branch = ' + TomlStr(Branch)
      else
        Value := Value + ', version = ' + TomlStr(Constraint);
      Value := Value + ' }';
    end;
    SetDependency(Root, Name, Value);
    { load everything once: the package's own dependencies, and a check that it builds as a library }
    Resolved.Clear;
    Updating.Clear;
    if not LoadAll(P) then
      Exit(1);
    P.Free;
    Hint(Format('%s = %s in pastel.toml; its units can now be used (uses ...)', [Name, Value]));
    Result := 0;
  except
    on E: Exception do
    begin
      { leave pastel.toml and pastel.lock as they were }
      WriteText(Root + ProjectFileName, Before);
      if LockBefore <> '' then
        WriteText(Root + LockFileName, LockBefore)
      else
        DeleteFileIfExists(Root + LockFileName);
      Result := Guard(E);
    end;
  end;
end;

function RunRemove(const Args: TStringArray): Integer;
var
  Root, Name: string;
  P: TPastelProject;
begin
  if Length(Args) = 0 then
    Exit(Usage('usage: pastel remove <name>...'));
  if not ProjectHere(Root) then
    Exit(1);
  Result := 0;
  for Name in Args do
    if not RemoveDependency(Root, Name) then
    begin
      Fail(Format('"%s" is not in [dependencies] of %s', [Name, ProjectFileName]));
      Result := 1;
    end;
  try
    if LoadAll(P) then
      P.Free;
  except
    on E: Exception do
      Result := Guard(E);
  end;
end;

function RunUpdate(const Args: TStringArray): Integer;
var
  N: string;
  P: TPastelProject;
  Before: Integer;
  Changed: Boolean;
  I: Integer;
  Old: array of TLockEntry;
  Root: string;
begin
  if not ProjectHere(Root) then
    Exit(1);
  if Length(Args) = 0 then
    Updating.Add('*')
  else
    for N in Args do
      Updating.Add(LowerCase(N));
  try
    LoadLock(Root);
    Old := Copy(Lock);
    Before := Length(Lock);
    if not LoadAll(P) then
      Exit(1);
    try
      Changed := Length(Lock) <> Before;
      for I := 0 to High(Lock) do
        if (I > High(Old)) or (Old[I].Commit <> Lock[I].Commit) then
          Changed := True;
      if not Changed then
        Status('Checked', 'every package is at the newest version pastel.toml allows');
    finally
      P.Free;
    end;
    Result := 0;
  except
    on E: Exception do
      Result := Guard(E);
  end;
end;

function RunSearch(const Args: TStringArray): Integer;
var
  E: TRegistryEntry;
  W: string;
  Found, Hit: Boolean;
begin
  try
    Found := False;
    for E in RegistryEntries(True) do
    begin
      Hit := True;
      for W in Args do
        if (Pos(LowerCase(W), LowerCase(E.Name)) = 0) and (Pos(LowerCase(W), LowerCase(E.Description)) = 0) then
          Hit := False;
      if not Hit then
        Continue;
      Found := True;
      WriteLn(Bold(Format('%-16s', [E.Name])), ' ', E.Description);
    end;
    if not Found then
      Status('Searched', 'no package matches')
    else
      Hint('add one with: pastel add <name>');
    Result := 0;
  except
    on Ex: Exception do
      Result := Guard(Ex);
  end;
end;

function RunDeps(Json: Boolean): Integer;
var
  P: TPastelProject;
  Seen: TStringList;
  Out_: string;

  procedure Show(const D: TDependency; Depth: Integer);
  var
    Where: string;
  begin
    if Json then
    begin
      if Out_ <> '' then
        Out_ := Out_ + ',';
      Out_ := Out_ + Format('{"name":%s,"version":%s,"root":%s,"depth":%d,"package":%s}',
        [JsonStr(D.Name), JsonStr(D.Resolved), JsonStr(ExcludeTrailingPathDelimiter(D.Root)), Depth,
         BoolToStr(D.Remote, 'true', 'false')]);
      Exit;
    end;
    if D.Remote then
      Where := D.Resolved + Dim('  ' + D.Git + BoolToStr(D.Path <> '', ' (' + D.Path + ')', ''))
    else
      Where := Dim(D.Path);
    WriteLn(StringOfChar(' ', 2 * Depth), Bold(D.Name), ' ', Where);
  end;

begin
  Quiet := Json;
  try
    if not LoadAll(P) then
      Exit(1);
    Seen := TStringList.Create;
    try
      Out_ := '';
      if not Json and (Length(P.Dependencies) = 0) then
        Status('Checked', 'the project has no dependencies')
      else
        Walk(P, @Show, 0, Seen);
      if Json then
        WriteLn('[' + Out_ + ']');
    finally
      Seen.Free;
      P.Free;
    end;
    Result := 0;
  except
    on E: Exception do
      Result := Guard(E);
  end;
end;

initialization
  Resolved := TStringList.Create;
  Updating := TStringList.Create;
  Fetched := TStringList.Create;
  ResolvePackage := @ResolveHook;

finalization
  Resolved.Free;
  Updating.Free;
  Fetched.Free;

end.
