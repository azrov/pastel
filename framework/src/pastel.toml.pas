{ Pastel - a small TOML reader for pastel.toml files.

  Supported: [tables], dotted keys, basic and literal strings, integers,
  floats, booleans, arrays of scalars (also across lines), inline tables
  (on one line, in curly brackets), comments.
  Not supported yet: multi-line strings, dates, [[arrays of tables]].
  Part of the Pastel project, MIT License. }
unit Pastel.Toml;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  ETomlError = class(Exception);

  TTomlKind = (tkString, tkInteger, tkFloat, tkBoolean, tkArray);

  TTomlValue = class
  public
    Kind: TTomlKind;
    Text: string;          { scalar value as text }
    Items: TStringArray;   { array items (scalars only) }
  end;

  TTomlDocument = class
  private
    FValues: TStringList;
    FTables: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromString(const Src: string);
    procedure LoadFromFile(const FileName: string);
    function Has(const Path: string): Boolean;
    function Find(const Path: string): TTomlValue;
    function GetString(const Path: string; const Default: string = ''): string;
    function GetBool(const Path: string; Default: Boolean = False): Boolean;
    function GetInt(const Path: string; Default: Int64 = 0): Int64;
    function GetArray(const Path: string): TStringArray;
    { Names directly inside a table: Keys('dependencies') -> ['json', 'utils'] }
    function Keys(const Table: string): TStringArray;
    property Values: TStringList read FValues;
  end;

function CodePointToUTF8(CP: Cardinal): string;

implementation

function CodePointToUTF8(CP: Cardinal): string;
begin
  if CP < $80 then
    Result := Chr(CP)
  else if CP < $800 then
    Result := Chr($C0 or (CP shr 6)) + Chr($80 or (CP and $3F))
  else if CP < $10000 then
    Result := Chr($E0 or (CP shr 12)) + Chr($80 or ((CP shr 6) and $3F)) +
              Chr($80 or (CP and $3F))
  else
    Result := Chr($F0 or (CP shr 18)) + Chr($80 or ((CP shr 12) and $3F)) +
              Chr($80 or ((CP shr 6) and $3F)) + Chr($80 or (CP and $3F));
end;

constructor TTomlDocument.Create;
begin
  inherited Create;
  FValues := TStringList.Create;
  FValues.OwnsObjects := True;
  FValues.CaseSensitive := True;
  FValues.Sorted := True;
  FTables := TStringList.Create;
  FTables.CaseSensitive := True;
  FTables.Sorted := True;
end;

destructor TTomlDocument.Destroy;
begin
  FValues.Free;
  FTables.Free;
  inherited Destroy;
end;

procedure TTomlDocument.LoadFromFile(const FileName: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    LoadFromString(L.Text);
  finally
    L.Free;
  end;
end;

procedure TTomlDocument.LoadFromString(const Src: string);
var
  P, Len, Line: Integer;
  Table, Key: string;

  procedure Error(const Msg: string);
  begin
    raise ETomlError.CreateFmt('line %d: %s', [Line, Msg]);
  end;

  function Peek: Char;
  begin
    if P <= Len then Result := Src[P] else Result := #0;
  end;

  procedure SkipSpaces;
  begin
    while (P <= Len) and (Src[P] in [' ', #9]) do Inc(P);
  end;

  procedure SkipComment;
  begin
    if Peek = '#' then
      while (P <= Len) and not (Src[P] in [#10, #13]) do Inc(P);
  end;

  procedure SkipBlank;  { spaces, comments and newlines (inside arrays) }
  begin
    repeat
      SkipSpaces;
      SkipComment;
      if Peek = #13 then
        Inc(P)
      else if Peek = #10 then
      begin
        Inc(P);
        Inc(Line);
      end
      else
        Break;
    until False;
  end;

  procedure ExpectLineEnd;
  begin
    SkipSpaces;
    SkipComment;
    if Peek = #13 then Inc(P);
    if Peek = #10 then
    begin
      Inc(P);
      Inc(Line);
    end
    else if P <= Len then
      Error('unexpected text "' + Copy(Src, P, 20) + '"');
  end;

  function ParseBasicString: string;
  var
    C: Char;
    N: Integer;
    Code: Int64;
  begin
    if Copy(Src, P, 3) = '"""' then
      Error('multi-line strings are not supported yet');
    Inc(P);
    Result := '';
    repeat
      if (P > Len) or (Src[P] in [#10, #13]) then
        Error('unterminated string');
      C := Src[P];
      Inc(P);
      if C = '"' then
        Exit;
      if C = '\' then
      begin
        if P > Len then Error('unterminated string');
        C := Src[P];
        Inc(P);
        case C of
          'n': Result := Result + #10;
          't': Result := Result + #9;
          'r': Result := Result + #13;
          'b': Result := Result + #8;
          'f': Result := Result + #12;
          '"': Result := Result + '"';
          '\': Result := Result + '\';
          'u', 'U':
            begin
              if C = 'u' then N := 4 else N := 8;
              Code := StrToInt64Def('$' + Copy(Src, P, N), -1);
              if (Code < 0) or (Length(Copy(Src, P, N)) <> N) then
                Error('invalid unicode escape');
              Inc(P, N);
              Result := Result + CodePointToUTF8(Cardinal(Code));
            end;
        else
          Error('invalid escape "\' + C + '"');
        end;
      end
      else
        Result := Result + C;
    until False;
  end;

  function ParseLiteralString: string;
  begin
    if Copy(Src, P, 3) = '''''''' then
      Error('multi-line strings are not supported yet');
    Inc(P);
    Result := '';
    repeat
      if (P > Len) or (Src[P] in [#10, #13]) then
        Error('unterminated string');
      if Src[P] = '''' then
      begin
        Inc(P);
        Exit;
      end;
      Result := Result + Src[P];
      Inc(P);
    until False;
  end;

  function ParseKeyPart: string;
  begin
    SkipSpaces;
    if Peek = '"' then
      Result := ParseBasicString
    else if Peek = '''' then
      Result := ParseLiteralString
    else
    begin
      Result := '';
      while (P <= Len) and (Src[P] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) do
      begin
        Result := Result + Src[P];
        Inc(P);
      end;
      if Result = '' then
        Error('expected a key');
    end;
    SkipSpaces;
  end;

  function ParseKey: string;
  begin
    Result := ParseKeyPart;
    while Peek = '.' do
    begin
      Inc(P);
      Result := Result + '.' + ParseKeyPart;
    end;
  end;

  function ParseScalar(out Kind: TTomlKind): string;
  var
    Tok, Clean: string;
    I64: Int64;
    F: Double;
    FS: TFormatSettings;
  begin
    case Peek of
      '"':
        begin
          Kind := tkString;
          Exit(ParseBasicString);
        end;
      '''':
        begin
          Kind := tkString;
          Exit(ParseLiteralString);
        end;
      '[':
        Error('nested arrays are not supported yet');
      '{':
        Error('inline tables are not supported yet');
    end;
    Tok := '';
    while (P <= Len) and not (Src[P] in [' ', #9, #10, #13, ',', ']', '#']) do
    begin
      Tok := Tok + Src[P];
      Inc(P);
    end;
    if Tok = '' then
      Error('expected a value');
    if (Tok = 'true') or (Tok = 'false') then
    begin
      Kind := tkBoolean;
      Exit(Tok);
    end;
    Clean := StringReplace(Tok, '_', '', [rfReplaceAll]);
    if TryStrToInt64(Clean, I64) and (Pos('$', Clean) = 0) then
    begin
      Kind := tkInteger;
      Exit(IntToStr(I64));
    end;
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    if TryStrToFloat(Clean, F, FS) then
    begin
      Kind := tkFloat;
      Exit(Clean);
    end;
    Error('invalid value "' + Tok + '" (strings need quotes)');
  end;

  procedure ParseValue(Into: TTomlValue);
  var
    K: TTomlKind;
    S: string;
  begin
    if Peek = '[' then
    begin
      Into.Kind := tkArray;
      Into.Items := nil;
      Inc(P);
      repeat
        SkipBlank;
        if Peek = ']' then
          Break;
        if P > Len then
          Error('unterminated array');
        S := ParseScalar(K);
        SetLength(Into.Items, Length(Into.Items) + 1);
        Into.Items[High(Into.Items)] := S;
        SkipBlank;
        if P > Len then
          Error('unterminated array');
        if Peek = ',' then
          Inc(P)
        else if Peek <> ']' then
          Error('expected "," or "]" in array');
      until False;
      Inc(P);
    end
    else
      Into.Text := ParseScalar(Into.Kind);
  end;

  procedure AddValue(const Key: string);
  var
    V: TTomlValue;
  begin
    if FValues.IndexOf(Key) >= 0 then
      Error('key "' + Key + '" is defined twice');
    V := TTomlValue.Create;
    try
      ParseValue(V);
    except
      V.Free;
      raise;
    end;
    FValues.AddObject(Key, V);
  end;

  // an inline table on one line: Key = { name = "x", path = "../y" },
  // stored as Key.name and Key.path
  procedure ParseInlineTable(const Key: string);
  var
    Sub: string;
  begin
    Inc(P);
    if FTables.IndexOf(Key) < 0 then
      FTables.Add(Key);
    SkipSpaces;
    if Peek = '}' then
    begin
      Inc(P);
      Exit;
    end;
    repeat
      Sub := Key + '.' + ParseKey;
      if Peek <> '=' then
        Error('expected "=" in inline table');
      Inc(P);
      SkipSpaces;
      if Peek = '{' then
        ParseInlineTable(Sub)
      else
        AddValue(Sub);
      SkipSpaces;
      if Peek = ',' then
        Inc(P)
      else if Peek = '}' then
      begin
        Inc(P);
        Break;
      end
      else
        Error('expected "," or "}" in inline table');
    until False;
  end;

begin
  FValues.Clear;
  FTables.Clear;
  P := 1;
  Len := Length(Src);
  Line := 1;
  Table := '';
  if Copy(Src, 1, 3) = #$EF#$BB#$BF then
    P := 4;
  while P <= Len do
  begin
    SkipSpaces;
    case Peek of
      #0: Break;
      #13: Inc(P);
      #10:
        begin
          Inc(P);
          Inc(Line);
        end;
      '#': SkipComment;
      '[':
        begin
          Inc(P);
          if Peek = '[' then
            Error('arrays of tables ([[...]]) are not supported yet');
          Table := ParseKey;
          if Peek <> ']' then
            Error('expected "]"');
          Inc(P);
          if FTables.IndexOf(Table) >= 0 then
            Error('table [' + Table + '] is defined twice');
          FTables.Add(Table);
          ExpectLineEnd;
        end;
    else
      Key := ParseKey;
      if Peek <> '=' then
        Error('expected "=" after key "' + Key + '"');
      Inc(P);
      SkipSpaces;
      if Table <> '' then
        Key := Table + '.' + Key;
      if Peek = '{' then
        ParseInlineTable(Key)
      else
        AddValue(Key);
      ExpectLineEnd;
    end;
  end;
end;

function TTomlDocument.Has(const Path: string): Boolean;
begin
  Result := (FValues.IndexOf(Path) >= 0) or (FTables.IndexOf(Path) >= 0);
end;

function TTomlDocument.Find(const Path: string): TTomlValue;
var
  I: Integer;
begin
  I := FValues.IndexOf(Path);
  if I >= 0 then
    Result := TTomlValue(FValues.Objects[I])
  else
    Result := nil;
end;

function TTomlDocument.GetString(const Path: string; const Default: string): string;
var
  V: TTomlValue;
begin
  V := Find(Path);
  if V = nil then
    Exit(Default);
  if V.Kind = tkArray then
    raise ETomlError.CreateFmt('"%s" must be a single value, not a list', [Path]);
  Result := V.Text;
end;

function TTomlDocument.GetBool(const Path: string; Default: Boolean): Boolean;
var
  V: TTomlValue;
begin
  V := Find(Path);
  if V = nil then
    Exit(Default);
  if V.Kind <> tkBoolean then
    raise ETomlError.CreateFmt('"%s" must be true or false', [Path]);
  Result := V.Text = 'true';
end;

function TTomlDocument.GetInt(const Path: string; Default: Int64): Int64;
var
  V: TTomlValue;
begin
  V := Find(Path);
  if V = nil then
    Exit(Default);
  if V.Kind <> tkInteger then
    raise ETomlError.CreateFmt('"%s" must be a whole number', [Path]);
  Result := StrToInt64(V.Text);
end;

function TTomlDocument.Keys(const Table: string): TStringArray;
var
  I, J: Integer;
  Prefix, Name: string;
  Seen: TStringList;
begin
  Result := nil;
  if Table = '' then
    Prefix := ''      { the top-level keys and tables }
  else
    Prefix := Table + '.';
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    for I := 0 to FValues.Count + FTables.Count - 1 do
    begin
      if I < FValues.Count then
        Name := FValues[I]
      else
        Name := FTables[I - FValues.Count];
      if Copy(Name, 1, Length(Prefix)) <> Prefix then
        Continue;
      Delete(Name, 1, Length(Prefix));
      J := Pos('.', Name);
      if J > 0 then
        SetLength(Name, J - 1);
      Seen.Add(Name);
    end;
    SetLength(Result, Seen.Count);
    for I := 0 to Seen.Count - 1 do
      Result[I] := Seen[I];
  finally
    Seen.Free;
  end;
end;

function TTomlDocument.GetArray(const Path: string): TStringArray;
var
  V: TTomlValue;
begin
  V := Find(Path);
  if V = nil then
    Exit(nil);
  if V.Kind <> tkArray then
    raise ETomlError.CreateFmt('"%s" must be a list, like ["a", "b"]', [Path]);
  Result := Copy(V.Items);
end;

end.
