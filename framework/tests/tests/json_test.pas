unit Json_Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Json;

type
  TPerson = class(TPersistent)
  private
    FName: string;
    FAge: Integer;
    FAdmin: Boolean;
    FTags: TStrings;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Name: string read FName write FName;
    property Age: Integer read FAge write FAge;
    property Admin: Boolean read FAdmin write FAdmin;
    property Tags: TStrings read FTags write FTags;
  end;

  TJsonTests = class(TTestSuite)
  private
    FDoc: TJSONData;
    procedure ParseBroken;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ReadsWithPaths;
    procedure MissingValuesGiveDefaults;
    procedure ReadsArrays;
    procedure ConvertsLooseTypes;
    procedure BrokenJsonSaysWhere;
    procedure CommentsAndTrailingCommasAreAllowed;
    procedure BuildsObjectsAndArrays;
    procedure WritesPrettyJson;
    procedure KeepsUnicode;
    procedure ObjectToJsonAndBack;
    procedure SavesAndLoadsFiles;
  end;

implementation

constructor TPerson.Create;
begin
  inherited Create;
  FTags := TStringList.Create;
end;

destructor TPerson.Destroy;
begin
  FTags.Free;
  inherited Destroy;
end;

procedure TJsonTests.SetUp;
begin
  FDoc := ParseJson('{"user": {"name": "Ali", "age": 30, "tags": ["a", "b"], ' +
    '"address": {"city": "Bakı"}}, "items": [{"id": 1}, {"id": 2}], "ok": true, ' +
    '"pi": 3.14, "count": "12", "flag": "yes", "nothing": null}');
end;

procedure TJsonTests.TearDown;
begin
  FDoc.Free;
end;

procedure TJsonTests.ReadsWithPaths;
begin
  AssertEquals('Ali', JStr(FDoc, 'user.name'));
  AssertEquals(30, JInt(FDoc, 'user.age'));
  AssertEquals('Bakı', JStr(FDoc, 'user.address.city'));
  AssertEquals('b', JStr(FDoc, 'user.tags[1]'));
  AssertEquals(2, JInt(FDoc, 'items[1].id'));
  AssertTrue(JBool(FDoc, 'ok'));
  AssertEquals(3.14, JFloat(FDoc, 'pi'), 1E-9);
  AssertTrue(JHas(FDoc, 'user.tags'));
end;

procedure TJsonTests.MissingValuesGiveDefaults;
begin
  AssertEquals('?', JStr(FDoc, 'user.email', '?'));
  AssertEquals(-1, JInt(FDoc, 'items[9].id', -1));
  AssertEquals('', JStr(FDoc, 'nothing'));
  AssertEquals('x', JStr(FDoc, 'user', 'x'), 'an object is not a string');
  AssertFalse(JHas(FDoc, 'user.name.first'));
  AssertNil(JFind(FDoc, 'items[x]'));
end;

procedure TJsonTests.ReadsArrays;
var
  Items: TJsonItems;
begin
  Items := JArray(FDoc, 'items');
  AssertEquals(2, Length(Items));
  AssertEquals(1, JInt(Items[0], 'id'));
  AssertEquals(0, Length(JArray(FDoc, 'missing')));
end;

procedure TJsonTests.ConvertsLooseTypes;
begin
  AssertEquals(12, JInt(FDoc, 'count'), 'number in a string');
  AssertTrue(JBool(FDoc, 'flag'), '"yes" is true');
  AssertEquals('30', JStr(FDoc, 'user.age'), 'number as text');
end;

procedure TJsonTests.ParseBroken;
begin
  ParseJson('{"a": 1,' + LineEnding + '  "b": }').Free;
end;

procedure TJsonTests.BrokenJsonSaysWhere;
begin
  AssertRaises(EJsonError, @ParseBroken);
  try
    ParseBroken;
  except
    on E: EJsonError do
    begin
      AssertEquals(2, E.Line);
      AssertStartsWith('line 2, column', E.Message);
    end;
  end;
end;

procedure TJsonTests.CommentsAndTrailingCommasAreAllowed;
var
  D: TJSONData;
begin
  D := ParseJson('{ // settings' + LineEnding + '"a": [1, 2,], }');
  try
    AssertEquals(2, JInt(D, 'a[1]'));
  finally
    D.Free;
  end;
end;

procedure TJsonTests.BuildsObjectsAndArrays;
var
  O: TJSONObject;
begin
  O := JObject(['name', 'Ali', 'age', 30, 'admin', True, 'note', nil,
    'tags', JArrayOf(['x', 1, 2.5]), 'address', JObject(['city', 'Gəncə'])]);
  try
    AssertEquals('{"name":"Ali","age":30,"admin":true,"note":null,"tags":["x",1,2.5],' +
      '"address":{"city":"Gəncə"}}', ToJson(O));
  finally
    O.Free;
  end;
end;

procedure TJsonTests.WritesPrettyJson;
var
  O: TJSONObject;
begin
  O := JObject(['a', 1, 'b', JArrayOf([true])]);
  try
    AssertEquals('{' + LineEnding + '  "a" : 1,' + LineEnding + '  "b" : [' + LineEnding +
      '    true' + LineEnding + '  ]' + LineEnding + '}', ToJson(O, True));
  finally
    O.Free;
  end;
end;

procedure TJsonTests.KeepsUnicode;
var
  D: TJSONData;
begin
  D := ParseJson('{"s": "şğ and ü"}');
  try
    AssertEquals('şğ and ü', JStr(D, 's'));
  finally
    D.Free;
  end;
  AssertEquals('"a\"b\\c\n"', JsonQuote('a"b\c' + #10));
end;

procedure TJsonTests.ObjectToJsonAndBack;
var
  P, Q: TPerson;
  Text: string;
begin
  P := TPerson.Create;
  Q := TPerson.Create;
  try
    P.Name := 'Ayşe';
    P.Age := 28;
    P.Admin := True;
    P.Tags.Add('dev');
    Text := ObjectToJson(P);
    { properties come in alphabetical order }
    AssertEquals('{"Admin":true,"Age":28,"Name":"Ayşe","Tags":["dev"]}', Text);
    JsonToObject('{"name": "Veli", "age": 40, "tags": ["a", "b"]}', Q);
    AssertEquals('Veli', Q.Name, 'names are matched without case');
    AssertEquals(40, Q.Age);
    AssertEquals(2, Q.Tags.Count);
  finally
    P.Free;
    Q.Free;
  end;
end;

procedure TJsonTests.SavesAndLoadsFiles;
var
  F: string;
  D: TJSONData;
begin
  F := GetTempDir + 'pastel-json-test' + PathDelim + 'data.json';
  SaveJsonFile(F, FDoc);
  D := LoadJsonFile(F);
  try
    AssertEquals('Bakı', JStr(D, 'user.address.city'));
  finally
    D.Free;
    DeleteFile(F);
    RemoveDir(ExtractFileDir(F));
  end;
end;

initialization
  RegisterTests(TJsonTests);
end.
