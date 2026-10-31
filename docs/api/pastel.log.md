# Pastel.Log

Logging.

    Log.Info('Server started on port %d', [Port]);
    Log.Warn('Disk is %d%% full', [Used]);
    Log.Error(E, 'could not save the order');          // an exception
    Log.Fields(['user', Name, 'ip', IP]).Info('login'); // structured fields
    Log.Debug('only shown with Log.Level := llDebug');

  Output goes to standard error, one line per message:
    2026-10-29 15:04:05.123 INFO  login user=ali ip=10.0.0.5
  Under systemd it switches to the form journald understands (priority
  prefix, no time stamp), so "journalctl -p err" works. Log.Format := lfJson
  writes one JSON object per line for log collectors. Log.ToFile adds a file
  that is rotated by size. Logging is safe from several threads.

`uses Pastel.Log;` · source: [framework/src/pastel.log.pas](../../framework/src/pastel.log.pas)

## Types

### TLogLevel

```pascal
type TLogLevel = (llDebug, llInfo, llWarn, llError, llOff)
```

- `llDebug`
- `llInfo`
- `llWarn`
- `llError`
- `llOff`
### TLogFormat

```pascal
type TLogFormat = (lfAuto, lfText, lfJson, lfJournal)
```

- `lfAuto`
- `lfText`
- `lfJson`
- `lfJournal`
### TLogFields

```pascal
type TLogFields = record
```

Fields to attach to one message: Log.Fields(['user', 'ali']).Info('login')

| | |
|---|---|
| `Logger: TLogger` |  |
| `Items: TStringArray` |  |
| `procedure Debug(const Msg: string)` |  |
| `procedure Info(const Msg: string)` |  |
| `procedure Warn(const Msg: string)` |  |
| `procedure Error(const Msg: string)` |  |

### TLogger

```pascal
type TLogger = class
```

| | |
|---|---|
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure Write(Level: TLogLevel; const Msg: string; const Fields: TStringArray)` |  |
| `function Enabled(Level: TLogLevel): Boolean` |  |
| `procedure Debug(const Msg: string)` |  |
| `procedure Debug(const Fmt: string; const Args: array of const)` |  |
| `procedure Info(const Msg: string)` |  |
| `procedure Info(const Fmt: string; const Args: array of const)` |  |
| `procedure Warn(const Msg: string)` |  |
| `procedure Warn(const Fmt: string; const Args: array of const)` |  |
| `procedure Error(const Msg: string)` |  |
| `procedure Error(const Fmt: string; const Args: array of const)` |  |
| `procedure Error(E: Exception; const What: string = '')` | Logs an exception with its class and message, after What (if given). |
| `function Fields(const NamesAndValues: array of const): TLogFields` | Names and values alternate: ['user', 'ali', 'items', 3]. |
| `procedure ToFile(const FileName: string; MaxMB: Integer = 10; Keep: Integer = 5)` | Also write to a file. When it grows past MaxMB it becomes name.1 (older ones name.2 ... name.Keep), and a new file is started. |
| `procedure SetLevel(const Name: string)` | 'debug', 'info', 'warn'/'warning', 'error', 'off'; raises for others. |
| `property Level: TLogLevel` |  |
| `property Format: TLogFormat` |  |
| `property Console: Boolean` | Write to standard error (default True). |
| `property MaxBytes: Int64` | Size at which the log file is rotated (ToFile sets it from MaxMB). |
| `property OnLine: TLogLineEvent` | Called for every line written (for tests or custom outputs). |

## Other types

| | |
|---|---|
| `type TLogLineEvent = procedure(Level: TLogLevel; Line: string)` |  |

## Routines

### LevelName

```pascal
function LevelName(Level: TLogLevel): string
```

## Constants and variables

| | |
|---|---|
| `var Log: TLogger` | The program's logger. |
