# Pastel.Dialogs

Dialogs: messages, questions, input, choosing files and folders.

    ShowMessage('Saved.');
    if Ask('Delete this note?') then ...
    Name := InputBox('New file', 'Name:', 'notes.txt');
    if OpenFileDialog(FileName, 'Text files|*.txt;*.md|All files|*') then ...
    if SaveFileDialog(FileName, 'Notes|*.txt') then ...

  Messages and questions are drawn by Pastel inside the window. The file
  and folder dialogs are the system's own when it has them (Windows; Linux
  with zenity or kdialog), else Pastel's; UseNativeDialogs := False always
  takes Pastel's. Test scripts and headless runs get Pastel's, which
  scripts can click. They wait until the user answered, like Delphi's. Their controls have names a test script can use:
  OkButton, CancelButton, YesButton, NoButton, InputEdit, FileList,
  FileNameEdit, PathEdit.

`uses Pastel.Dialogs;` · source: [framework/src/pastel.dialogs.pas](../../framework/src/pastel.dialogs.pas)

**Contents:** [ShowMessage](#showmessage) · [Ask](#ask) · [MessageDlg](#messagedlg) · [InputBox](#inputbox) · [InputQuery](#inputquery) · [OpenFileDialog](#openfiledialog) · [SaveFileDialog](#savefiledialog) · [SelectFolderDialog](#selectfolderdialog) · [ModalResultCaption](#modalresultcaption)

## Routines

### ShowMessage

```pascal
procedure ShowMessage(const Msg: string; const Title: string = '')
```

A message with an OK button.

### Ask

```pascal
function Ask(const Msg: string; const Title: string = ''): Boolean
```

A question with Yes and No; True for Yes.

### MessageDlg

```pascal
function MessageDlg(const Msg: string; const Title: string; const Buttons: array of Integer; Danger: Boolean = False): Integer
```

A message with the buttons given (mrOk, mrCancel, mrYes, mrNo, mrAbort,
mrRetry, mrIgnore, mrClose); the result is the button chosen, or mrCancel
for Escape. The first button is the default (Enter). Danger: the first
button is red (for deleting and the like).

### InputBox

```pascal
function InputBox(const Title: string; const Prompt: string; const Default: string): string
```

Asks for a line of text; Default when cancelled.

### InputQuery

```pascal
function InputQuery(const Title: string; const Prompt: string; var Value: string): Boolean
```

The same; False when cancelled (Value is not changed then).

### OpenFileDialog

```pascal
function OpenFileDialog(var FileName: string; const Filter: string = ''; const Title: string = 'Open'): Boolean
```

Filter: 'Pictures|*.png;*.jpg|All files|*'. FileName: where to start
(a file or a folder); on True the chosen file.

### SaveFileDialog

```pascal
function SaveFileDialog(var FileName: string; const Filter: string = ''; const Title: string = 'Save'; const DefaultExt: string = ''): Boolean
```

Asks before replacing a file that exists. DefaultExt ('.txt') is added
when the name has none.

### SelectFolderDialog

```pascal
function SelectFolderDialog(var Folder: string; const Title: string = 'Choose a folder'): Boolean
```

### ModalResultCaption

```pascal
function ModalResultCaption(R: Integer): string
```

The caption of a modal result: 'OK', 'Cancel', 'Yes'...

## Constants and variables

| | |
|---|---|
| `var UseNativeDialogs: Boolean` | File and folder dialogs of the system when there are some. |
| `var NativeWindowHook: function : Pointer` | The window handle for system dialogs (set by the application; HWND on Windows). |
