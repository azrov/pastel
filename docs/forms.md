# Forms and controls

A Pastel window is a **form**. Each form has two files in `src/forms/`:

| File | What it contains |
|---|---|
| `Home.pform` | The layout: which controls exist and their properties |
| `Home.pas` | The code: event handlers and logic |

When you build, Pastel generates a third unit, `Home.g`, with a `THomeFormBase` class that has a field for every control in the `.pform` file. Your form class inherits from it, so you can use `NameEdit.Text` directly. You never edit the generated file; it lives in `build/`.

```pascal
unit Home;
{$mode objfpc}{$H+}
interface
uses SysUtils, Pastel.UI, Home.g;

type
  THomeForm = class(THomeFormBase)
    procedure SendClick(Sender: TObject);
  end;

var
  HomeForm: THomeForm;

implementation

procedure THomeForm.SendClick(Sender: TObject);
begin
  Greeting.Text := 'Hello, ' + NameEdit.Text;
end;

end.
```

## The .pform format

```
object HomeForm: THomeForm
  Title = 'My app'
  Width = 460
  object NameEdit: TEdit
    Placeholder = 'Your name'
  end
  object SendButton: TButton
    Text = 'Send'
    OnClick = SendClick
  end
end
```

- `object Name: TType` ... `end` creates a control. Objects inside another object become its children.
- Text values use single quotes: `'It''s fine'` (two quotes for one).
- Numbers: `Width = 200`, `Gap = -2`.
- `True` / `False` for yes/no properties.
- Choices can be written short: `Align = Center` is the same as `Align = aiCenter`.
- Colors are text: `Color = '#4F46E5'` (also `#RGB` and `#AARRGGBB`).
- Events name a method of your form class: `OnClick = SendClick`. The method must be declared in the class: `procedure SendClick(Sender: TObject);`
- Comments: `// to the end of the line` and `{ like this }`.

## The window

Window settings are properties of the form:

| Property | Default | |
|---|---|---|
| `Title` | `'Pastel'` | Window title |
| `Width`, `Height` | 480 × 360 | Size when the window opens |
| `MinWidth`, `MinHeight` | 200 × 120 | Smallest size the user can resize to |
| `Resizable` | `True` | `False`: fixed size, no maximize |
| `WindowState` | `Normal` | `Maximized`, `Minimized` or `FullScreen` when the window opens |
| `AlwaysOnTop` | `False` | Keep the window above other windows |

From code: `Maximize`, `Minimize`, `Restore`, `Close`, or set `WindowState` and `Resizable` while the app runs. `WindowState` also tells you what the user did (for example `wsMaximized` after they maximized the window).

Window events:

```pascal
// OnCloseQuery = HomeCloseQuery: runs when the user closes the window or Close is called
procedure THomeForm.HomeCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FHasUnsavedChanges;
end;
```

`OnClose` runs when the window really closes, `OnResize` after the size changed. The minimize, maximize and close buttons in the title bar are drawn by the operating system, so they always match the platform.

## Designing in VS Code

With the Pastel extension, open a `.pform` file and press the designer button in the editor title:

- click a control to select it; the editor jumps to its line, and moving the cursor in the editor selects it in the designer
- change properties in the panel on the right; the → button next to an event opens its code, or creates the handler if it does not exist yet
- drag controls to move them: the orange line shows where the control will go (between other controls, or into a row, column or card)
- drag new controls in from the toolbox, or click one to add it after the selected control
- `Delete` removes the selected control; `Ctrl+C`, `Ctrl+X`, `Ctrl+V` and `Ctrl+D` (duplicate) copy controls, with new names when a name is taken
- `F2` or the name at the top of the properties panel renames a control, and the form's `.pas` code is renamed with it
- `Ctrl+Z` / `Ctrl+Y` undo and redo designer changes (every change is also an ordinary edit of the `.pform` text)
- the size box shows the form at phone, tablet and desktop sizes; *Dark* shows it in the dark theme

Controls of your own (`pastel new control StarRating`, in `src/controls/`) are in the toolbox too, at the front in italics.

**Pastel: New Form…** (or the *New Form* button in the Pastel sidebar, or `pastel new form Settings` in a terminal) creates `Settings.pform` and `Settings.pas` with OK and Cancel buttons, and adds the form to `main.pas`.

## Hot reload

`pastel run` builds a debug version that reads the `.pform` file from disk. While the app is running, save the `.pform` file and the window updates right away. If the file has a mistake, a red bar explains it and the last working layout stays visible. Text typed into edits, checked boxes, selected items, slider positions and the open tab are kept across a reload.

What needs a restart: changes to `.pas` code, and new event handlers.

## Layout

Containers place their children one after another:

- `TColumn` stacks children top to bottom; `TRow` places them left to right. The form itself is a column.
- `Gap`: space between children. `Padding`: space inside the edges.
- `Align` (across the stacking direction): `Stretch` (default for columns), `Start`, `Center` (default for rows), `End`.
- `Justify` (along the stacking direction): `Start`, `Center`, `End`, `SpaceBetween`.
- `Grow`: a child with `Grow = 1` takes the free space; `Grow = 2` takes twice as much as `Grow = 1`.
- `Width` / `Height`: fixed size in pixels; `0` (the default) means "as big as the content".
- When a row is too narrow, its growing children (`Grow`) give up width, down to 48 pixels. If the controls still do not fit, the last ones are cut off; `pastel check` (and the editor) warns about such rows at the form's size.

## Controls

All controls have `Width`, `Height`, `Grow`, `Visible`, `Enabled`, `Hint` (a tooltip) and `PopupMenu` (a right-click menu). Every control with a `.pform` and a code example: [controls.md](controls.md). Your own controls: [components.md](components.md).

| Control | Properties | Events |
|---|---|---|
| `TForm` | `Title`, window properties (see above), `Padding` (24), `Gap` (12), `Color`, `Appearance` (`Light`, `Dark`, `System`) and the column properties | `OnCreate`, `OnCloseQuery`, `OnClose`, `OnResize` |
| `TColumn`, `TRow` | `Gap`, `Padding`, `Align`, `Justify`, `Color`, `Radius`, `BorderColor`, `BorderWidth` | |
| `TCard` | Like `TColumn`, with a background, border, rounded corners and padding | |
| `TScrollBox` | A column that scrolls when its content is taller than it | |
| `TTabControl`, `TTabSheet` | Pages with tabs: `TabIndex`; a sheet has a `Caption` | `OnChange` |
| `TSpacer` | Empty space with `Grow = 1` | |
| `TLabel` | `Text`, `FontSize` (14), `Bold`, `Color`, `TextAlign` (`Left`, `Center`, `Right`), `WordWrap` | |
| `TButton` | `Text`, `Icon` (`'save'`, `'add'`...), `Style` (`Primary`, `Secondary`, `Danger`, `Flat`), `Action`, `ModalResult`, `Default`, `Cancel` | `OnClick` |
| `TEdit` | `Text`, `Placeholder`, `Password`, `ReadOnly`, `MaxLength` | `OnChange`, `OnSubmit` (Enter key) |
| `TMemo` | Several lines: `Text`, `Lines`, `WordWrap`, `Placeholder`, `ReadOnly` | `OnChange` |
| `TCheckBox`, `TSwitch`, `TRadioButton` | `Text`, `Checked`; radio buttons with the same parent are one group | `OnChange` |
| `TComboBox` | A drop-down list: `Items = ('A', 'B')`, `ItemIndex`, `Text`, `Placeholder` | `OnChange` |
| `TListBox` | `Items`, `ItemIndex`, `ItemHeight`; only the visible rows are drawn, so long lists stay fast | `OnChange`, `OnDblClick` |
| `TImage` | `FileName` (from `assets/`), `Fit` (`Contain`, `Cover`, `Stretch`, `Center`) | |
| `TProgressBar` | `Position`, `Max`, `Indeterminate` | |
| `TSlider` | `Position`, `Min`, `Max`, `Step` | `OnChange` |
| `TSpinner` | `Active` | |
| `TSplitter` | Between two controls of a row or column; dragging it changes the `Width`/`Height` of the one before it; `MinSize` | `OnMoved` |
| `TToolBar`, `TStatusBar` | Rows at the top and bottom of a form: flat buttons (`Style = Flat`); `Text` or labels | |
| `TDatePicker`, `TCalendarView` | A date: `DateText = '2026-11-01'`, `Placeholder`; `Date`, `HasDate`, `Clear` from code | `OnChange`, `OnPick` |
| `TTimeEdit`, `TNumberEdit`, `TCurrencyEdit` | A time (`Step` minutes), a whole number (`Min`, `Max`, `Step`, `Value`), an amount (`Symbol`, `Decimals`, `Value`) — [controls.md](controls.md#dates-numbers-and-money) | `OnChange` |
| `TGrid`, `TListView` | A table: `TGridColumn` children (`Title`, `Field`, `Width`), `Editable`, `Sortable`; `LoadJson` from code | `OnChange`, `OnDblClick`, `OnCellEdit` |
| `TTreeView` | A tree: `Items = ('Documents', '  Letters')` | `OnChange`, `OnDblClick` |
| `TDataBinding` | Fills edits from a record and back: `Fields = ('NameEdit', 'EmailEdit')` | |
| `TMenuBar`, `TMenuItem`, `TPopupMenu` | Menus: `Caption` (`'-'` is a line), `ShortCut = 'Ctrl+S'`, `Checked`, `Action`; items inside items are submenus | `OnClick` |
| `TAction` | One command for a menu item and a button: `Caption`, `ShortCut`, `Enabled`, `Checked` | `OnExecute` |
| `TTimer` | `Interval` (ms), `Enabled` | `OnTimer` |

Keyboard: `Tab` / `Shift+Tab` move the focus, `Enter` or `Space` presses a focused button, `Enter` in a dialog presses its `Default` button and `Escape` its `Cancel` button, `F10` or `Alt` opens the menu bar, the `Menu` key or `Shift+F10` opens a control's popup menu. In edits: selection with the mouse and `Shift`, `Ctrl+A`, `Ctrl+C`/`X`/`V`, `Ctrl+Z`/`Y`, word moves with `Ctrl`.

## Testing a form without a window

Apps can run a script of UI actions and quit, which is useful for tests and CI:

```
type NameEdit Ayşe
click SendButton
expect Greeting Hello, Ayşe
shot screenshot.png
```

```sh
PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=ui.txt ./build/linux/debug/myapp
```

Commands:

- `click <name> [x y]`, `doubleclick`, `rightclick`, `hover <name>`, `wheel <name> <dy>`, `drag <name> <dx> <dy>` (press in its middle, move, let go: splitters, sliders) – menu items and tab sheets can be clicked by name too
- `type <name> <text>` – `\n` presses Enter
- `key ctrl+a`, `key shift+down`, `key f10`, `key enter|tab|escape|backspace|delete|up|down|left|right|home|end|space`
- `expect <name> <text>` checks the text; `expect <name>.<property> <value>` any property (`expect Agree.Checked True`, `expect HomeForm.Title Notes`)
- `set <name>.<property> <value>` sets a property like a `.pform` line does (`set DueDate.DateText 2026-11-01`)
- `wait <ms>` (lets timers and threads run), `print <name>`, `resize <w> <h>`, `shot <file.png>`, `reload`, `close`, `quit`

Dialogs are scripted like everything else: the lines after the one that opened a dialog act on it (`click YesButton`, `type FileNameEdit notes.txt\n`). The exit code is 1 if an `expect` fails. `PASTEL_HEADLESS=1` draws into memory without opening a window, so no display is needed; `PASTEL_SCALE=2` draws at double size and `PASTEL_THEME=dark` in the dark theme.
