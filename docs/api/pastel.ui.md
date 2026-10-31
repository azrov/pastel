# Pastel.UI

Controls, layout and input handling.

  Controls are TComponent descendants with published properties, so they can
  be created from .pform files the same way Delphi creates forms from .dfm.
  Layout is a small flexbox-style model: TColumn and TRow place children one
  after another, Grow shares the free space, Align/Justify position them.

`uses Pastel.UI;` · source: [framework/src/pastel.ui.pas](../../framework/src/pastel.ui.pas)

**Contents:** [TAlignItems](#talignitems) · [TJustify](#tjustify) · [TTextAlign](#ttextalign) · [TButtonStyle](#tbuttonstyle) · [TCursorKind](#tcursorkind) · [TWindowState](#twindowstate) · [TControl](#tcontrol) · [TBox](#tbox) · [TColumn](#tcolumn) · [TRow](#trow) · [TCard](#tcard) · [TSpacer](#tspacer) · [TLabel](#tlabel) · [TButton](#tbutton) · [TEdit](#tedit) · [TForm](#tform) · [TTheme](#ttheme) · [RegisterControl](#registercontrol) · [FindControlClass](#findcontrolclass) · [ControlClassCount](#controlclasscount) · [ControlClassAt](#controlclassat)

## Types

### TAlignItems

```pascal
type TAlignItems = (aiStretch, aiStart, aiCenter, aiEnd)
```

- `aiStretch`
- `aiStart`
- `aiCenter`
- `aiEnd`
### TJustify

```pascal
type TJustify = (jsStart, jsCenter, jsEnd, jsSpaceBetween)
```

- `jsStart`
- `jsCenter`
- `jsEnd`
- `jsSpaceBetween`
### TTextAlign

```pascal
type TTextAlign = (taLeft, taCenter, taRight)
```

- `taLeft`
- `taCenter`
- `taRight`
### TButtonStyle

```pascal
type TButtonStyle = (bsPrimary, bsSecondary, bsDanger)
```

- `bsPrimary`
- `bsSecondary`
- `bsDanger`
### TCursorKind

```pascal
type TCursorKind = (ckArrow, ckIBeam, ckHand)
```

- `ckArrow`
- `ckIBeam`
- `ckHand`
### TWindowState

```pascal
type TWindowState = (wsNormal, wsMaximized, wsMinimized, wsFullScreen)
```

- `wsNormal`
- `wsMaximized`
- `wsMinimized`
- `wsFullScreen`
### TControl

```pascal
type TControl = class(TComponent)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Invalidate` | needs repaint only |
| `procedure SetFocus` |  |
| `function HitTest(X: Integer; Y: Integer): TControl` |  |
| `function ParentForm: TForm` |  |
| `procedure GetSize(AvailWidth: Integer; out W: Integer; out H: Integer)` | Preferred size including explicit Width/Height. |
| `property Parent: TControl` |  |
| `property Children[Index: Integer]: TControl` |  |
| `property ChildCount: Integer` |  |
| `property Bounds: TRectI` |  |
| `property Width: Integer` |  |
| `property Height: Integer` |  |
| `property Grow: Integer` |  |
| `property Visible: Boolean` |  |
| `property Enabled: Boolean` |  |

### TBox

```pascal
type TBox = class(TControl)
```

A container that stacks its children vertically or horizontally.

| | |
|---|---|
| `property Horizontal: Boolean` | True for TRow: children are placed left to right. |
| `property Gap: Integer` |  |
| `property Padding: Integer` |  |
| `property Align: TAlignItems` |  |
| `property Justify: TJustify` |  |
| `property Color: TColor32` |  |
| `property BorderColor: TColor32` |  |
| `property BorderWidth: Integer` |  |
| `property Radius: Integer` |  |

### TColumn

```pascal
type TColumn = class(TBox)
```

### TRow

```pascal
type TRow = class(TBox)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |

### TCard

```pascal
type TCard = class(TBox)
```

A white rounded panel with a border.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |

### TSpacer

```pascal
type TSpacer = class(TControl)
```

Empty space that takes the free room in a row or column.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |

### TLabel

```pascal
type TLabel = class(TControl)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Font: TPastelFont` |  |
| `property Text: string` |  |
| `property FontSize: Integer` |  |
| `property Bold: Boolean` |  |
| `property Color: TColor32` |  |
| `property TextAlign: TTextAlign` |  |

### TButton

```pascal
type TButton = class(TControl)
```

| | |
|---|---|
| `procedure Click` |  |
| `property Text: string` |  |
| `property Style: TButtonStyle` |  |
| `property OnClick: TNotifyEvent` |  |

### TEdit

```pascal
type TEdit = class(TControl)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Font: TPastelFont` |  |
| `property CaretPos: Integer` |  |
| `property Text: string` |  |
| `property Placeholder: string` |  |
| `property OnChange: TNotifyEvent` |  |
| `property OnSubmit: TNotifyEvent` |  |

### TForm

```pascal
type TForm = class(TBox)
```

The root of a window. Owns all controls created from its .pform file.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure Notification(AComponent: TComponent; Operation: TOperation)` |  |
| `procedure ClearControls` | Removes every control created from the .pform (used by hot reload). |
| `procedure Layout(AWidth: Integer; AHeight: Integer)` |  |
| `procedure Render(C: TCanvas32)` |  |
| `procedure FocusControl(C: TControl)` |  |
| `procedure FocusNext(Backward: Boolean)` |  |
| `procedure HandleMouseMove(X: Integer; Y: Integer)` |  |
| `procedure HandleMouseDown(X: Integer; Y: Integer)` |  |
| `procedure HandleMouseUp(X: Integer; Y: Integer)` |  |
| `procedure HandleMouseLeave` |  |
| `procedure HandleKeyDown(Key: LongInt; Shift: Boolean; Ctrl: Boolean)` |  |
| `procedure HandleTextInput(const S: string)` |  |
| `function CurrentCursor: TCursorKind` |  |
| `function FindControl(const AName: string): TControl` |  |
| `procedure BindControls` | Points the form's fields at the controls created from the .pform. Overridden by the code Pastel generates from the .pform file. |
| `function BindControl(const AName: string; AClass: TControlClass): TControl` | Used by BindControls: finds a control and checks its type. |
| `property Focused: TControl` |  |
| `property Hovered: TControl` |  |
| `property FocusVisible: Boolean` | True when focus came from the keyboard (Tab): buttons show a focus ring. |
| `procedure Maximize` | Window commands. They take effect on the next pass of the event loop. |
| `procedure Minimize` |  |
| `procedure Restore` |  |
| `procedure Close` |  |
| `function CloseQuery: Boolean` | Asks OnCloseQuery; True if the window may close. |
| `procedure WindowStateChanged(AState: TWindowState)` | Called by the platform layer when the user changed the window state. |
| `property Title: string` |  |
| `property Resizable: Boolean` | Can the user resize (and maximize) the window? |
| `property MinWidth: Integer` |  |
| `property MinHeight: Integer` |  |
| `property WindowState: TWindowState` |  |
| `property AlwaysOnTop: Boolean` |  |
| `property OnCreate: TNotifyEvent` |  |
| `property OnCloseQuery: TCloseQueryEvent` | Set CanClose to False to keep the window open, e.g. to ask about unsaved work. |
| `property OnClose: TNotifyEvent` |  |
| `property OnResize: TNotifyEvent` |  |

### TTheme

```pascal
type TTheme = record
```

| | |
|---|---|
| `Background: TColor32` |  |
| `Surface: TColor32` |  |
| `Text: TColor32` |  |
| `TextMuted: TColor32` |  |
| `Placeholder: TColor32` |  |
| `Accent: TColor32` |  |
| `AccentHover: TColor32` |  |
| `AccentPressed: TColor32` |  |
| `OnAccent: TColor32` |  |
| `Secondary: TColor32` |  |
| `SecondaryHover: TColor32` |  |
| `SecondaryPressed: TColor32` |  |
| `Danger: TColor32` |  |
| `DangerHover: TColor32` |  |
| `DangerPressed: TColor32` |  |
| `Border: TColor32` |  |
| `BorderHover: TColor32` |  |
| `FocusRing: TColor32` |  |
| `Disabled: TColor32` |  |
| `Radius: Integer` |  |
| `FontSize: Integer` |  |

## Other types

| | |
|---|---|
| `type TCloseQueryEvent = procedure(Sender: TObject; CanClose: Boolean)` |  |
| `type TControlClass = class of TControl` |  |
| `type TFormClass = class of TForm` |  |

## Routines

### RegisterControl

```pascal
procedure RegisterControl(AClass: TControlClass)
```

### FindControlClass

```pascal
function FindControlClass(const AName: string): TControlClass
```

### ControlClassCount

```pascal
function ControlClassCount: Integer
```

### ControlClassAt

```pascal
function ControlClassAt(Index: Integer): TControlClass
```

## Constants and variables

| | |
|---|---|
| `var Theme: TTheme` |  |
| `var NeedsLayout: Boolean` | Set by controls when something changed; the application loop reads them. |
| `var NeedsRepaint: Boolean` |  |
| `var CaretVisible: Boolean` | Caret blink phase, toggled by the application loop. |
| `var NeedsWindowSync: Boolean` | Set when window properties changed; the platform layer applies them. |
| `var CloseRequested: Boolean` | Set by TForm.Close; the application loop handles it. |
| `var ClipboardGetText: function : string` | Clipboard access, provided by the platform layer. |
| `var ClipboardSetText: procedure (const S : string)` |  |
| `const KEY_BACKSPACE = 8` | Platform-independent key codes (same values as SDL key codes). |
| `const KEY_TAB = 9` |  |
| `const KEY_ENTER = 13` |  |
| `const KEY_ESCAPE = 27` |  |
| `const KEY_SPACE = 32` |  |
| `const KEY_DELETE = 127` |  |
| `const KEY_RIGHT = $4000004F` |  |
| `const KEY_LEFT = $40000050` |  |
| `const KEY_HOME = $4000004A` |  |
| `const KEY_END = $4000004D` |  |
| `const KEY_KP_ENTER = $40000058` |  |
