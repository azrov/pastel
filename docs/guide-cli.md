# Guide: writing a command-line tool

This guide builds a real tool step by step: **dupfinder**, which finds files
with the same content. The finished program is in `examples/dupfinder`; a
second example, `examples/weather`, shows a tool that calls a web API. Both
are built and tested with every change to Pastel, so the code here works.

## 1. Start

```sh
pastel new console dupfinder
cd dupfinder
```

Decide what the tool should look like from the outside first. For
dupfinder:

```
dupfinder [options] <folders>...

  -p, --pattern PATTERN   Only files whose name matches
  -m, --min-size SIZE     Ignore files smaller than this, e.g. 100k or 5M
      --json              Print the groups as JSON
```

## 2. Keep the work out of `main.pas`

`main.pas` deals with the command line and the screen. The actual work goes
in a unit under `src/` (Pastel finds every folder below it): here
`src/services/duplicates.pas`. A unit that does not write to the screen or
read arguments is easy to test and to reuse.

```pascal
unit Duplicates;
...
type
  TDupGroup = record
    Size: Int64;
    Files: TStringArray;
  end;
  TDupGroups = array of TDupGroup;

function ParseSize(const S: string): Int64;          { '10M' -> 10485760 }
function FindDuplicates(const Files: array of string; MinSize: Int64;
  OnCheck: TCheckProc = nil): TDupGroups;
```

The idea: files of different size cannot be equal, so only files that
share their size with another are read, and those are compared by MD5
checksum (Free Pascal's `md5` unit).

## 3. Test it

Write the tests next to the code, in `tests/duplicates_test.pas`. The test
creates its own files in a temporary folder:

```pascal
procedure TDuplicatesTests.SetUp;
begin
  Dir := MakeTempDir('dupfinder-test');
  WriteText(Dir + 'a.txt', 'hello');
  WriteText(JoinPath([Dir, 'sub', 'b.txt']), 'hello');
  WriteText(Dir + 'c.txt', 'hellp');      { same size, other content }
end;

procedure TDuplicatesTests.TearDown;
begin
  DeleteDir(Dir);
end;

procedure TDuplicatesTests.FindsFilesWithEqualContent;
var
  G: TDupGroups;
begin
  G := FindDuplicates(ListFiles(Dir, '*', True), 1);
  AssertEquals(1, Length(G));
  AssertEquals(2, Length(G[0].Files));
end;
```

Keep `pastel test --watch` running in a terminal while you work: every save
runs the tests again. `MakeTempDir`, `WriteText`, `ListFiles` and `DeleteDir`
come from `Pastel.Files` ([system.md](system.md)).

## 4. Arguments

```pascal
Args := TArgs.Create(AppName, 'Finds files with the same content, so the copies can go.');
try
  Args.Version := AppVersion;                    { from pastel.toml }
  Args.Positional('folders', 'Folders to search (with their sub-folders)').Many;
  Args.Option('pattern', 'p', 'Only files whose name matches').Many.MetaVar('PATTERN');
  Args.Option('min-size', 'm', 'Ignore files smaller than this, e.g. 100k or 5M', '1').MetaVar('SIZE');
  Args.Flag('json', '', 'Print the groups as JSON');
  Args.Example('dupfinder -p "*.jpg" -p "*.png" --min-size 100k photos');
  Args.Parse;
  ...
finally
  Args.Free;
end;
```

`Args.Parse` takes care of `--help`, `--version`, missing folders and typing
mistakes (`--min-sise` → *did you mean --min-size?*), with exit code 2. All
the details are in [console.md](console.md).

## 5. Check the input, say what is wrong

Some mistakes only the program can see. Say them in a sentence, on standard
error, and end with exit code 2 (wrong use) or 1 (it did not work):

```pascal
try
  MinSize := ParseSize(Args.Get('min-size'));
except
  on E: EConvertError do
  begin
    Error(E.Message);        { ✗ "lots" is not a size; use a number with k, M or G, like 10M }
    Halt(2);
  end;
end;
for Folder in Args.GetAll('folders') do
  if not DirectoryExists(Folder) then
  begin
    Error(Format('folder "%s" does not exist', [Folder]));
    Halt(2);
  end;
```

## 6. Progress for people, plain output for scripts

Reading thousands of files takes a while. A progress bar helps a person at
a terminal, but would only clutter a file or another program's input:

```pascal
if not Args.Has('json') and IsTerminal then
  Progress := TProgress.Create(Length(SameSizeFiles(Files, MinSize)), 'comparing');
try
  Groups := FindDuplicates(Files, MinSize, @Checked);    { Checked calls Progress.Step }
finally
  FreeAndNil(Progress);
end;
```

## 7. Output: for reading, and for other programs

For people: short, with the important part in bold, and a summary.

```
2 files of 2.9 KB
  /home/ali/Pictures/beach.jpg
  /home/ali/Downloads/beach (1).jpg

✓ 1 group(s) of duplicates; deleting the copies would free 2.9 KB
```

For other programs: `--json`. It costs a few lines and makes the tool usable
in scripts (`dupfinder --json ~/Pictures | jq ...`):

```pascal
List := TJSONArray.Create;
for G in Groups do
begin
  Files := TJSONArray.Create;
  for F in G.Files do
    Files.Add(F);
  List.Add(JObject(['size', G.Size, 'wasted', Wasted(G), 'files', Files]));
end;
WriteLn(ToJson(List, True));
```

Colors and symbols switch themselves off when the output is not a terminal,
and with `NO_COLOR` or `--no-color`.

## 8. Settings and the web: the `weather` example

`examples/weather` shows the rest of what most tools need.

**Settings** that a user sets once, instead of typing them every time:

```pascal
Config := TConfig.Create('weather');
Config.SetDefault('units', 'metric');
Config.LoadStandard;      { ~/.config/weather/config.toml, ./config.toml, WEATHER_* variables }
...
Args.Option('units', 'u', 'metric or imperial', Config.Get('units')).Choices(['metric', 'imperial']);
```

The command line wins over the settings file, the file over the default.

**Calling a web API** with `Pastel.Http`: HTTPS with certificate checks,
proxies and clear error messages are taken care of.

```pascal
R := HttpGet(PlaceUrl(City, Config.Get('language')));
R.RaiseForStatus;
Place := ParsePlace(R.Body, City);
```

**Testing without a network:** the unit `Forecast` only builds addresses
and reads answers; it never connects. The tests feed it answers saved from
the real service, so they run anywhere, fast, and always give the same
result:

```pascal
const
  NoPlaceAnswer = '{"generationtime_ms":0.3}';

procedure TForecastTests.UnknownPlaceIsExplained;
...
  AssertEquals('no place called "Atlantis" was found', E.Message);
```

## 9. Release

```sh
pastel fmt --check                    # is everything formatted?
pastel test
pastel package --all                  # every platform in pastel.toml
```

`dist/` then holds `dupfinder-1.0.0-linux.tar.gz`,
`dupfinder-1.0.0-windows.zip` and so on, each with a `.sha256` file. What
goes into the packages besides the program is set in `pastel.toml`:

```toml
[package]
include = ["README.md", "config.example.toml"]
```

## Checklist for a good tool

- `--help` explains every option, with an example
- `--version` (comes from `pastel.toml`)
- mistakes are explained in a sentence, on standard error
- exit code 0 when it worked, 1 when it did not, 2 for wrong use
- no colors or progress bars when the output is not a terminal
- `--json` (or another plain format) for scripts
- the work is in units with tests; `main.pas` only connects them
