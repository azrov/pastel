# Pastel.Config

Settings from files, environment variables and code.

    Config := TConfig.Create('myapp');
    Config.SetDefault('server.port', '8080');
    Config.LoadStandard;                 // see below
    Port := Config.GetInt('server.port');
    Host := Config.Get('database.host', 'localhost');
    Pass := Config.Require('database.password');   // clear error if missing

  A setting can come from several places; the later one wins:
    1. SetDefault in code
    2. /etc/myapp/config.toml          (Linux; on Windows %ProgramData%\myapp)
    3. ~/.config/myapp/config.toml     (the user's own settings)
    4. ./config.toml                   (next to where the program runs)
    5. environment: MYAPP_SERVER_PORT for server.port
    6. Config.SetValue in code, e.g. from a command-line option
  LoadStandard loads 2-5; LoadFile and LoadEnv do it step by step.
  Files can be TOML or JSON. Config.Source('server.port') tells where a
  value came from, which helps when something is not what you expect.

`uses Pastel.Config;` · source: [framework/src/pastel.config.pas](../../framework/src/pastel.config.pas)

## Types

### EConfigError

```pascal
type EConfigError = class(Exception)
```

### TConfig

```pascal
type TConfig = class
```

| | |
|---|---|
| `constructor Create(const AAppName: string = '')` |  |
| `destructor Destroy` |  |
| `procedure SetDefault(const Key: string; const Value: string)` |  |
| `procedure SetValue(const Key: string; const Value: string)` | Highest priority: for values from the command line. |
| `procedure LoadFile(const FileName: string)` | Loads a .toml or .json file. Raises EConfigError (with file and line) for mistakes, and when the file does not exist. |
| `function LoadFileIfExists(const FileName: string): Boolean` | Same, but a missing file is fine. Returns True if it was loaded. |
| `procedure LoadEnv(const Prefix: string = '')` | Settings from environment variables PREFIX_SECTION_KEY. Default prefix: the app name in capitals, with - turned into _. |
| `procedure LoadStandard` | System file, user file, ./config.toml (or .json), then the environment. |
| `function Has(const Key: string): Boolean` |  |
| `function Get(const Key: string; const Default: string = ''): string` |  |
| `function GetInt(const Key: string; Default: Int64 = 0): Int64` |  |
| `function GetFloat(const Key: string; Default: Double = 0): Double` |  |
| `function GetBool(const Key: string; Default: Boolean = False): Boolean` |  |
| `function GetList(const Key: string): TStringArray` | A list: a TOML/JSON array, or comma-separated text (handy in environment variables). |
| `function Require(const Key: string): string` | The value, or an EConfigError explaining how to set it. |
| `function Source(const Key: string): string` | Where the value came from: a file name, 'environment NAME', 'default' or 'set in code'. |
| `function Keys: TStringArray` | All known keys (from files and defaults), sorted. |
| `property Files: TStringList` | Files that were loaded, in order. |
| `property AppName: string` |  |

## Routines

### SystemConfigDir

```pascal
function SystemConfigDir(const AppName: string): string
```

Standard folders for an app's settings on this system.

### UserConfigDir

```pascal
function UserConfigDir(const AppName: string): string
```

