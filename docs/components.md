# Writing components

Like in Delphi, you can add your own components to Pastel. They are used in `.pform` files and appear in the VS Code designer's toolbox, next to the built-in ones. There are two kinds:

| Kind | Examples | Base class | Registered with |
|---|---|---|---|
| **Control**: drawn on the form, the user sees and uses it | a star rating, a date picker, an amount field | `TControl` (or a control to build on, like `TEdit`) | `RegisterControl` |
| **Non-visual component**: part of the form, but not drawn | a timer, an action, a connection to a service | `TComponent` | `RegisterNonVisual` |

Complete examples are in [`examples/components`](../examples/components) (a library with `TStarRating` and `TFormMemory`); `TCurrencyEdit` and `TDatePicker`, explained below, are in the framework's [`pastel.inputs.pas`](../framework/src/pastel.inputs.pas) and [`examples/components-demo`](../examples/components-demo) (an app that uses them). This page explains them step by step.

## Units and `uses`: how code finds other code

A Pascal **unit** is one file with a name (`unit StarRating;`). What is in its `interface` part can be used by other units that name it in their `uses` list, like `use` in PHP or `import` in other languages:

```pascal
uses
  SysUtils, Pastel.UI, Pastel.Inputs, Prices;     // Prices: src/services/prices.pas of this project or of a library
```

Units are found in the project's `src/` folder (and its sub-folders), in the libraries the project depends on, and in the framework (`Pastel.*`). For the controls in a `.pform` file you write no `uses`: the code Pastel generates for the form names their units.

## A control of your own

```sh
pastel new control StarRating
```

writes `src/controls/starrating.pas`, a working control to change. Every control answers four questions:

**1. How big is it?** `Measure` gets the width that is available and gives the size the control wants. The layout (rows, columns, `Grow`, `Width`/`Height` in the `.pform`) decides the final size, which is in `Bounds` when the control is drawn.

```pascal
procedure TStarRating.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  W := FMax * FStarSize;
  H := FStarSize;
end;
```

**2. How does it look?** `Paint` draws inside `Bounds` with the canvas `C` (see [Drawing](#drawing)). Use the colors of `Theme`, so the control fits the light and the dark theme and `assets/theme.toml`.

```pascal
procedure TStarRating.Paint(C: TCanvas32);
var
  F: TPastelFont;
  I: Integer;
  Col: TColor32;
begin
  F := GetFont(FStarSize * 3 div 4);
  for I := 1 to FMax do
  begin
    if I <= FValue then Col := $FFF59E0B else Col := Theme.Border;
    C.DrawText(F, Bounds.X + (I - 1) * FStarSize, Bounds.Y, '★', Col);
  end;
end;
```

**3. What does it do with the mouse and the keyboard?** Override what you need: `MouseDown(X, Y)`, `MouseMove`, `MouseUp(X, Y, Inside)`, `MouseWheel(DX, DY)`, `KeyDown(Key, Shift, Ctrl)` (return `True` when the key was used), `TextInput(S)` (typed text). A control that should get the keyboard focus returns `True` from `Focusable`. `IsFocused` and `IsHovered` tell its state while painting.

```pascal
procedure TStarRating.MouseDown(X, Y: Integer);
begin
  Value := (X - Bounds.X) div FStarSize + 1;
end;

function TStarRating.KeyDown(Key: LongInt; Shift, Ctrl: Boolean): Boolean;
begin
  Result := True;
  case Key of
    KEY_RIGHT: Value := FValue + 1;
    KEY_LEFT: Value := FValue - 1;
  else
    Result := False;      { not ours: the form uses it (Tab, shortcuts...) }
  end;
end;
```

**4. What can be set in the `.pform` and the designer?** The `published` properties and events. They appear in the designer's properties panel, are checked by `pastel check`, and are set when the form loads:

```pascal
  published
    property Value: Integer read FValue write SetValue default 0;
    property Max: Integer read FMax write SetMax default 5;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
```

In a setter, call **`Invalidate`** when only the look changes (Pastel paints that control again) and **`Changed`** when the size may change (layout and paint):

```pascal
procedure TStarRating.SetValue(AValue: Integer);
begin
  if FValue = AValue then
    Exit;
  FValue := AValue;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;
```

Last, register the class at the end of the unit, so `.pform` files know it:

```pascal
initialization
  RegisterControl(TStarRating);
end.
```

Use it like any control:

```
object Rating: TStarRating
  Value = 3
  OnChange = RatingChange
end
```

Saving the unit in VS Code updates the toolbox and the designer's picture: `pastel schema`, `check` and `preview` compile a copy of the pastel tool together with your controls (in `build/designer/`), again whenever a control changes.

## Building on an existing control

Often a control is an existing one with a little more. `TCurrencyEdit` is a `TEdit` with a `Value` in money: it inherits typing, selection, the clipboard, undo and the look, and adds three things:

```pascal
type
  TCurrencyEdit = class(TEdit)
  protected
    procedure TextInput(const S: string); override;   { only digits and separators get in }
    procedure FocusLost; override;                    { writes the amount nicely when leaving }
  public
    property Value: Currency read GetValue write SetValue;
  published
    property Symbol: string read FSymbol write SetSymbol;
  end;

procedure TCurrencyEdit.TextInput(const S: string);
var
  I: Integer;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9', '.', ',', '-'] then
      Clean := Clean + S[I];
  if Clean <> '' then
    inherited TextInput(Clean);      { TEdit does the rest }
end;
```

`inherited` calls the base class: the control keeps all of `TEdit`'s behavior and changes only what it overrides. The properties `TEdit` publishes (`Text`, `Placeholder`, `OnChange`...) stay in the designer.

## A control with a popup

`TDatePicker` shows a date and opens a calendar under itself. The calendar is a `TPopup` (a floating box that closes with Escape or a click outside) with a control in it:

```pascal
procedure TDatePicker.DropDown;
begin
  if FPopup = nil then
  begin
    FPopup := TPopup.Create(Self);
    FCalendar := TCalendarView.Create(FPopup);
    FCalendar.Name := 'Calendar';        { test scripts can click it }
    FCalendar.Parent := FPopup;
    FCalendar.OnPick := @Picked;
  end;
  FCalendar.ShowDate(FDate);
  FPopup.Popup(ParentForm, Bounds);      { below the picker (above when there is no room) }
  FCalendar.SetFocus;
end;

procedure TDatePicker.Picked(Sender: TObject);
begin
  Date := FCalendar.Selected;
  FPopup.Close;
  SetFocus;
end;
```

`TPopup.ShowModal(Form)` instead shows it in the middle with the window dimmed and waits until it is closed: that is how Pastel's own dialogs work.

## A non-visual component

A component without a place on the form derives from `TComponent` (or from another component). Its published properties are set in the `.pform` like a control's; the form owns it and frees it.

`TFormMemory` remembers what the user entered, between runs. It builds on `TDataBinding`, which already knows how to read and set controls:

```pascal
type
  TFormMemory = class(TDataBinding)
  public
    function Restore: Boolean;     { the controls get the stored values }
    procedure Store;               { the controls' values go to the file }
  published
    property FileName: string read FFileName write FFileName;
  end;

procedure TFormMemory.Store;
var
  O: TJSONObject;
begin
  O := ToJson;                                         { from TDataBinding }
  try
    WriteText(FilePath, O.FormatJSON);
  finally
    O.Free;
  end;
end;

initialization
  RegisterNonVisual(TFormMemory);
```

```
object Memory: TFormMemory
  Fields = ('CustomerEdit', 'PriceEdit')
  FileName = 'order-form.json'
end
```

```pascal
procedure THomeForm.FormCreate(Sender: TObject);
begin
  Memory.Restore;
end;

procedure THomeForm.FormClose(Sender: TObject);
begin
  Memory.Store;
end;
```

In the designer's toolbox, non-visual components are marked with ◇; adding one puts it at the top of the `.pform`.

## Sharing components between projects

Put the components into a **library** project and let apps depend on it, like a Composer or npm package (but from a folder; a package registry is planned):

```sh
pastel new lib components
```

```
components/
  pastel.toml            type = "lib"
  src/controls/          the controls and components (RegisterControl / RegisterNonVisual)
  src/services/          other units (money, calendar...): no window needed, easy to test
  tests/                 pastel test
```

In the app's `pastel.toml`:

```toml
[dependencies]
components = { path = "../components" }
```

Now the library's controls are in the app's `.pform` files and the designer's toolbox (at the front, in italics), and its other units can be named in `uses`. A library may depend on other libraries.

## Testing components

- **The logic** (parsing amounts, calendar arithmetic) belongs in units without a window, tested with `pastel test`: [`inputs_test.pas`](../framework/tests/tests/inputs_test.pas), [`starrating_test.pas`](../examples/components/tests/starrating_test.pas).
- **The control in a form**: a UI script drives it like a user, without a screen: [`tests/ui.txt`](../examples/components-demo/tests/ui.txt).

```
set DuePicker.DateText 2026-11-01     # set a property, like in the .pform
click DuePicker                       # opens the calendar
key right
key enter
expect DuePicker.DateText 2026-11-02
click Rating 110 10                   # x y inside the control: the fourth star
expect Rating.Value 4
```

```sh
PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/linux/debug/components-demo
```

`PASTEL_CHECK_REPAINT=1` also checks that `Invalidate` is called where needed: a control that changes its look without it is reported.

## Drawing

The canvas `C` in `Paint` (`TCanvas32`, unit `Pastel.Graphics`) works in the same units as the layout; Pastel scales for high-DPI screens.

| | |
|---|---|
| `C.FillRect(X, Y, W, H, Color)` | A rectangle |
| `C.FillRoundRect(X, Y, W, H, Radius, Color)`, `C.StrokeRoundRect(X, Y, W, H, Radius, Thickness, Color)` | Rounded, filled or outlined |
| `C.FillCircle(CX, CY, Radius, Color)` | |
| `C.DrawLine(X1, Y1, X2, Y2, Thickness, Color)` | Smooth lines |
| `C.DrawText(Font, X, Y, Text, Color)` | `Font := GetFont(Size, Bold)`; `Font.TextWidth(S)`, `Font.LineHeight` |
| `C.DrawBitmap(Bitmap, X, Y, W, H)` | A `TBitmap32` (PNG/JPEG loaded with `LoadFromFile`/`LoadFromStream`) |
| `C.PushClip(Rect)` … `C.PopClip` | Draw only inside a rectangle |

Colors: `RGB(79, 70, 229)`, `RGBA(...)`, `$FF4F46E5` (`$AARRGGBB`), `WithAlpha(Color, 128)`, `Mix(A, B, 0.5)`, and the theme's: `Theme.Accent`, `Theme.OnAccent`, `Theme.Text`, `Theme.TextMuted`, `Theme.Placeholder`, `Theme.Surface`, `Theme.Background`, `Theme.Border`, `Theme.BorderHover`, `Theme.FocusRing`, `Theme.SecondaryHover`, `Theme.SecondaryPressed`, `Theme.Danger`, `Theme.Disabled`, `Theme.Radius`, `Theme.FontSize`.

## Checklist for a good component

- Comment above the class and every published property: it becomes the tooltip in the designer and the API reference.
- Theme colors, not fixed ones (except for what has a meaning, like the stars' gold).
- `Invalidate` / `Changed` in every setter that changes the look / the size.
- Keyboard: `Focusable`, a focus ring when `IsFocused` (`Theme.FocusRing`), and the keys people expect.
- `Enabled = False` looks grey (`Theme.Disabled`) and ignores input.
- The logic in a separate unit with tests; a UI script for the control.
- An entry in the project's documentation with a `.pform` and a code example (like [controls.md](controls.md)).
