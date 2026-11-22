(* Pastel - JSON made easy, on top of Free Pascal's fpjson.

  Reading:
    Doc := ParseJson('{"user": {"name": "Ali", "tags": ["a", "b"]}}');
    try
      Name := JStr(Doc, 'user.name');           // 'Ali'
      Age  := JInt(Doc, 'user.age', 0);          // 0: not there
      Tag  := JStr(Doc, 'user.tags[1]');         // 'b'
      for Item in JArray(Doc, 'user.tags') do ...
    finally
      Doc.Free;
    end;

  Writing:
    Obj := JObject(['name', 'Ali', 'age', 30, 'admin', True]);
    WriteLn(ToJson(Obj));              // {"name":"Ali","age":30,"admin":true}
    WriteLn(ToJson(Obj, True));        // indented

  Objects with published properties convert both ways:
    Text := ObjectToJson(Person);
    JsonToObject(Text, Person);

  The JSON types (TJSONData, TJSONObject, TJSONArray) are fpjson's, so all
  of fpjson can be used as well.
  Part of the Pastel project, MIT License. *)
unit Pastel.Json;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson;

type
  TJSONData = fpjson.TJSONData;
  TJSONObject = fpjson.TJSONObject;
  TJSONArray = fpjson.TJSONArray;
  TJSONType = fpjson.TJSONtype;

  { Bad JSON text. Line and Column say where (1-based, 0 if unknown). }
  EJsonError = class(Exception)
  public
    Line, Column: Integer;
  end;

  TJsonItems = array of TJSONData;

{ Parses JSON text; comments and trailing commas are allowed.
  Raises EJsonError with the line and column of a mistake. The caller frees
  the result. }
function ParseJson(const Text: string): TJSONData;
function ParseJsonObject(const Text: string): TJSONObject;
function LoadJsonFile(const FileName: string): TJSONData;
procedure SaveJsonFile(const FileName: string; Data: TJSONData; Pretty: Boolean = True);

{ Compact or indented (2 spaces) text. }
function ToJson(Data: TJSONData; Pretty: Boolean = False): string;

{ ---- reading with a path: 'user.name', 'items[0].id', '[2]' ----
  These never raise for a missing value: they return the default. }
function JFind(Data: TJSONData; const Path: string): TJSONData;
function JHas(Data: TJSONData; const Path: string): Boolean;
function JStr(Data: TJSONData; const Path: string; const Default: string = ''): string;
function JInt(Data: TJSONData; const Path: string; Default: Int64 = 0): Int64;
function JFloat(Data: TJSONData; const Path: string; Default: Double = 0): Double;
function JBool(Data: TJSONData; const Path: string; Default: Boolean = False): Boolean;
{ The items of an array (or the values of an object); empty if missing.
  The items belong to Data: do not free them. }
function JArray(Data: TJSONData; const Path: string): TJsonItems;

{ ---- building ---- }
{ JObject(['name', 'Ali', 'age', 30]): names and values alternate. Values can
  be strings, numbers, booleans, nil (null) or TJSONData (taken over). }
function JObject(const NamesAndValues: array of const): TJSONObject;
function JArrayOf(const Values: array of const): TJSONArray;

{ ---- objects <-> JSON through published properties ---- }
function ObjectToJson(Obj: TObject; Pretty: Boolean = False): string;
function ObjectToJsonData(Obj: TObject): TJSONObject;
procedure JsonToObject(const Text: string; Obj: TObject);
procedure JsonDataToObject(Data: TJSONObject; Obj: TObject);

{ A string as a JSON string literal, with quotes. }
function JsonQuote(const S: string): string;

implementation

uses
  jsonparser, jsonscanner, fpjsonrtti;

type
  { Numbers like 2.5 are written as 2.5, not 2.5000000000000000E+000. }
  TPastelJSONFloat = class(TJSONFloatNumber)
  protected
    function GetAsString: TJSONStringType; override;
  end;

function TPastelJSONFloat.GetAsString: TJSONStringType;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  Result := FloatToStrF(AsFloat, ffGeneral, 15, 0, FS);
  { keep it a number in JSON: no thousands, an exponent like 1E20 is fine }
end;

function JsonQuote(const S: string): string;
begin
  Result := '"' + StringToJSONString(S) + '"';
end;

function ParseJson(const Text: string): TJSONData;
var
  Parser: TJSONParser;
  Msg: string;
  E: EJsonError;
  P1, P2: Integer;
begin
  Parser := TJSONParser.Create(Text, [joUTF8, joComments, joIgnoreTrailingComma]);
  try
    try
      Result := Parser.Parse;
    except
      on X: EJSONParser do
      begin
        { fpjson: "Error at line 3, Pos 7:Unexpected token" }
        Msg := X.Message;
        E := EJsonError.Create('');
        P1 := Pos('line ', Msg);
        P2 := Pos(', Pos ', Msg);
        if (P1 > 0) and (P2 > P1) then
        begin
          E.Line := StrToIntDef(Copy(Msg, P1 + 5, P2 - P1 - 5), 0);
          E.Column := StrToIntDef(Copy(Msg, P2 + 6, Pos(':', Copy(Msg, P2, MaxInt)) - 7), 0);
          Msg := Trim(Copy(Msg, Pos(':', Copy(Msg, P2, MaxInt)) + P2, MaxInt));
        end;
        if E.Line > 0 then
          E.Message := Format('line %d, column %d: %s', [E.Line, E.Column, Msg])
        else
          E.Message := Msg;
        raise E;
      end;
    end;
    if Result = nil then
      raise EJsonError.Create('no JSON value found (the text is empty)');
  finally
    Parser.Free;
  end;
end;

function ParseJsonObject(const Text: string): TJSONObject;
var
  D: TJSONData;
begin
  D := ParseJson(Text);
  if not (D is TJSONObject) then
  begin
    D.Free;
    raise EJsonError.Create('expected a JSON object { ... }');
  end;
  Result := TJSONObject(D);
end;

function ReadFileText(const FileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
  if Copy(Result, 1, 3) = #$EF#$BB#$BF then
    Delete(Result, 1, 3);
end;

function LoadJsonFile(const FileName: string): TJSONData;
begin
  try
    Result := ParseJson(ReadFileText(FileName));
  except
    on E: EJsonError do
    begin
      E.Message := FileName + ', ' + E.Message;
      raise;
    end;
  end;
end;

procedure SaveJsonFile(const FileName: string; Data: TJSONData; Pretty: Boolean);
var
  S: string;
  F: TFileStream;
begin
  S := ToJson(Data, Pretty) + LineEnding;
  ForceDirectories(ExtractFileDir(ExpandFileName(FileName)));
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
end;

function ToJson(Data: TJSONData; Pretty: Boolean): string;
begin
  if Data = nil then
    Exit('null');
  if Pretty then
    Result := Data.FormatJSON([], 2)
  else
    Result := Data.FormatJSON([foSingleLineArray, foSingleLineObject, foSkipWhiteSpace], 0);
end;

{ ---- paths ---- }

function JFind(Data: TJSONData; const Path: string): TJSONData;
var
  I, N, Index: Integer;
  Name: string;
begin
  Result := Data;
  I := 1;
  N := Length(Path);
  while (Result <> nil) and (I <= N) do
  begin
    if Path[I] = '.' then
    begin
      Inc(I);
      Continue;
    end;
    if Path[I] = '[' then
    begin
      Inc(I);
      Name := '';
      while (I <= N) and (Path[I] <> ']') do
      begin
        Name := Name + Path[I];
        Inc(I);
      end;
      Inc(I);
      if not (Result is TJSONArray) or not TryStrToInt(Trim(Name), Index) or
         (Index < 0) or (Index >= Result.Count) then
        Exit(nil);
      Result := TJSONArray(Result).Items[Index];
      Continue;
    end;
    Name := '';
    while (I <= N) and not (Path[I] in ['.', '[']) do
    begin
      Name := Name + Path[I];
      Inc(I);
    end;
    if not (Result is TJSONObject) then
      Exit(nil);
    Result := TJSONObject(Result).Find(Name);
  end;
end;

function JHas(Data: TJSONData; const Path: string): Boolean;
begin
  Result := JFind(Data, Path) <> nil;
end;

function JStr(Data: TJSONData; const Path, Default: string): string;
var
  D: TJSONData;
begin
  D := JFind(Data, Path);
  if (D = nil) or (D.JSONType in [jtNull, jtArray, jtObject]) then
    Exit(Default);
  Result := D.AsString;
end;

function JInt(Data: TJSONData; const Path: string; Default: Int64): Int64;
var
  D: TJSONData;
begin
  D := JFind(Data, Path);
  if D = nil then
    Exit(Default);
  case D.JSONType of
    jtNumber: Result := D.AsInt64;
    jtString: if not TryStrToInt64(D.AsString, Result) then Result := Default;
    jtBoolean: Result := Ord(D.AsBoolean);
  else
    Result := Default;
  end;
end;

function JFloat(Data: TJSONData; const Path: string; Default: Double): Double;
var
  D: TJSONData;
  FS: TFormatSettings;
begin
  D := JFind(Data, Path);
  if D = nil then
    Exit(Default);
  case D.JSONType of
    jtNumber: Result := D.AsFloat;
    jtString:
      begin
        FS := DefaultFormatSettings;
        FS.DecimalSeparator := '.';
        if not TryStrToFloat(D.AsString, Result, FS) then
          Result := Default;
      end;
  else
    Result := Default;
  end;
end;

function JBool(Data: TJSONData; const Path: string; Default: Boolean): Boolean;
var
  D: TJSONData;
  S: string;
begin
  D := JFind(Data, Path);
  if D = nil then
    Exit(Default);
  case D.JSONType of
    jtBoolean: Result := D.AsBoolean;
    jtNumber: Result := D.AsInt64 <> 0;
    jtString:
      begin
        S := LowerCase(D.AsString);
        if (S = 'true') or (S = 'yes') or (S = '1') or (S = 'on') then Result := True
        else if (S = 'false') or (S = 'no') or (S = '0') or (S = 'off') then Result := False
        else Result := Default;
      end;
  else
    Result := Default;
  end;
end;

function JArray(Data: TJSONData; const Path: string): TJsonItems;
var
  D: TJSONData;
  I: Integer;
begin
  Result := nil;
  D := JFind(Data, Path);
  if (D = nil) or not (D.JSONType in [jtArray, jtObject]) then
    Exit;
  SetLength(Result, D.Count);
  for I := 0 to D.Count - 1 do
    Result[I] := D.Items[I];
end;

{ ---- building ---- }

function ValueOf(const V: TVarRec): TJSONData;
begin
  case V.VType of
    vtInteger: Result := TJSONIntegerNumber.Create(V.VInteger);
    vtInt64: Result := TJSONInt64Number.Create(V.VInt64^);
    vtQWord: Result := TJSONQWordNumber.Create(V.VQWord^);
    vtBoolean: Result := TJSONBoolean.Create(V.VBoolean);
    vtExtended: Result := TPastelJSONFloat.Create(V.VExtended^);
    vtCurrency: Result := TPastelJSONFloat.Create(V.VCurrency^);
    vtString: Result := TJSONString.Create(V.VString^);
    vtAnsiString: Result := TJSONString.Create(AnsiString(V.VAnsiString));
    vtUnicodeString: Result := TJSONString.Create(UTF8Encode(UnicodeString(V.VUnicodeString)));
    vtWideString: Result := TJSONString.Create(UTF8Encode(WideString(V.VWideString)));
    vtChar: Result := TJSONString.Create(V.VChar);
    vtWideChar: Result := TJSONString.Create(UTF8Encode(WideString(V.VWideChar)));
    vtPChar: Result := TJSONString.Create(StrPas(V.VPChar));
    vtPointer:
      if V.VPointer = nil then
        Result := TJSONNull.Create
      else
        raise EJsonError.Create('pointers cannot be turned into JSON');
    vtObject:
      if V.VObject = nil then
        Result := TJSONNull.Create
      else if V.VObject is TJSONData then
        Result := TJSONData(V.VObject)
      else
        Result := ObjectToJsonData(V.VObject);
  else
    raise EJsonError.CreateFmt('this kind of value cannot be turned into JSON (type %d)', [V.VType]);
  end;
end;

function NameOf(const V: TVarRec): string;
begin
  case V.VType of
    vtString: Result := V.VString^;
    vtAnsiString: Result := AnsiString(V.VAnsiString);
    vtUnicodeString: Result := UTF8Encode(UnicodeString(V.VUnicodeString));
    vtChar: Result := V.VChar;
    vtPChar: Result := StrPas(V.VPChar);
  else
    raise EJsonError.Create('JObject: names must be text, as in JObject([''name'', value, ...])');
  end;
end;

function JObject(const NamesAndValues: array of const): TJSONObject;
var
  I: Integer;
begin
  if Odd(Length(NamesAndValues)) then
    raise EJsonError.Create('JObject needs pairs: a name and a value each');
  Result := TJSONObject.Create;
  try
    I := 0;
    while I < High(NamesAndValues) do
    begin
      Result.Add(NameOf(NamesAndValues[I]), ValueOf(NamesAndValues[I + 1]));
      Inc(I, 2);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function JArrayOf(const Values: array of const): TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  try
    for I := 0 to High(Values) do
      Result.Add(ValueOf(Values[I]));
  except
    Result.Free;
    raise;
  end;
end;

{ ---- objects ---- }

function ObjectToJsonData(Obj: TObject): TJSONObject;
var
  S: TJSONStreamer;
begin
  S := TJSONStreamer.Create(nil);
  try
    S.Options := [jsoTStringsAsArray, jsoDateTimeAsString];
    Result := S.ObjectToJSON(Obj);
  finally
    S.Free;
  end;
end;

function ObjectToJson(Obj: TObject; Pretty: Boolean): string;
var
  D: TJSONObject;
begin
  D := ObjectToJsonData(Obj);
  try
    Result := ToJson(D, Pretty);
  finally
    D.Free;
  end;
end;

procedure JsonDataToObject(Data: TJSONObject; Obj: TObject);
var
  S: TJSONDeStreamer;
begin
  S := TJSONDeStreamer.Create(nil);
  try
    S.Options := [jdoCaseInsensitive, jdoIgnoreNulls];
    S.JSONToObject(Data, Obj);
  finally
    S.Free;
  end;
end;

procedure JsonToObject(const Text: string; Obj: TObject);
var
  D: TJSONObject;
begin
  D := ParseJsonObject(Text);
  try
    JsonDataToObject(D, Obj);
  finally
    D.Free;
  end;
end;

initialization
  SetJSONInstanceType(jitNumberFloat, TPastelJSONFloat);

end.
