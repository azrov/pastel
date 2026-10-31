# Pastel.Args

Command-line arguments.

    Args := TArgs.Create('backup', 'Copies folders into an archive.');
    Args.Version := '1.2.0';
    Args.Flag('verbose', 'v', 'Show every file');
    Args.Option('output', 'o', 'Archive to write', 'backup.tar');
    Args.Option('level', 'l', 'Compression level').IntRange(1, 9).Default('6');
    Args.Positional('folders', 'Folders to back up').Many;
    Args.Parse;          // prints help or errors and exits when needed

    if Args.Has('verbose') then ...
    Level := Args.GetInt('level');
    for F in Args.GetAll('folders') do ...

  Sub-commands ("todo add", "todo list") have their own options:

    with Args.Command('add', 'Add a task') do
      Positional('title', 'What to do');
    Args.Parse;
    case Args.CommandName of
      'add': AddTask(Args.Get('title'));

  --help, --version and --no-color are added automatically.

`uses Pastel.Args;` · source: [framework/src/pastel.args.pas](../../framework/src/pastel.args.pas)

**Contents:** [EArgsError](#eargserror) · [TArgKind](#targkind) · [TArgDef](#targdef) · [TArgCommand](#targcommand) · [TArgs](#targs) · [Levenshtein](#levenshtein) · [CommandLineWords](#commandlinewords)

## Types

### EArgsError

```pascal
type EArgsError = class(Exception)
```

### TArgKind

```pascal
type TArgKind = (akFlag, akOption, akPositional)
```

- `akFlag`
- `akOption`
- `akPositional`
### TArgDef

```pascal
type TArgDef = class
```

One flag, option or positional argument. Its setup methods return the
argument itself, so they can be chained.

| | |
|---|---|
| `constructor Create(AKind: TArgKind; const AName: string; const AShort: string; const AHelp: string)` |  |
| `destructor Destroy` |  |
| `function Default(const AValue: string): TArgDef` |  |
| `function Required: TArgDef` |  |
| `function Optional: TArgDef` |  |
| `function Many: TArgDef` | May be given more than once (options) or take all remaining words (positional). |
| `function IsInteger: TArgDef` |  |
| `function IntRange(AMin: Int64; AMax: Int64): TArgDef` |  |
| `function Choices(const AValues: array of string): TArgDef` |  |
| `function Env(const AVariable: string): TArgDef` | Value taken from this environment variable when not given on the command line. |
| `function MetaVar(const AValue: string): TArgDef` | Placeholder in the help, e.g. FILE in "--output FILE". |
| `property Name: string` |  |
| `property Kind: TArgKind` |  |

### TArgCommand

```pascal
type TArgCommand = class
```

| | |
|---|---|
| `constructor Create(const AName: string; const ADescription: string)` |  |
| `destructor Destroy` |  |
| `function Flag(const AName: string; const AShort: string; const AHelp: string): TArgDef` |  |
| `function Option(const AName: string; const AShort: string; const AHelp: string; const ADefault: string = ''): TArgDef` |  |
| `function Positional(const AName: string; const AHelp: string): TArgDef` | Required unless Optional or a Default is set. |
| `function Command(const AName: string; const ADescription: string): TArgCommand` |  |
| `procedure Example(const Line: string)` |  |
| `function HelpText: string` |  |
| `property Name: string` |  |
| `property Description: string` |  |

### TArgs

```pascal
type TArgs = class(TArgCommand)
```

| | |
|---|---|
| `constructor Create(const AProgram: string; const ADescription: string)` |  |
| `procedure ParseFrom(const Words: array of string)` | Parses the given words. Raises EArgsError with a message for the user. |
| `procedure Parse` | Parses the program's command line. Prints help, the version or an error and ends the program when that is what the command line asks for. |
| `function Has(const AName: string): Boolean` |  |
| `function Count(const AName: string): Integer` |  |
| `function Get(const AName: string): string` |  |
| `function GetInt(const AName: string): Int64` |  |
| `function GetAll(const AName: string): TStringArray` |  |
| `function CommandName: string` | The chosen sub-command ('' when the program has none, or none was given); "remote add" for nested commands. |
| `property Version: string` |  |
| `property HelpWanted: Boolean` |  |
| `property VersionWanted: Boolean` |  |

## Routines

### Levenshtein

```pascal
function Levenshtein(const A: string; const B: string): Integer
```

Edit distance, used for "did you mean ...?"

### CommandLineWords

```pascal
function CommandLineWords: TStringArray
```

The program's arguments as UTF-8 (on Windows ParamStr uses the old ANSI
code page, which cannot hold every character).

