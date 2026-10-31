# Guide: building a desktop app

This guide builds a small address book step by step: a window with a list and a form, menus and shortcuts, dialogs, a second window, and data in SQLite. The finished app is in [`examples/contacts`](../examples/contacts); [`examples/notepad`](../examples/notepad) is a text editor built the same way.

The basics of `.pform` files, layout and the designer are in [Forms and controls](forms.md). This guide puts them together.

## 1. Create the project

```sh
pastel new app contacts
cd contacts
pastel run
```

`src/main.pas` creates the forms and runs the app; `src/forms/Home.pform` is the main window and `Home.pas` its code. Keep `pastel run` going: when you save the `.pform` file the window updates by itself.

## 2. Lay out the window

A row with two columns: a search box and a list on the left, the details on the right.

```
object HomeForm: THomeForm
  Title = 'Contacts'
  Width = 760
  Height = 520
  Padding = 0
  Gap = 0
  object Body: TRow
    Grow = 1
    Align = Stretch          // the columns get the full height
    Padding = 16
    Gap = 16
    object Side: TColumn
      Width = 260
      Gap = 8
      object SearchEdit: TEdit
        Placeholder = 'Search'
        OnChange = SearchChange
      end
      object ContactList: TListBox
        Grow = 1
        OnChange = ContactListChange
      end
    end
    object Details: TColumn
      Grow = 1
      Gap = 8
      object NameEdit: TEdit
      end
      object NotesMemo: TMemo
        Grow = 1
      end
      object SaveButton: TButton
        Text = 'Save'
        Default = True
        OnClick = SaveClick
      end
    end
  end
end
```

In VS Code, the designer shows the window as you type; *Size* shows it at other window sizes and *Dark* in the dark theme.

## 3. Menus, shortcuts and actions

A `TAction` is one command with a caption, a shortcut and an `Enabled` state. Menu items and buttons that use it show the same caption and are disabled together:

```
  object MainMenu: TMenuBar
    object FileMenu: TMenuItem
      Caption = 'File'
      object NewItem: TMenuItem
        Action = NewAction
      end
      object Sep1: TMenuItem
        Caption = '-'
      end
      object QuitItem: TMenuItem
        Caption = 'Quit'
        ShortCut = 'Ctrl+Q'
        OnClick = QuitClick
      end
    end
  end
  object NewAction: TAction
    Caption = 'New contact'
    ShortCut = 'Ctrl+N'
    OnExecute = NewExecute
  end
```

and a button with `Action = NewAction`. The menu bar goes first in the form. `TPopupMenu` is a right-click menu: give it items and set `PopupMenu = EditMenu` on a control.

Shortcuts work anywhere in the window: `Ctrl+N` runs `NewExecute`. On macOS `Ctrl` means `Cmd`.

## 4. Event handlers

Declare the handlers in the form class; the designer's → button next to an event creates them for you.

```pascal
procedure THomeForm.SaveClick(Sender: TObject);
begin
  ...
  ContactList.Items.Add(NameEdit.Text);
end;

procedure THomeForm.NewExecute(Sender: TObject);
begin
  ContactList.ItemIndex := -1;
  NameEdit.Text := '';
  NameEdit.SetFocus;
end;
```

## 5. Dialogs

All dialogs wait for the answer and return it:

```pascal
ShowMessage('Saved.');
if Ask('Delete Ayşe?', 'Delete contact') then ...
case MessageDlg('Save the changes?', 'Notes', [mrYes, mrNo, mrCancel]) of
  mrYes: ...
end;
Name := InputBox('New list', 'Name of the list:', 'Friends');
if OpenFileDialog(FileName, 'Text files|*.txt;*.md|All files|*') then ...
if SaveFileDialog(FileName, 'Text files|*.txt', 'Save', '.txt') then ...
if SelectFolderDialog(Folder) then ...
```

`MessageDlg` with `Danger = True` makes the first button red. The save dialog asks before replacing a file. The dialogs are drawn by Pastel inside the window, so they look the same everywhere and can be tested with scripts (step 9).

## 6. A second window

```sh
pastel new form Settings
```

creates `Settings.pform` / `Settings.pas` with OK and Cancel buttons and adds the form to `main.pas`. Show it as a dialog:

```pascal
if SettingsForm.ShowModal = mrOk then
  ApplySettings;
```

A button with `ModalResult = mrOk` closes the dialog with that result; `Default = True` is pressed by Enter, `Cancel = True` by Escape. Before closing, `OnCloseQuery` can say no (for example when a field is empty).

## 7. Keeping the data

Put the data code in its own unit under `src/services/`, not in the form: then it can be tested without a window. [`contactstore.pas`](../examples/contacts/src/services/contactstore.pas) keeps the contacts in SQLite with `Pastel.Db`:

```pascal
FDb := TDatabase.Create('sqlite:' + GetAppConfigDir(False) + 'contacts.db', 1);
FDb.Exec('create table if not exists contacts (id integer primary key autoincrement, name text not null)', []);
Rows := FDb.Query('select * from contacts where name like ? order by name', ['%' + Filter + '%']);
```

`GetAppConfigDir(False)` is the right place for an app's files: `~/.config/contacts` on Linux, `AppData\Local\contacts` on Windows. See [Databases](database.md) for transactions and migrations, and [Testing](testing.md) for `pastel test`.

## 8. Long work, timers and threads

A `TTimer` (`Interval = 1000`, `OnTimer = Tick`) runs code on the UI thread at intervals. Work that takes long (a download, a big query) belongs in a thread; to show the result, hand it back to the UI thread with `TThread.Queue`:

```pascal
type
  THomeForm = class(THomeFormBase)
    ...
  private
    FResult: string;
    procedure Download;          // runs in another thread
    procedure ShowResult;        // runs on the UI thread
  end;

procedure THomeForm.RefreshClick(Sender: TObject);
begin
  Busy.Active := True;
  TThread.ExecuteInThread(@Download);
end;

procedure THomeForm.Download;
begin
  FResult := HttpGet('https://example.com/list.txt').Body;   // Pastel.Http
  TThread.Queue(nil, @ShowResult);
end;

procedure THomeForm.ShowResult;
begin
  Busy.Active := False;
  ResultMemo.Text := FResult;
end;
```

Never touch controls from the other thread; `TThread.Queue` (or `Synchronize`, which waits) runs the method on the UI thread, and the window wakes up for it. While the work runs, a `TSpinner` or a `TProgressBar` with `Indeterminate = True` shows that something is happening. In a long loop on the UI thread, `Application.ProcessMessages` keeps the window responding.

## 9. Testing the window

The window can be driven by a script, without a display. [`tests/ui.txt`](../examples/contacts/tests/ui.txt) of the example:

```
type NameEdit Ayşe Yılmaz
click SaveButton
expect CountLabel 1 contact
key ctrl+d
expect MessageText Delete Ayşe Yılmaz?
click YesButton
expect CountLabel no contacts
```

```sh
pastel build
PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/linux/debug/contacts
```

The commands are listed in [Forms and controls](forms.md#testing-a-form-without-a-window).

## 10. Look and feel

- **Dark theme:** `Appearance = System` on the main form follows the computer's setting; `Dark` and `Light` fix it. Set `Appearance` from code to switch while the app runs.
- **Sharp on high-DPI screens:** Pastel draws at the screen's real resolution; sizes in `.pform` files are in logical pixels.
- **Icon and fonts:** put `assets/icon.png` in the project for the window icon, `assets/font.ttf` (and `font-bold.ttf`) to use your own font. Everything in `assets/` is compiled into the program in release builds (`pastel build --release`); `TImage.FileName = 'logo.png'` and `OpenAsset('data/list.json')` find the files either way.

## 11. Shipping

```sh
pastel build --release              # Linux
pastel build --release --target windows
pastel package
```

See [Deploying](deploy.md).

## Controls

All controls have `Width`, `Height` (0 = as big as the content), `Grow`, `Visible`, `Enabled`, `Hint` and `PopupMenu`.

### Containers

| Control | Properties | Events |
|---|---|---|
| `TColumn` | Children top to bottom. `Gap`, `Padding`, `Align` (`Stretch`), `Justify`, `Color`, `Radius`, `BorderColor`, `BorderWidth` | |
| `TRow` | Children left to right; like `TColumn` with `Align = Center` | |
| `TCard` | A column with a background, border and rounded corners | |
| `TScrollBox` | A column that scrolls (mouse wheel, scroll bar, focus moves bring controls into view) | |
| `TTabControl` | Pages: its children are `TTabSheet`s. `TabIndex` | `OnChange` |
| `TTabSheet` | One page: `Caption` and the column properties | |
| `TSpacer` | Takes the free space | |

### Text

| Control | Properties | Events |
|---|---|---|
| `TLabel` | `Text` (may have line breaks), `FontSize`, `Bold`, `Color`, `TextAlign`, `WordWrap` | |
| `TEdit` | `Text`, `Placeholder`, `Password`, `ReadOnly`, `MaxLength`; `SelectAll`, `SelStart`, `SelLength` from code | `OnChange`, `OnSubmit` |
| `TMemo` | `Text`, `Lines`, `WordWrap`, `Placeholder`, `ReadOnly`, `MaxLength`; scrolls | `OnChange` |

Editing: mouse and `Shift` selection, double-click selects a word, `Ctrl+A`, cut/copy/paste, undo/redo (`Ctrl+Z`, `Ctrl+Y`), `Ctrl+Left/Right` by words, `Home`/`End`, `PageUp`/`PageDown` in a memo.

### Choices

| Control | Properties | Events |
|---|---|---|
| `TButton` | `Text`, `Style` (`Primary`, `Secondary`, `Danger`), `Action`, `ModalResult`, `Default`, `Cancel` | `OnClick` |
| `TCheckBox` | `Text`, `Checked` | `OnChange` |
| `TSwitch` | An on/off switch: `Text`, `Checked` | `OnChange` |
| `TRadioButton` | `Text`, `Checked`; one per parent is checked | `OnChange` |
| `TComboBox` | `Items`, `ItemIndex`, `Text`, `Placeholder`; opens a list (keyboard: arrows, Enter, Escape) | `OnChange` |
| `TListBox` | `Items`, `ItemIndex`, `ItemHeight`, `HotTrack`; only visible rows are drawn | `OnChange`, `OnDblClick`, `OnItemClick` |
| `TSlider` | `Position`, `Min`, `Max`, `Step`; arrows move it | `OnChange` |

### Pictures and progress

| Control | Properties | Events |
|---|---|---|
| `TImage` | `FileName` (in `assets/`, next to the program, or a full path), `Fit` (`Contain`, `Cover`, `Stretch`, `Center`); `LoadFromStream`, `Picture` from code. PNG, JPEG, BMP | |
| `TProgressBar` | `Position`, `Max`, `Indeterminate` | |
| `TSpinner` | `Active` | |

### Menus and commands

| Component | Properties | Events |
|---|---|---|
| `TMenuBar` | The window's menu bar; its items are the menus | |
| `TMenuItem` | `Caption` (`'-'` for a line), `ShortCut` (`'Ctrl+Shift+S'`, `'F5'`), `Checked`, `Action`; items inside are a submenu | `OnClick` |
| `TPopupMenu` | A right-click menu; set `PopupMenu = ...` on a control | |
| `TAction` | `Caption`, `ShortCut`, `Enabled`, `Checked` | `OnExecute` |
| `TTimer` | `Interval` (ms), `Enabled` | `OnTimer` |
