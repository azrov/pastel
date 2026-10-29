# Console programs

`pastel new console mytool` creates a command-line program that already handles arguments, `--help` and `--version`. This page shows the units that make console programs pleasant to write:

| Unit | For |
|---|---|
| `Pastel.Args` | Options, flags, arguments, sub-commands, automatic help |
| `Pastel.Term` | Colors, tables, progress bars, questions |
| `Pastel.Text` | Upper/lower case and lengths that work for every language |
| `AppInfo` | Your program's name and version from `pastel.toml` (generated) |

## Arguments: `Pastel.Args`

```pascal
uses
  Pastel.Args, AppInfo;

var
  Args: TArgs;
begin
  Args := TArgs.Create(AppName, 'Copies folders into an archive.');
  try
    Args.Version := AppVersion;
    Args.Flag('verbose', 'v', 'Show every file');
    Args.Option('output', 'o', 'Archive to write', 'backup.tar').MetaVar('FILE');
    Args.Option('level', 'l', 'Compression level').IntRange(1, 9).Default('6');
    Args.Option('format', 'f', 'Archive format').Choices(['tar', 'zip']).Default('tar');
    Args.Option('exclude', 'x', 'Pattern to skip').Many;
    Args.Option('token', '', 'Upload token').Env('BACKUP_TOKEN');
    Args.Positional('folders', 'Folders to back up').Many;
    Args.Example('backup -v -o today.tar docs photos');
    Args.Parse;

    if Args.Has('verbose') then ...
    Level := Args.GetInt('level');
    for Folder in Args.GetAll('folders') do ...
  finally
    Args.Free;
  end;
end.
```

`backup --help` then prints:

```
Copies folders into an archive.

Usage: backup [options] <folders>...

Arguments:
  <folders>  Folders to back up

Options:
  -v, --verbose          Show every file
  -o, --output FILE      Archive to write (default: backup.tar)
  -l, --level N          Compression level [1-9] (default: 6)
  -f, --format FORMAT    Archive format [tar|zip] (default: tar)
  -x, --exclude EXCLUDE  Pattern to skip
      --token TOKEN      Upload token (env: BACKUP_TOKEN)
  -h, --help             Show this help
      --version          Show the version
      --no-color         Plain output without colors

Examples:
  backup -v -o today.tar docs photos
```

Mistakes are explained, with a suggestion when it looks like a typo, and the program ends with exit code 2:

```
$ backup --outptu x docs
error: unknown option "--outptu" (did you mean --output?)
Run "backup --help" for usage.
```

### Defining arguments

| Call | |
|---|---|
| `Flag(Name, Short, Help)` | On/off switch: `-v`, `--verbose`. `Count` tells how often it was given (`-vvv`). |
| `Option(Name, Short, Help, Default)` | Takes a value: `-o x`, `-ox`, `-o=x`, `--output x`, `--output=x` |
| `Positional(Name, Help)` | A word without a dash, in order. Required unless `.Optional` or a `.Default` is set. |
| `Command(Name, Description)` | A sub-command with its own arguments (see below) |
| `Example(Line)` | Shown at the end of the help |

Every definition can be refined by chaining:

| Method | |
|---|---|
| `.Default('x')` | Value when not given |
| `.Required` / `.Optional` | Must or need not be given |
| `.Many` | Option: may be given several times. Positional: takes all remaining words. |
| `.IsInteger`, `.IntRange(1, 9)` | Must be a whole number (in a range) |
| `.Choices(['a', 'b'])` | Must be one of these |
| `.Env('NAME')` | Taken from this environment variable when not on the command line |
| `.MetaVar('FILE')` | Placeholder shown in the help |

Short names are one letter; use `''` for none. `--` ends the options, so `tool -- -file` passes `-file` as a word.

### Reading values

| | |
|---|---|
| `Args.Has('verbose')` | Was it given? (Defaults do not count.) |
| `Args.Get('output')` | The value, or the default |
| `Args.GetInt('level')` | The value as a number |
| `Args.GetAll('exclude')` | All values of a `.Many` option or positional |
| `Args.Count('verbose')` | How many times a flag was given |

### Sub-commands

```pascal
Args := TArgs.Create('todo', 'A small task list.');
Args.Option('file', '', 'Task file', 'tasks.txt');        // works with every command
with Args.Command('add', 'Add a task') do
begin
  Positional('title', 'What to do');
  Option('priority', 'p', 'How important').Choices(['low', 'normal', 'high']).Default('normal');
end;
with Args.Command('list', 'Show tasks') do
  Flag('all', 'a', 'Include finished tasks');
Args.Parse;

case Args.CommandName of
  'add':  AddTask(Args.Get('title'), Args.Get('priority'));
  'list': ShowTasks(Args.Has('all'));
end;
```

`todo --help` lists the commands; `todo add --help` shows the options of `add`.

## Terminal: `Pastel.Term`

```pascal
WriteLn(Green('done'), ' in ', Bold('2.1 s'));
Success('Backup written');            // ✓ Backup written
Warning('3 files were skipped');      // ! ... (to stderr)
Error('Disk full');                   // ✗ ... (to stderr)
```

Colors: `Bold`, `Dim`, `Italic`, `Underline`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `Gray`, and `Rgb('#4F46E5', Text)`. They switch themselves off when the output goes to a file or a pipe, when `NO_COLOR` is set, or with `--no-color`. `FORCE_COLOR=1` keeps them on.

### Tables

```pascal
T := TTable.Create(['File', 'Size', 'State']);
T.SetAlign(1, alRight);
T.AddRow(['report.pdf', '1.2 MB', Green('ready')]);
T.AddRow(['çok-uzun-dosya.txt', '12 KB', Yellow('waiting')]);
T.Print;
T.Free;
```

```
File                  Size  State
------------------  ------  -------
report.pdf          1.2 MB  ready
çok-uzun-dosya.txt   12 KB  waiting
```

Columns line up with colored text and with letters like `ş` or `漢`.

### Progress

```pascal
P := TProgress.Create(Files.Count, 'copying');
for F in Files do
begin
  Copy(F);
  P.Step;
end;
P.Free;
```

In a terminal it is one updating line: `[#########-------------]  45%  45/100  copying`. In a log file it writes a line every 10%.

### Questions

```pascal
Name := Ask('Your name', 'Ali');                       // Your name [Ali]:
if Confirm('Delete 3 files?') then ...                 // Delete 3 files? [y/N]
Env := Choose('Deploy to', ['staging', 'production']); // numbered list
Pass := AskPassword('Password');                       // typing is hidden
```

`Confirm` accepts y/yes and n/no (also e/evet, h/hayır). Questions read from standard input, so answers can be piped in for scripts and tests: `printf 'Ali\ny\n' | mytool`. `IsInteractive` tells whether someone is there to answer.

## Text: `Pastel.Text`

Free Pascal's `UpperCase` and `LowerCase` only change A–Z, and `Length` counts bytes. For text in any language use:

| | |
|---|---|
| `Upper('ayşe')` | `'AYŞE'` |
| `Upper('istanbul', 'tr')` | `'İSTANBUL'` (Turkish and Azerbaijani dotted i: `'tr'`, `'az'`) |
| `Lower('ILIK', 'tr')` | `'ılık'` |
| `Capitalize('şehir')` | `'Şehir'` |
| `CharCount('ağaç')` | `4` (`Length` gives 6) |
| `CharCopy('ağaç', 2, 2)` | `'ğa'` |
| `Shorten('çok uzun bir yazı', 7)` | `'çok uz…'` |

## Program information: `AppInfo`

Pastel generates the unit `AppInfo` from `pastel.toml` on every build:

```pascal
uses AppInfo;
...
WriteLn(AppName, ' ', AppVersion);   // values from [project]
if AppProfile = 'debug' then ...      // debug, release or test
WriteLn(AppTarget);                   // linux, windows, linux-arm64, ...
```

Change `version` in `pastel.toml` and `--version` follows.

## UTF-8

Pastel programs use UTF-8 for all text on every platform. On Windows, Pastel switches the program and its console to UTF-8 at start, so `WriteLn('Çiğdem')` and arguments like `mytool ayşe` work as on Linux.
