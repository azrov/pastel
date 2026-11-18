# Pastel.Term

Terminal output and input for console programs.

    WriteLn(Green('done'), ' in ', Bold('2.1s'));
    T := TTable.Create(['Name', 'Size']);
    T.AddRow(['report.pdf', '1.2 MB']);
    T.Print;
    if Confirm('Delete 3 files?') then ...
    Name := Ask('Your name', 'Ali');

  Colors are switched off automatically when the output is not a terminal
  (a pipe or a file), when NO_COLOR is set, or on old Windows consoles.
  Prompts read from standard input, so they also work in scripts and tests.

`uses Pastel.Term;` · source: [framework/src/pastel.term.pas](../../framework/src/pastel.term.pas)

**Contents:** [TTextAlign](#ttextalign) · [TTable](#ttable) · [TProgress](#tprogress) · [Bold](#bold) · [Dim](#dim) · [Italic](#italic) · [Underline](#underline) · [Red](#red) · [Green](#green) · [Yellow](#yellow) · [Blue](#blue) · [Magenta](#magenta) · [Cyan](#cyan) · [Gray](#gray) · [Rgb](#rgb) · [StripStyles](#stripstyles) · [ColorsEnabled](#colorsenabled) · [SetColors](#setcolors) · [IsTerminal](#isterminal) · [TerminalWidth](#terminalwidth) · [DisplayWidth](#displaywidth) · [PadRight](#padright) · [PadLeft](#padleft) · [Success](#success) · [Info](#info) · [Warning](#warning) · [Error](#error) · [Ask](#ask) · [Confirm](#confirm) · [Choose](#choose) · [AskPassword](#askpassword) · [IsInteractive](#isinteractive)

## Types

### TTextAlign

```pascal
type TTextAlign = (alLeft, alRight, alCenter)
```

- `alLeft`
- `alRight`
- `alCenter`
### TTable

```pascal
type TTable = class
```

A table printed with aligned columns and a line under the header.

| | |
|---|---|
| `constructor Create(const AHeader: array of string)` |  |
| `procedure AddRow(const Cells: array of string)` |  |
| `procedure SetAlign(Column: Integer; Align: TTextAlign)` |  |
| `function RowCount: Integer` |  |
| `function ToText: string` |  |
| `procedure Print` |  |

### TProgress

```pascal
type TProgress = class
```

A progress bar on one line: "[########------]  45%  45/100  copying".

| | |
|---|---|
| `constructor Create(ATotal: Int64; const ALabel: string = '')` |  |
| `destructor Destroy` |  |
| `procedure Step(Amount: Int64 = 1)` |  |
| `procedure SetPosition(AValue: Int64)` |  |
| `procedure SetLabel(const AValue: string)` |  |
| `procedure Finish` | Ends the line; called by Free too. |
| `property Position: Int64` |  |
| `property Total: Int64` |  |

## Routines

### Bold

```pascal
function Bold(const S: string): string
```

### Dim

```pascal
function Dim(const S: string): string
```

### Italic

```pascal
function Italic(const S: string): string
```

### Underline

```pascal
function Underline(const S: string): string
```

### Red

```pascal
function Red(const S: string): string
```

### Green

```pascal
function Green(const S: string): string
```

### Yellow

```pascal
function Yellow(const S: string): string
```

### Blue

```pascal
function Blue(const S: string): string
```

### Magenta

```pascal
function Magenta(const S: string): string
```

### Cyan

```pascal
function Cyan(const S: string): string
```

### Gray

```pascal
function Gray(const S: string): string
```

### Rgb

```pascal
function Rgb(const Hex: string; const S: string): string
```

24-bit color from '#RRGGBB'; falls back to plain text.

### StripStyles

```pascal
function StripStyles(const S: string): string
```

Removes escape codes.

### ColorsEnabled

```pascal
function ColorsEnabled: Boolean
```

True if colors are used. Can be changed, e.g. for a --no-color option.

### SetColors

```pascal
procedure SetColors(AEnabled: Boolean)
```

### IsTerminal

```pascal
function IsTerminal: Boolean
```

True if standard output is a terminal (not a file or a pipe).

### TerminalWidth

```pascal
function TerminalWidth: Integer
```

### DisplayWidth

```pascal
function DisplayWidth(const S: string): Integer
```

Number of columns a text takes on screen (UTF-8 aware, styles ignored).

### PadRight

```pascal
function PadRight(const S: string; Width: Integer): string
```

### PadLeft

```pascal
function PadLeft(const S: string; Width: Integer): string
```

### Success

```pascal
procedure Success(const Msg: string)
```

### Info

```pascal
procedure Info(const Msg: string)
```

### Warning

```pascal
procedure Warning(const Msg: string)
```

### Error

```pascal
procedure Error(const Msg: string)
```

### Ask

```pascal
function Ask(const Question: string; const Default: string = ''): string
```

### Confirm

```pascal
function Confirm(const Question: string; Default: Boolean = False): Boolean
```

Yes/no question; Enter gives Default.

### Choose

```pascal
function Choose(const Question: string; const Choices: array of string; Default: Integer = 0): Integer
```

Shows numbered choices; returns the index of the chosen one.

### AskPassword

```pascal
function AskPassword(const Question: string): string
```

Like Ask, but the typed text is not shown (when standard input is a terminal).

### IsInteractive

```pascal
function IsInteractive: Boolean
```

True when standard input is a terminal (someone can answer questions).

