{ Pastel - "pastel lang": the texts of a project, for translating it.

    pastel lang              update every assets/lang/*.json with the texts
                             of the project; tells what is not translated
    pastel lang add tr       a new language: assets/lang/tr.json
    pastel lang list         the texts that would be translated

  Texts come from .pform files (Text, Caption, Title, Placeholder, Hint,
  Items) and from _('...') and Translate('...') in .pas files. Pastel's own
  texts (OK, Cancel, Yes...) are built in for some languages and may be
  overridden in the files too. Translations
  already in a file are kept; texts no longer used are moved to the end
  with the name "-unused-".
  Part of the Pastel project, MIT License. }
unit Pastel.LangCmd;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

function RunLang(const Args: TStringArray): Integer;

{ The texts to translate in the project at Root, sorted. }
function CollectTexts(const Root: string): TStringArray;

implementation

uses
  Classes, fpjson, Pastel.Console, Pastel.Project, Pastel.Files, Pastel.PForm, Pastel.Json, Pastel.Lang;

procedure AddText(L: TStringList; const S: string);
var
  T: string;
begin
  T := TrimLeft(S);
  if (T <> '') and (T <> '-') then
    L.Add(T);
end;

procedure VisitNode(Node: TPFormNode; Data: Pointer);
var
  I, J: Integer;
  P: TPFormProp;
  Lines: TStringArray;
begin
  for I := 0 to Node.Props.Count - 1 do
  begin
    P := Node.Prop(I);
    case LowerCase(P.Name) of
      'text', 'caption', 'title', 'placeholder', 'hint':
        if P.Kind = pvString then
          AddText(TStringList(Data), P.Value);
      'items':
        if P.Kind = pvList then
        begin
          Lines := P.Value.Split([#10]);
          for J := 0 to High(Lines) do
            AddText(TStringList(Data), Lines[J]);
        end;
    end;
  end;
end;

procedure ScanPForm(const FileName: string; L: TStringList);
var
  Root: TPFormNode;
begin
  try
    Root := ParsePFormFile(FileName);
  except
    on E: Exception do
    begin
      Warn(Format('%s: %s', [FileName, E.Message]));
      Exit;
    end;
  end;
  try
    VisitNode(Root, L);
    VisitPForm(Root, @VisitNode, L);
  finally
    Root.Free;
  end;
end;

{ _('a''b') and Translate('...'): the literal right after the bracket }
procedure ScanPascal(const Src: string; L: TStringList);
var
  I, J, N: Integer;
  S: string;
  Word: string;
begin
  I := 1;
  N := Length(Src);
  while I <= N do
  begin
    { skip comments and strings that are not arguments }
    if (Src[I] = '/') and (I < N) and (Src[I + 1] = '/') then
    begin
      while (I <= N) and not (Src[I] in [#10, #13]) do Inc(I);
      Continue;
    end;
    if Src[I] = '{' then
    begin
      while (I <= N) and (Src[I] <> '}') do Inc(I);
      Inc(I);
      Continue;
    end;
    if Src[I] = '''' then
    begin
      Inc(I);
      while (I <= N) and (Src[I] <> '''') do Inc(I);
      Inc(I);
      Continue;
    end;
    if Src[I] in ['_', 'A'..'Z', 'a'..'z'] then
    begin
      J := I;
      while (I <= N) and (Src[I] in ['_', 'A'..'Z', 'a'..'z', '0'..'9']) do Inc(I);
      Word := LowerCase(Copy(Src, J, I - J));
      if (Word = '_') or (Word = 'translate') then
      begin
        J := I;
        while (J <= N) and (Src[J] in [' ', #9]) do Inc(J);
        if (J <= N) and (Src[J] = '(') then
        begin
          Inc(J);
          while (J <= N) and (Src[J] in [' ', #9]) do Inc(J);
          if (J <= N) and (Src[J] = '''') then
          begin
            S := '';
            Inc(J);
            while J <= N do
            begin
              if Src[J] = '''' then
              begin
                if (J < N) and (Src[J + 1] = '''') then
                begin
                  S := S + '''';
                  Inc(J, 2);
                  Continue;
                end;
                Break;
              end;
              S := S + Src[J];
              Inc(J);
            end;
            { only a whole literal: _('a' + B) is not collected }
            Inc(J);
            while (J <= N) and (Src[J] in [' ', #9]) do Inc(J);
            if (J <= N) and (Src[J] = ')') then
              AddText(L, S);
            I := J;
          end;
        end;
      end;
      Continue;
    end;
    Inc(I);
  end;
end;

{ the folders of the project's dependencies, and of theirs }
function DependencyRoots(const Root: string): TStringArray;
var
  Seen: TStringList;

  procedure Walk(const Dir: string);
  var
    P: TPastelProject;
    D: TDependency;
  begin
    try
      P := TPastelProject.Load(Dir);
    except
      Exit;
    end;
    try
      for D in P.Dependencies do
        if (D.Root <> '') and (Seen.IndexOf(D.Root) < 0) then
        begin
          Seen.Add(D.Root);
          Walk(D.Root);
        end;
    finally
      P.Free;
    end;
  end;

begin
  Seen := TStringList.Create;
  try
    Walk(Root);
    Result := Seen.ToStringArray;
  finally
    Seen.Free;
  end;
end;

function CollectTexts(const Root: string): TStringArray;
var
  L: TStringList;
  F, D: string;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.Sorted := True;
    L.CaseSensitive := True;
    L.Duplicates := dupIgnore;
    if DirectoryExists(JoinPath([Root, 'src'])) then
    begin
      for F in ListFiles(JoinPath([Root, 'src']), '*.pform', True) do
        ScanPForm(F, L);
      for F in ListFiles(JoinPath([Root, 'src']), '*.pas', True) do
        ScanPascal(ReadText(F), L);
    end;
    { the texts of libraries the app uses are shown by the app too }
    for F in DependencyRoots(Root) do
      if DirectoryExists(JoinPath([F, 'src'])) then
      begin
        for D in ListFiles(JoinPath([F, 'src']), '*.pform', True) do
          ScanPForm(D, L);
        for D in ListFiles(JoinPath([F, 'src']), '*.pas', True) do
          ScanPascal(ReadText(D), L);
      end;
    Result := nil;
    SetLength(Result, L.Count);
    for I := 0 to L.Count - 1 do
      Result[I] := L[I];
  finally
    L.Free;
  end;
end;

function LangDir(const Root: string): string;
begin
  Result := JoinPath([Root, 'assets', 'lang']);
end;

{ writes the file; returns the number of texts without a translation }
function UpdateFile(const FileName: string; const Texts: TStringArray; out Unused: Integer): Integer;
var
  Old: TJSONObject;
  Data: TJSONData;
  Known: TStringList;
  Out_, V: string;
  I: Integer;
  First: Boolean;

  procedure Line(const K, Value: string);
  begin
    if not First then
      Out_ := Out_ + ',' + LineEnding;
    First := False;
    Out_ := Out_ + '  ' + JsonQuote(K) + ': ' + JsonQuote(Value);
  end;

begin
  Result := 0;
  Unused := 0;
  Old := nil;
  if FileExists(FileName) then
  begin
    Data := LoadJsonFile(FileName);
    if not (Data is TJSONObject) then
    begin
      Data.Free;
      raise Exception.CreateFmt('%s: expected { "text": "translation", ... }', [FileName]);
    end;
    Old := TJSONObject(Data);
  end;
  Known := TStringList.Create;
  try
    Known.Sorted := True;
    Known.CaseSensitive := True;
    { Pastel's own texts may be translated too (dialog buttons) }
    for V in FrameworkTexts do
      Known.Add(V);
    Out_ := '{' + LineEnding;
    First := True;
    for I := 0 to High(Texts) do
    begin
      Known.Add(Texts[I]);
      V := '';
      if (Old <> nil) and (Old.Find(Texts[I]) <> nil) and (Old.Find(Texts[I]).JSONType = jtString) then
        V := Old.Strings[Texts[I]];
      if V = '' then
        Inc(Result);
      Line(Texts[I], V);
    end;
    { translations of texts the project does not use any more: kept, marked }
    if Old <> nil then
      for I := 0 to Old.Count - 1 do
        if (Old.Names[I] <> '-unused-') and (Known.IndexOf(Old.Names[I]) < 0) and
          (Old.Items[I].JSONType = jtString) and (Old.Items[I].AsString <> '') then
        begin
          if Unused = 0 then
            Line('-unused-', 'the texts below are not in the project any more');
          Inc(Unused);
          Line(Old.Names[I], Old.Items[I].AsString);
        end;
    Out_ := Out_ + LineEnding + '}' + LineEnding;
    WriteText(FileName, Out_);
  finally
    Known.Free;
    Old.Free;
  end;
end;

function RunLang(const Args: TStringArray): Integer;
var
  Root, Action, Code, F: string;
  Texts: TStringArray;
  Files: TStringArray;
  Missing, Unused: Integer;
begin
  Result := 0;
  Root := TPastelProject.FindRoot(GetCurrentDir);
  if Root = '' then
  begin
    Fail('no ' + ProjectFileName + ' found here or in any parent folder');
    Exit(1);
  end;
  Action := 'update';
  if Length(Args) > 0 then
    Action := LowerCase(Args[0]);
  Texts := CollectTexts(Root);
  case Action of
    'list':
      for F in Texts do
        WriteLn(F);
    'add':
      begin
        if Length(Args) < 2 then
        begin
          Fail('which language? for example: pastel lang add tr');
          Exit(2);
        end;
        Code := Args[1];
        F := JoinPath([LangDir(Root), Code + '.json']);
        if FileExists(F) then
        begin
          Fail(Format('assets/lang/%s.json exists already; "pastel lang" updates it', [Code]));
          Exit(1);
        end;
        ForceDirectories(LangDir(Root));
        Missing := UpdateFile(F, Texts, Unused);
        Status('Created', Format('assets/lang/%s.json with %d text(s) to translate', [Code, Missing]));
      end;
    'update':
      begin
        if not DirectoryExists(LangDir(Root)) then
        begin
          WriteLn(Format('%d text(s) in the project; no languages yet.', [Length(Texts)]));
          Tip('add one with: pastel lang add tr');
          Exit;
        end;
        Files := ListFiles(LangDir(Root), '*.json');
        for F in Files do
        begin
          try
            Missing := UpdateFile(F, Texts, Unused);
          except
            on E: Exception do
            begin
              Fail(E.Message);
              Exit(1);
            end;
          end;
          if Missing = 0 then
            Status('Updated', Format('%s: all %d text(s) translated', [ExtractFileName(F), Length(Texts)]))
          else
            Status('Updated', Format('%s: %d of %d text(s) not translated yet', [ExtractFileName(F), Missing, Length(Texts)]));
          if Unused > 0 then
            WriteLn(Format('         %d translation(s) no longer used (after "-unused-")', [Unused]));
        end;
      end;
  else
    Fail(Format('unknown "pastel lang %s"; use: pastel lang, pastel lang add <code>, pastel lang list', [Action]));
    Result := 2;
  end;
end;

end.
