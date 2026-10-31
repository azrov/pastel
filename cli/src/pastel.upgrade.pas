{ Pastel - "pastel upgrade": brings a project made with an older Pastel up
  to date.

    pastel upgrade           make the changes (and tell what changed)
    pastel upgrade --check   only tell what would change; exit code 1 if anything

  [project] pastel = "0.7" in pastel.toml records the Pastel version a project
  is made for. A build warns when the project needs a newer Pastel, and hints
  at "pastel upgrade" when it is from an older one.
  Part of the Pastel project, MIT License. }
unit Pastel.Upgrade;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Project;

function RunUpgrade(CheckOnly: Boolean): Integer;
{ The changes "pastel upgrade" would make, one line each; nil when none. }
function PendingUpgrades(const Root: string): TStringArray;
{ For builds: a warning when the project is for a newer Pastel, a hint when
  it can be upgraded. }
procedure CheckProjectVersion(Project: TPastelProject);

implementation

uses
  Classes, RegExpr, Pastel.Console, Pastel.Files;

type
  TStep = record
    What: string;
    Files: TStringList;    { file name -> new text }
  end;

function Max(A, B: Integer): Integer;
begin
  if A > B then Result := A else Result := B;
end;

{ 1 when A > B, -1 when A < B, 0 when equal; by numbers ('0.10' > '0.9') }
function CompareVersions(const A, B: string): Integer;
var
  PA, PB: TStringArray;
  I, NA, NB: Integer;
begin
  PA := A.Split(['.']);
  PB := B.Split(['.']);
  for I := 0 to Max(High(PA), High(PB)) do
  begin
    if I <= High(PA) then NA := StrToIntDef(PA[I], 0) else NA := 0;
    if I <= High(PB) then NB := StrToIntDef(PB[I], 0) else NB := 0;
    if NA <> NB then
    begin
      if NA > NB then Exit(1) else Exit(-1);
    end;
  end;
  Result := 0;
end;

{ Key = "Value" in [project]: the line replaced, or added after name/version }
function WithProjectKey(const Toml, Key, Value: string): string;
var
  L: TStringList;
  I, Insert: Integer;
  InProject: Boolean;
  T: string;
begin
  L := TStringList.Create;
  try
    L.Text := Toml;
    InProject := False;
    Insert := -1;
    for I := 0 to L.Count - 1 do
    begin
      T := Trim(L[I]);
      if (T <> '') and (T[1] = '[') then
      begin
        if InProject then
          Break;
        InProject := T = '[project]';
        if InProject then
          Insert := I;
        Continue;
      end;
      if not InProject then
        Continue;
      if ExecRegExpr('^' + Key + '\s*=', T) then
      begin
        L[I] := Key + ' = "' + Value + '"';
        Exit(L.Text);
      end;
      if ExecRegExpr('^(name|version|pastel)\s*=', T) then
        Insert := I;
    end;
    if Insert < 0 then
    begin
      L.Insert(0, '[project]');
      Insert := 0;
    end;
    L.Insert(Insert + 1, Key + ' = "' + Value + '"');
    Result := L.Text;
  finally
    L.Free;
  end;
end;

procedure AddStep(var Steps: array of TStep; var Count: Integer; const What: string);
begin
  Steps[Count].What := What;
  Steps[Count].Files := TStringList.Create;
  Inc(Count);
end;

function CollectSteps(const Root: string; out Steps: array of TStep): Integer;
var
  P: TPastelProject;
  TomlFile, Toml, F, Text, NewText, Ignore, Missing, Title: string;
  Forms: TStringArray;
begin
  Result := 0;
  P := TPastelProject.Load(Root);
  try
    TomlFile := Root + ProjectFileName;
    Toml := ReadText(TomlFile);

    { the version the project is made for }
    if (P.PastelFor = '') or (CompareVersions(P.PastelFor, PastelMinor) < 0) then
    begin
      if P.PastelFor = '' then
        AddStep(Steps, Result, Format('pastel.toml: [project] pastel = "%s" (the Pastel version it is made for)',
          [PastelMinor]))
      else
        AddStep(Steps, Result, Format('pastel.toml: pastel = "%s" (was "%s")', [PastelMinor, P.PastelFor]));
      Toml := WithProjectKey(Toml, 'pastel', PastelMinor);
      Steps[Result - 1].Files.Values[TomlFile] := Toml;
    end;

    { 0.6: apps have a title for menus, installers and the AppImage }
    if (P.Kind = 'app') and not ExecRegExpr('(?m)^[ \t]*title[ \t]*=', Toml) then
    begin
      Title := TitleFromName(P.Name);
      AddStep(Steps, Result, Format('pastel.toml: title = "%s" (the name in menus and installers)', [Title]));
      Toml := WithProjectKey(Toml, 'title', Title);
      Steps[Result - 1].Files.Values[TomlFile] := Toml;
    end;

    { 0.5: a control named Hint hides the Hint property of the form (the 0.4 template had one) }
    if DirectoryExists(Root + 'src') then
    begin
      Forms := ListFiles(Root + 'src', '*.pform', True);
      for F in Forms do
      begin
        Text := ReadText(F);
        if not ExecRegExpr('(?m)^\s*object\s+Hint\s*:', Text) then
          Continue;
        AddStep(Steps, Result, Format('%s: the control "Hint" is now "HintLabel" (Hint is a property of every control)',
          [ExtractRelativePath(Root, F)]));
        Steps[Result - 1].Files.Values[F] := ReplaceRegExpr('(?m)^(\s*object\s+)Hint(\s*:)', Text, '$1HintLabel$2', True);
        if FileExists(ChangeFileExt(F, '.pas')) then
        begin
          Text := ReadText(ChangeFileExt(F, '.pas'));
          NewText := ReplaceRegExpr('\bHint\.', Text, 'HintLabel.', False);
          if NewText <> Text then
            Steps[Result - 1].Files.Values[ChangeFileExt(F, '.pas')] := NewText;
        end;
      end;
    end;

    { build output stays out of git }
    if FileExists(Root + '.gitignore') then
    begin
      Ignore := ReadText(Root + '.gitignore');
      Missing := '';
      if not ExecRegExpr('(?m)^/?build/?\s*$', Ignore) then
        Missing := Missing + 'build/' + LineEnding;
      if not ExecRegExpr('(?m)^/?dist/?\s*$', Ignore) then
        Missing := Missing + 'dist/' + LineEnding;
      if Missing <> '' then
      begin
        AddStep(Steps, Result, '.gitignore: ' + StringReplace(Trim(Missing), LineEnding, ', ', [rfReplaceAll]));
        if (Ignore <> '') and (Ignore[Length(Ignore)] <> #10) then
          Ignore := Ignore + LineEnding;
        Steps[Result - 1].Files.Values[Root + '.gitignore'] := Ignore + Missing;
      end;
    end;
  finally
    P.Free;
  end;
end;

function FindProjectRoot: string;
begin
  Result := TPastelProject.FindRoot(GetCurrentDir);
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result);
end;

function PendingUpgrades(const Root: string): TStringArray;
var
  Steps: array[0..31] of TStep;
  N, I: Integer;
begin
  Result := nil;
  N := CollectSteps(IncludeTrailingPathDelimiter(Root), Steps);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    Result[I] := Steps[I].What;
    Steps[I].Files.Free;
  end;
end;

function RunUpgrade(CheckOnly: Boolean): Integer;
var
  Root: string;
  Steps: array[0..31] of TStep;
  N, I, J: Integer;
  P: TPastelProject;
  Final: TStringList;
begin
  Root := FindProjectRoot;
  if Root = '' then
  begin
    Fail('no ' + ProjectFileName + ' found; run "pastel upgrade" in a project folder');
    Exit(2);
  end;
  P := TPastelProject.Load(Root);
  try
    if (P.PastelFor <> '') and (CompareVersions(P.PastelFor, PastelMinor) > 0) then
    begin
      Fail(Format('this project is made for Pastel %s; this pastel is %s - update pastel first',
        [P.PastelFor, PastelVersion]));
      Exit(1);
    end;
  finally
    P.Free;
  end;
  N := CollectSteps(Root, Steps);
  if N = 0 then
  begin
    Status('Up to date', Format('the project is made for Pastel %s', [PastelMinor]));
    Exit(0);
  end;
  { later steps saw the text of earlier ones: the last text of each file wins }
  Final := TStringList.Create;
  try
    for I := 0 to N - 1 do
    begin
      if CheckOnly then
        WriteLn('  would change ', Steps[I].What)
      else
        Status('Upgraded', Steps[I].What);
      for J := 0 to Steps[I].Files.Count - 1 do
        Final.Values[Steps[I].Files.Names[J]] := Steps[I].Files.ValueFromIndex[J];
      Steps[I].Files.Free;
    end;
    if CheckOnly then
    begin
      Hint('run "pastel upgrade" to make these changes');
      Exit(1);
    end;
    for I := 0 to Final.Count - 1 do
      WriteText(Final.Names[I], Final.ValueFromIndex[I]);
  finally
    Final.Free;
  end;
  Result := 0;
end;

procedure CheckProjectVersion(Project: TPastelProject);
var
  K: string;
begin
  for K in Project.UnknownKeys do
    Warn(Format('%s: unknown setting "%s" (ignored; see docs/project.md)', [ProjectFileName, K]));
  if (Project.PastelFor <> '') and (CompareVersions(Project.PastelFor, PastelMinor) > 0) then
    Warn(Format('this project is made for Pastel %s, this pastel is %s; some things may not work - update pastel',
      [Project.PastelFor, PastelVersion]))
  else if (Project.PastelFor = '') or (CompareVersions(Project.PastelFor, PastelMinor) < 0) then
    Hint(Format('this project is from an older Pastel; "pastel upgrade" brings it up to date (%s)', [PastelMinor]));
end;

end.
