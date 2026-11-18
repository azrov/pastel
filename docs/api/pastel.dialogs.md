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
  scripts can click. They wait until the user answered, like Delphi's.
  Each has a second form that does not wait: it returns at once and calls a
  method of yours with the answer — the way for phones (nothing should wait
  inside an event there):
    Ask('Delete this note?', @DeleteAnswered);
    ...
    procedure TMainForm.DeleteAnswered(Sender: TObject; AResult: Integer);
    begin
      if AResult = mrYes then DeleteNote;
    end;
  Their controls have names a test script can use:
  OkButton, CancelButton, YesButton, NoButton, InputEdit, FileList,
  FileNameEdit, PathEdit.

`uses Pastel.Dialogs;` · source: [framework/src/pastel.dialogs.pas](../../framework/src/pastel.dialogs.pas)

**Contents:** [TOpenDialog](#topendialog) · [TSaveDialog](#tsavedialog) · [TSelectFolderDialog](#tselectfolderdialog) · [ShowMessage](#showmessage) · [ShowMessage](#showmessage) · [ShowToast](#showtoast) · [Ask](#ask) · [Ask](#ask) · [MessageDlg](#messagedlg) · [MessageDlg](#messagedlg) · [InputBox](#inputbox) · [InputQuery](#inputquery) · [InputQuery](#inputquery) · [LoginDialog](#logindialog) · [OpenFileDialog](#openfiledialog) · [OpenFileDialog](#openfiledialog) · [SaveFileDialog](#savefiledialog) · [SelectFolderDialog](#selectfolderdialog) · [SaveFileDialog](#savefiledialog) · [SelectFolderDialog](#selectfolderdialog) · [ModalResultCaption](#modalresultcaption)

## Types

### TOpenDialog

```pascal
type TOpenDialog = class(TComponent)
```

The file dialogs as components, like Delphi's: put one on the form (it is not
drawn), set its properties in the designer and call Execute:
if OpenDialog1.Execute then
Memo.Lines.LoadFromFile(OpenDialog1.FileName);

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Execute: Boolean` | Shows the dialog; True when the user chose a file (then in FileName). |
| `procedure Execute(OnDone: TFileDoneEvent)` | The same without waiting: FileName is set, then OnDone(Self, Ok, FileName). |
| `property FileName: string` | Where it starts (a file or a folder); the chosen file after Execute. |
| `property Filter: string` | 'Pictures\|*.png;*.jpg\|All files\|*' |
| `property Title: string` |  |

### TSaveDialog

```pascal
type TSaveDialog = class(TOpenDialog)
```

Asks before replacing a file that exists; DefaultExt ('.txt') is added when the name has none.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Execute: Boolean` |  |
| `procedure Execute(OnDone: TFileDoneEvent)` |  |
| `property DefaultExt: string` |  |

### TSelectFolderDialog

```pascal
type TSelectFolderDialog = class(TComponent)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Execute: Boolean` |  |
| `procedure Execute(OnDone: TFileDoneEvent)` |  |
| `property Folder: string` | Where it starts; the chosen folder after Execute. |
| `property Title: string` |  |

## Other types

| | |
|---|---|
| `type TInputDoneEvent = procedure(Sender: TObject; Ok: Boolean; Value: string)` | The answer of InputQuery without waiting: Ok for OK, Value the text typed. |
| `type TFileDoneEvent = procedure(Sender: TObject; Ok: Boolean; FileName: string)` | The answer of a file dialog without waiting: Ok when a file (folder) was chosen. |

## Routines

### ShowMessage

```pascal
procedure ShowMessage(const Msg: string; const Title: string = '')
```

A message with an OK button.

### ShowMessage

```pascal
procedure ShowMessage(const Msg: string; OnDone: TModalDoneEvent; const Title: string = '')
```

The same without waiting; OnDone (may be nil) when it is closed.

### ShowToast

```pascal
procedure ShowToast(const Msg: string; Long: Boolean = False)
```

A short message for a moment, without a button (Android's Toast; drawn by
Pastel near the bottom of the window elsewhere): 'Saved', 'Copied'.

### Ask

```pascal
function Ask(const Msg: string; const Title: string = ''): Boolean
```

A question with Yes and No; True for Yes.

### Ask

```pascal
procedure Ask(const Msg: string; OnDone: TModalDoneEvent; const Title: string = '')
```

The same without waiting: OnDone gets mrYes or mrNo.

### MessageDlg

```pascal
function MessageDlg(const Msg: string; const Title: string; const Buttons: array of Integer; Danger: Boolean = False): Integer
```

A message with the buttons given (mrOk, mrCancel, mrYes, mrNo, mrAbort,
mrRetry, mrIgnore, mrClose); the result is the button chosen, or mrCancel
for Escape. The first button is the default (Enter). Danger: the first
button is red (for deleting and the like).

### MessageDlg

```pascal
procedure MessageDlg(const Msg: string; const Title: string; const Buttons: array of Integer; OnDone: TModalDoneEvent; Danger: Boolean = False)
```

The same without waiting: OnDone gets the button chosen (mrCancel for Escape).

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

### InputQuery

```pascal
procedure InputQuery(const Title: string; const Prompt: string; const Value: string; OnDone: TInputDoneEvent)
```

The same without waiting: OnDone gets Ok and the text.

### LoginDialog

```pascal
function LoginDialog(const Title: string; var User: string; var Password: string; const Error: string = ''): Boolean
```

Asks for an e-mail (or user name) and a password; Error is shown above
them (after a failed try). With Pastel.Auth:
while LoginDialog('Salon', Email, Password, Client.Error) do
if Client.Login(Email, Password) then Break;

### OpenFileDialog

```pascal
function OpenFileDialog(var FileName: string; const Filter: string = ''; const Title: string = 'Open'): Boolean
```

Filter: 'Pictures|*.png;*.jpg|All files|*'. FileName: where to start
(a file or a folder); on True the chosen file.

### OpenFileDialog

```pascal
procedure OpenFileDialog(const FileName: string; const Filter: string; const Title: string; OnDone: TFileDoneEvent)
```

The file dialogs without waiting: OnDone gets Ok and the file (folder).

### SaveFileDialog

```pascal
procedure SaveFileDialog(const FileName: string; const Filter: string; const Title: string; const DefaultExt: string; OnDone: TFileDoneEvent)
```

### SelectFolderDialog

```pascal
procedure SelectFolderDialog(const Folder: string; const Title: string; OnDone: TFileDoneEvent)
```

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
