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
- `Delete` removes the selected control

Every change is an ordinary edit of the `.pform` text, so `Ctrl+Z` in the editor undoes it.

## Hot reload

`pastel run` builds a debug version that reads the `.pform` file from disk. While the app is running, save the `.pform` file and the window updates right away. If the file has a mistake, a red bar explains it and the last working layout stays visible.

What needs a restart: changes to `.pas` code, and new event handlers. Note that controls are recreated on reload, so text typed into them is reset.

## Layout

Containers place their children one after another:

- `TColumn` stacks children top to bottom; `TRow` places them left to right. The form itself is a column.
- `Gap`: space between children. `Padding`: space inside the edges.
- `Align` (across the stacking direction): `Stretch` (default for columns), `Start`, `Center` (default for rows), `End`.
- `Justify` (along the stacking direction): `Start`, `Center`, `End`, `SpaceBetween`.
- `Grow`: a child with `Grow = 1` takes the free space; `Grow = 2` takes twice as much as `Grow = 1`.
- `Width` / `Height`: fixed size in pixels; `0` (the default) means "as big as the content".

## Controls

All controls have `Width`, `Height`, `Grow`, `Visible` and `Enabled`.

| Control | Properties | Events |
|---|---|---|
| `TForm` | `Title`, window properties (see above), `Padding` (24), `Gap` (12), `Color` and the column properties | `OnCreate`, `OnCloseQuery`, `OnClose`, `OnResize` |
| `TColumn`, `TRow` | `Gap`, `Padding`, `Align`, `Justify`, `Color`, `Radius`, `BorderColor`, `BorderWidth` | |
| `TCard` | Like `TColumn`, with a white background, border, rounded corners and padding | |
| `TSpacer` | Empty space with `Grow = 1` | |
| `TLabel` | `Text`, `FontSize` (14), `Bold`, `Color`, `TextAlign` (`Left`, `Center`, `Right`) | |
| `TButton` | `Text`, `Style` (`Primary`, `Secondary`, `Danger`) | `OnClick` |
| `TEdit` | `Text`, `Placeholder` | `OnChange`, `OnSubmit` (Enter key) |

Keyboard: `Tab` / `Shift+Tab` move between buttons and edits, `Enter` or `Space` presses a focused button, `Ctrl+C` / `Ctrl+V` copy and paste in an edit.

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

Commands: `click <name>`, `hover <name>`, `type <name> <text>`, `key enter|tab|backspace|delete|left|right|home|end|space`, `expect <name> <text>`, `print <name>`, `resize <w> <h>`, `close`, `shot <file.png>`, `sleep <ms>`, `quit`. The exit code is 1 if an `expect` fails. `PASTEL_HEADLESS=1` draws into memory without opening a window, so no display is needed.
