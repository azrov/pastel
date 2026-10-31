# Pastel.Json

JSON made easy, on top of Free Pascal's fpjson.

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

`uses Pastel.Json;` · source: [framework/src/pastel.json.pas](../../framework/src/pastel.json.pas)

**Contents:** [EJsonError](#ejsonerror) · [ParseJson](#parsejson) · [ParseJsonObject](#parsejsonobject) · [LoadJsonFile](#loadjsonfile) · [SaveJsonFile](#savejsonfile) · [ToJson](#tojson) · [JFind](#jfind) · [JHas](#jhas) · [JStr](#jstr) · [JInt](#jint) · [JFloat](#jfloat) · [JBool](#jbool) · [JArray](#jarray) · [JObject](#jobject) · [JArrayOf](#jarrayof) · [ObjectToJson](#objecttojson) · [ObjectToJsonData](#objecttojsondata) · [JsonToObject](#jsontoobject) · [JsonDataToObject](#jsondatatoobject) · [JsonQuote](#jsonquote)

## Types

### EJsonError

```pascal
type EJsonError = class(Exception)
```

Bad JSON text. Line and Column say where (1-based, 0 if unknown).

## Other types

| | |
|---|---|
| `type TJSONData = fpjson.TJSONData` |  |
| `type TJSONObject = fpjson.TJSONObject` |  |
| `type TJSONArray = fpjson.TJSONArray` |  |
| `type TJSONType = fpjson.TJSONtype` |  |
| `type TJsonItems = array of TJSONData` |  |

## Routines

### ParseJson

```pascal
function ParseJson(const Text: string): TJSONData
```

Parses JSON text; comments and trailing commas are allowed.
Raises EJsonError with the line and column of a mistake. The caller frees
the result.

### ParseJsonObject

```pascal
function ParseJsonObject(const Text: string): TJSONObject
```

### LoadJsonFile

```pascal
function LoadJsonFile(const FileName: string): TJSONData
```

### SaveJsonFile

```pascal
procedure SaveJsonFile(const FileName: string; Data: TJSONData; Pretty: Boolean = True)
```

### ToJson

```pascal
function ToJson(Data: TJSONData; Pretty: Boolean = False): string
```

Compact or indented (2 spaces) text.

### JFind

```pascal
function JFind(Data: TJSONData; const Path: string): TJSONData
```

### JHas

```pascal
function JHas(Data: TJSONData; const Path: string): Boolean
```

### JStr

```pascal
function JStr(Data: TJSONData; const Path: string; const Default: string = ''): string
```

### JInt

```pascal
function JInt(Data: TJSONData; const Path: string; Default: Int64 = 0): Int64
```

### JFloat

```pascal
function JFloat(Data: TJSONData; const Path: string; Default: Double = 0): Double
```

### JBool

```pascal
function JBool(Data: TJSONData; const Path: string; Default: Boolean = False): Boolean
```

### JArray

```pascal
function JArray(Data: TJSONData; const Path: string): TJsonItems
```

The items of an array (or the values of an object); empty if missing.
The items belong to Data: do not free them.

### JObject

```pascal
function JObject(const NamesAndValues: array of const): TJSONObject
```

### JArrayOf

```pascal
function JArrayOf(const Values: array of const): TJSONArray
```

### ObjectToJson

```pascal
function ObjectToJson(Obj: TObject; Pretty: Boolean = False): string
```

### ObjectToJsonData

```pascal
function ObjectToJsonData(Obj: TObject): TJSONObject
```

### JsonToObject

```pascal
procedure JsonToObject(const Text: string; Obj: TObject)
```

### JsonDataToObject

```pascal
procedure JsonDataToObject(Data: TJSONObject; Obj: TObject)
```

### JsonQuote

```pascal
function JsonQuote(const S: string): string
```

A string as a JSON string literal, with quotes.

