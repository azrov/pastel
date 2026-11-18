# Pastel.Toml

A small TOML reader for pastel.toml files.

  Supported: [tables], dotted keys, basic and literal strings, integers,
  floats, booleans, arrays of scalars (also across lines), inline tables
  (on one line, in curly brackets), comments.
  Not supported yet: multi-line strings, dates, [[arrays of tables]].

`uses Pastel.Toml;` · source: [framework/src/pastel.toml.pas](../../framework/src/pastel.toml.pas)

## Types

### ETomlError

```pascal
type ETomlError = class(Exception)
```

### TTomlKind

```pascal
type TTomlKind = (tkString, tkInteger, tkFloat, tkBoolean, tkArray)
```

- `tkString`
- `tkInteger`
- `tkFloat`
- `tkBoolean`
- `tkArray`
### TTomlValue

```pascal
type TTomlValue = class
```

### TTomlDocument

```pascal
type TTomlDocument = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure LoadFromString(const Src: string)` |  |
| `procedure LoadFromFile(const FileName: string)` |  |
| `function Has(const Path: string): Boolean` |  |
| `function Find(const Path: string): TTomlValue` |  |
| `function GetString(const Path: string; const Default: string = ''): string` |  |
| `function GetBool(const Path: string; Default: Boolean = False): Boolean` |  |
| `function GetInt(const Path: string; Default: Int64 = 0): Int64` |  |
| `function GetArray(const Path: string): TStringArray` |  |
| `function Keys(const Table: string): TStringArray` | Names directly inside a table: Keys('dependencies') -> ['json', 'utils'] |
| `property Values: TStringList` |  |

## Routines

### CodePointToUTF8

```pascal
function CodePointToUTF8(CP: Cardinal): string
```

