# Pastel.NativeDialogs

The system's own open, save and folder dialogs.

  Windows: the common dialogs (comdlg32, shell32). Linux: zenity (GNOME and
  most desktops) or kdialog (KDE), when installed. Pastel.Dialogs uses them
  when they are there and falls back to its own dialogs otherwise; test
  scripts and headless runs always get Pastel's own.
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.

`uses Pastel.NativeDialogs;` · source: [framework/src/pastel.nativedialogs.pas](../../framework/src/pastel.nativedialogs.pas)

## Types

### TNativeDialogKind

```pascal
type TNativeDialogKind = (ndOpen, ndSave, ndFolder)
```

- `ndOpen`
- `ndSave`
- `ndFolder`
### TNativeDialog

```pascal
type TNativeDialog = class
```

One dialog. Start shows it (False: no system dialog here); on Linux it
runs beside the program, so the window keeps drawing: call Running until
it is False. Then Ok and FileName hold the answer.

| | |
|---|---|
| `constructor Create(AKind: TNativeDialogKind; const ATitle: string; const AFilter: string; const AFileName: string; const ADefaultExt: string)` |  |
| `destructor Destroy` |  |
| `function Start: Boolean` |  |
| `function Running: Boolean` |  |
| `property Ok: Boolean` |  |
| `property FileName: string` |  |
| `property Owner: Pointer` | The window that owns the dialog (Windows: HWND). |

## Routines

### SplitFilter

```pascal
procedure SplitFilter(const Filter: string; out Names: TStringArray; out Patterns: TStringArray)
```

Filter 'Text files|*.txt;*.md|All files|*' as pairs: names and patterns.

