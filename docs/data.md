# JSON, settings and logging

Three units that every service and most tools need:

| Unit | For |
|---|---|
| `Pastel.Json` | Reading and writing JSON, objects to JSON and back |
| `Pastel.Config` | Settings from files, environment variables and code |
| `Pastel.Log` | Log messages to the console, journald, files or log collectors |

## JSON: `Pastel.Json`

### Reading

```pascal
uses Pastel.Json;

var
  Doc: TJSONData;
  Item: TJSONData;
begin
  Doc := ParseJson('{"user": {"name": "Ali", "tags": ["a", "b"]}, "items": [{"id": 1}]}');
  try
    WriteLn(JStr(Doc, 'user.name'));          // Ali
    WriteLn(JStr(Doc, 'user.tags[1]'));       // b
    WriteLn(JInt(Doc, 'items[0].id'));        // 1
    WriteLn(JInt(Doc, 'user.age', 18));       // 18: not in the document
    for Item in JArray(Doc, 'items') do
      WriteLn(JInt(Item, 'id'));
  finally
    Doc.Free;
  end;
end;
```

| | |
|---|---|
| `JStr`, `JInt`, `JFloat`, `JBool` (Data, Path, Default) | A value by path, or the default when it is missing or of another kind. Text like `"12"` or `"yes"` is converted. |
| `JArray(Data, Path)` | The items of an array (they belong to `Data`: do not free them) |
| `JHas(Data, Path)`, `JFind(Data, Path)` | Is it there / the raw `TJSONData` |
| `ParseJson(Text)`, `LoadJsonFile(Name)` | Comments (`//`) and trailing commas are allowed |

A mistake in the text raises `EJsonError` with the line and column: `config.json, line 4, column 12: Unexpected token`.

### Writing

```pascal
Obj := JObject(['name', 'Ayşe', 'age', 28, 'admin', True,
                'tags', JArrayOf(['dev', 'ops']), 'manager', nil]);
WriteLn(ToJson(Obj));          // {"name":"Ayşe","age":28,"admin":true,"tags":["dev","ops"],"manager":null}
WriteLn(ToJson(Obj, True));    // indented
SaveJsonFile('person.json', Obj);
Obj.Free;
```

`JObject` takes names and values in turn. Values can be text, numbers, booleans, `nil` (null), and other `TJSONData` (which `JObject` then owns).

### Objects

Classes with published properties convert in both directions:

```pascal
type
  TPerson = class(TPersistent)
  published
    property Name: string ...;
    property Age: Integer ...;
    property Tags: TStrings ...;
  end;

Text := ObjectToJson(Person);           // {"Age":28,"Name":"Ayşe","Tags":["dev"]}
JsonToObject('{"name": "Veli", "age": 40}', Person);   // names match without case
```

The types are Free Pascal's own `TJSONData`, `TJSONObject` and `TJSONArray` from fpjson, so everything fpjson offers works too.

## Settings: `Pastel.Config`

```pascal
uses Pastel.Config;

Config := TConfig.Create('myapp');
Config.SetDefault('server.port', '8080');
Config.LoadStandard;
Port := Config.GetInt('server.port');
DbHost := Config.Get('database.host', 'localhost');
DbPass := Config.Require('database.password');
```

with a `config.toml` like:

```toml
[server]
port = 9000

[database]
host = "db.internal"
password = "s3cret"
```

### Where settings come from

The later source wins:

1. `SetDefault` in code
2. the system file: `/etc/myapp/config.toml` (Windows: `%ProgramData%\myapp\config.toml`)
3. the user's file: `~/.config/myapp/config.toml` (Windows: `%APPDATA%\myapp\config.toml`)
4. `./config.toml` (or `config.json`) in the current folder
5. environment variables: `MYAPP_SERVER_PORT` for `server.port`, `MYAPP_DATABASE_PASSWORD` for `database.password`
6. `SetValue` in code, for example from a command-line option

`LoadStandard` loads 2–5. For other set-ups use `LoadFile`, `LoadFileIfExists` and `LoadEnv(Prefix)` in the order you want. Files can be TOML or JSON.

Environment variables are the usual way to give secrets to a service (systemd `Environment=`, Docker `-e`), so they never have to be written in a file.

### Reading

| | |
|---|---|
| `Get(Key, Default)` | Text |
| `GetInt`, `GetFloat`, `GetBool` | Typed values; `GetBool` accepts true/false, yes/no, on/off, 1/0 |
| `GetList(Key)` | A TOML/JSON array, or comma-separated text (`MYAPP_ADMINS="ali, ayşe"`) |
| `Has(Key)` | Is it set anywhere? |
| `Require(Key)` | The value, or an error that says how to set it |
| `Source(Key)` | Where the value came from |
| `Files` | The files that were loaded |

Errors say exactly what is wrong and where:

```
/etc/myapp/config.toml, line 3: invalid value "localhost" (strings need quotes)
setting "server.port" must be a whole number, got "eighty" (from ./config.toml)
missing setting "database.password": add [database] password = ... to config.toml, or set MYAPP_DATABASE_PASSWORD
```

## Logging: `Pastel.Log`

```pascal
uses Pastel.Log;

Log.Info('Server started on port %d', [Port]);
Log.Warn('Disk is %d%% full', [Used]);
Log.Debug('Request body: %s', [Body]);              // hidden unless the level is debug
Log.Fields(['user', Name, 'ip', IP]).Info('login');
try
  SaveOrder(Order);
except
  on E: Exception do
    Log.Error(E, 'could not save the order');
end;
```

Messages go to standard error:

```
2026-10-29 15:04:05.123 INFO  Server started on port 8080
2026-10-29 15:04:09.871 INFO  login user=ali ip=10.0.0.5
2026-10-29 15:04:12.002 ERROR could not save the order: disk not ready error=EInOutError
```

### Level

`Log.Level := llDebug` (or `llInfo`, the default, `llWarn`, `llError`, `llOff`). `Log.SetLevel('debug')` takes the name, handy with a setting or option. Every Pastel program also reads the environment variable `LOG_LEVEL`: `LOG_LEVEL=debug ./myapp`.

### Formats

| `Log.Format` | |
|---|---|
| `lfAuto` (default) | Text in a terminal; journald format when the program runs under systemd |
| `lfText` | `time LEVEL message name=value` |
| `lfJournal` | `<3>message` with the syslog priority, no time (journald adds it) |
| `lfJson` | One JSON object per line: `{"time":"...Z","level":"info","msg":"...","user":"ali"}` |

With the journald format, `journalctl -u myapp -p err` shows only errors.

### Files

```pascal
Log.ToFile('/var/log/myapp/app.log', 10, 5);   // rotate at 10 MB, keep 5 old files
Log.Console := False;                           // only the file
```

Old files are named `app.log.1` (newest) to `app.log.5`. Under systemd, logging to the journal is usually all you need.

### Threads

Logging is safe from several threads at once; lines are never mixed.
