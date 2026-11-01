# Pastel.UI

Controls, layout and input handling.

  Controls are TComponent descendants with published properties, so they can
  be created from .pform files the same way Delphi creates forms from .dfm.
  Layout is a small flexbox-style model: TColumn and TRow place children one
  after another, Grow shares the free space, Align/Justify position them.

`uses Pastel.UI;` · source: [framework/src/pastel.ui.pas](../../framework/src/pastel.ui.pas)

**Contents:** [TAlignItems](#talignitems) · [TJustify](#tjustify) · [TTextAlign](#ttextalign) · [TButtonStyle](#tbuttonstyle) · [TCursorKind](#tcursorkind) · [TWindowState](#twindowstate) · [TThemeMode](#tthememode) · [TControl](#tcontrol) · [TAction](#taction) · [TBox](#tbox) · [TColumn](#tcolumn) · [TRow](#trow) · [TCard](#tcard) · [TSpacer](#tspacer) · [TLabel](#tlabel) · [TButton](#tbutton) · [TEditState](#teditstate) · [TVisualLine](#tvisualline) · [TCustomEdit](#tcustomedit) · [TEdit](#tedit) · [TMemo](#tmemo) · [TPopup](#tpopup) · [TTimer](#ttimer) · [TForm](#tform) · [TTheme](#ttheme) · [UseDarkTheme](#usedarktheme) · [SetThemeValue](#setthemevalue) · [InvalidateArea](#invalidatearea) · [RequestAnimation](#requestanimation) · [AnimationTime](#animationtime) · [RequestAnimation](#requestanimation) · [ProcessTimers](#processtimers) · [WrapText](#wraptext) · [RegisterControl](#registercontrol) · [FindControlClass](#findcontrolclass) · [ControlClassCount](#controlclasscount) · [ControlClassAt](#controlclassat) · [RegisterNonVisual](#registernonvisual) · [FindNonVisualClass](#findnonvisualclass) · [NonVisualClassCount](#nonvisualclasscount) · [NonVisualClassAt](#nonvisualclassat)

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
type TButtonStyle = (bsPrimary, bsSecondary, bsDanger, bsFlat)
```

bsFlat: no background until the mouse is on it (tool bars).

- `bsPrimary` bsFlat: no background until the mouse is on it (tool bars).
- `bsSecondary` bsFlat: no background until the mouse is on it (tool bars).
- `bsDanger` bsFlat: no background until the mouse is on it (tool bars).
- `bsFlat` bsFlat: no background until the mouse is on it (tool bars).
### TCursorKind

```pascal
type TCursorKind = (ckArrow, ckIBeam, ckHand, ckSizeWE, ckSizeNS)
```

- `ckArrow`
- `ckIBeam`
- `ckHand`
- `ckSizeWE`
- `ckSizeNS`
### TWindowState

```pascal
type TWindowState = (wsNormal, wsMaximized, wsMinimized, wsFullScreen)
```

- `wsNormal`
- `wsMaximized`
- `wsMinimized`
- `wsFullScreen`
### TThemeMode

```pascal
type TThemeMode = (tmLight, tmDark, tmSystem)
```

Light, dark, or what the computer is set to.

- `tmLight` Light, dark, or what the computer is set to.
- `tmDark` Light, dark, or what the computer is set to.
- `tmSystem` Light, dark, or what the computer is set to.
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
| `function ParentPopup: TPopup` | The popup the control is in, or nil. |
| `procedure GetSize(AvailWidth: Integer; out W: Integer; out H: Integer)` | Preferred size including explicit Width/Height. |
| `property Parent: TControl` |  |
| `property Children[Index: Integer]: TControl` |  |
| `property ChildCount: Integer` |  |
| `function IndexOfChild(C: TControl): Integer` |  |
| `property Bounds: TRectI` |  |
| `property Width: Integer` |  |
| `property Height: Integer` |  |
| `property Grow: Integer` |  |
| `property Visible: Boolean` |  |
| `property Enabled: Boolean` |  |
| `property Hint: string` | Shown in a tooltip when the mouse rests on the control. |
| `property PopupMenu: TControl` | A TPopupMenu shown on a right click (or the menu key). |

### TAction

```pascal
type TAction = class(TBasicAction)
```

A command with a caption and a keyboard shortcut, used by menu items and
buttons: one place for what happens, and for Enabled and Checked.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function Execute: Boolean` |  |
| `property Caption: string` |  |
| `property ShortCut: string` | Like 'Ctrl+S', 'Ctrl+Shift+Z', 'F5', 'Delete'. |
| `property Hint: string` |  |
| `property Enabled: Boolean` |  |
| `property Checked: Boolean` |  |
| `property OnExecute` |  |

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

A white rounded panel with a border (in the theme's colors).

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
| `function TextLines(AWidth: Integer): TStringArray` | The lines the text is shown in, at a width (line breaks and wrapping). |
| `property Text: string` |  |
| `property WordWrap: Boolean` | Break long text into lines at the label's width. |
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
| `procedure Notification(AComponent: TComponent; Operation: TOperation)` |  |
| `procedure Click` |  |
| `property Text: string` |  |
| `property Style: TButtonStyle` |  |
| `property Icon: string` | A built-in icon ('save', 'add', 'delete'...; see Pastel.Icons) before the text, or alone. |
| `property Action: TBasicAction` | A click runs the action (and Text, Enabled come from it when not set). |
| `property ModalResult: Integer` | In a dialog: a click closes it with this result (mrOk, mrCancel...). |
| `property Default: Boolean` | Enter in the dialog clicks it. |
| `property Cancel: Boolean` | Escape in the dialog clicks it. |
| `property OnClick: TNotifyEvent` |  |

### TEditState

```pascal
type TEditState = record
```

| | |
|---|---|
| `Text: string` |  |
| `Caret: Integer` |  |
| `Anchor: Integer` |  |

### TVisualLine

```pascal
type TVisualLine = record
```

| | |
|---|---|
| `StartPos: Integer` | byte range in Text, without the line break |
| `EndPos: Integer` | byte range in Text, without the line break |

### TCustomEdit

```pascal
type TCustomEdit = class(TControl)
```

Text editing for TEdit and TMemo: caret, selection with mouse and
keyboard, clipboard, undo/redo, scrolling; TMemo adds lines and wrapping.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `function Font: TPastelFont` |  |
| `procedure SelectAll` |  |
| `procedure CopyToClipboard` |  |
| `procedure CutToClipboard` |  |
| `procedure PasteFromClipboard` |  |
| `procedure Undo` |  |
| `procedure Redo` |  |
| `function CanUndo: Boolean` |  |
| `property CaretPos: Integer` |  |
| `property SelStart: Integer` | The selection: SelStart counts from 0 (bytes), like Delphi. |
| `property SelLength: Integer` |  |
| `property SelText: string` |  |
| `property Text: string` |  |
| `property Placeholder: string` |  |
| `property ReadOnly: Boolean` |  |
| `property MaxLength: Integer` | At most this many bytes; 0: no limit. |
| `property OnChange: TNotifyEvent` |  |

### TEdit

```pascal
type TEdit = class(TCustomEdit)
```

One line of text.

| | |
|---|---|
| `property Text` |  |
| `property Placeholder` |  |
| `property ReadOnly` |  |
| `property MaxLength` |  |
| `property Password: Boolean` | Shows dots instead of the text. |
| `property OnChange` |  |
| `property OnSubmit: TNotifyEvent` | Enter was pressed. |

### TMemo

```pascal
type TMemo = class(TCustomEdit)
```

Text with several lines; scrolls, wraps long lines.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Lines: TStrings` | The text as lines: Memo.Lines.Add('...'), Memo.Lines[0]. |
| `property Text` |  |
| `property Placeholder` |  |
| `property ReadOnly` |  |
| `property MaxLength` |  |
| `property WordWrap: Boolean` |  |
| `property OnChange` |  |

### TPopup

```pascal
type TPopup = class(TBox)
```

A panel shown above the form: drop-down lists, menus, dialogs.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `procedure Popup(Form: TForm; const Anchor: TRectI; PlaceRight: Boolean = False)` | Shows it on Form, below (or above) Anchor; centered when not given. |
| `procedure PopupCentered(Form: TForm)` |  |
| `function ShowModal(Form: TForm): Integer` | Shows it centered with the form dimmed behind it and waits until it is closed; the result is ModalResult. |
| `procedure Close(AModalResult: Integer = 0)` |  |
| `property Modal: Boolean` |  |
| `property Closed: Boolean` |  |
| `property Shown: Boolean` |  |
| `property ModalResult: Integer` |  |
| `property ActiveControl: TControl` | Gets the focus when a modal popup opens; the first focusable control when nil. |
| `property OnClose: TNotifyEvent` |  |

### TTimer

```pascal
type TTimer = class(TComponent)
```

Calls OnTimer every Interval milliseconds while Enabled.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `property Interval: Integer` |  |
| `property Enabled: Boolean` |  |
| `property OnTimer: TNotifyEvent` |  |

### TForm

```pascal
type TForm = class(TBox)
```

The root of a window. Owns all controls created from its .pform file.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Notification(AComponent: TComponent; Operation: TOperation)` |  |
| `function HitTest(X: Integer; Y: Integer): TControl` |  |
| `procedure ShowPopup(P: TPopup)` | Popups (drop-downs, menus, dialogs), the last one on top. |
| `procedure ClosePopup(P: TPopup)` |  |
| `function PopupCount: Integer` |  |
| `function PopupAt(Index: Integer): TPopup` |  |
| `function TopPopup: TPopup` |  |
| `function UpdateTooltip(NowMs: QWord): Boolean` | Shows or hides the tooltip; the application calls it while the mouse rests. |
| `procedure HideTooltip` |  |
| `procedure HandleMouseWheel(DX: Integer; DY: Integer)` |  |
| `procedure HandleContextMenu(X: Integer; Y: Integer)` | Right button: the control's PopupMenu. |
| `procedure ClearControls` | Removes every control created from the .pform (used by hot reload). |
| `procedure Layout(AWidth: Integer; AHeight: Integer)` |  |
| `procedure Render(C: TCanvas32)` |  |
| `procedure RenderArea(C: TCanvas32; const Area: TRectI)` | Paints only Area (layout units): what changed since the last Render. |
| `procedure FocusControl(C: TControl)` |  |
| `procedure FocusNext(Backward: Boolean)` |  |
| `procedure HandleMouseMove(X: Integer; Y: Integer)` |  |
| `procedure HandleMouseDown(X: Integer; Y: Integer; Button: Integer = 1; Clicks: Integer = 1)` |  |
| `procedure HandleMouseUp(X: Integer; Y: Integer; Button: Integer = 1)` |  |
| `procedure HandleMouseLeave` |  |
| `procedure HandleKeyDown(Key: LongInt; Shift: Boolean; Ctrl: Boolean)` |  |
| `procedure HandleTextInput(const S: string)` |  |
| `function CurrentCursor: TCursorKind` |  |
| `function FindControl(const AName: string): TControl` |  |
| `procedure BindControls` | Points the form's fields at the controls created from the .pform. Overridden by the code Pastel generates from the .pform file. |
| `function BindControl(const AName: string; AClass: TControlClass): TControl` | Used by BindControls: finds a control and checks its type. |
| `function BindComponent(const AName: string; AClass: TComponentClass): TComponent` | The same for components without a place on the form (TTimer...). |
| `property Focused: TControl` |  |
| `property Hovered: TControl` |  |
| `property Captured: TControl` |  |
| `property ClickCount: Integer` | 2 for a double click, 3 for a triple click (in MouseDown). |
| `property MouseButton: Integer` | 1 left, 2 middle, 3 right (in MouseDown). |
| `property ShiftDown: Boolean` |  |
| `property MouseX: Integer` |  |
| `property MouseY: Integer` |  |
| `property FocusVisible: Boolean` | True when focus came from the keyboard (Tab): buttons show a focus ring. |
| `procedure Maximize` | Window commands. They take effect on the next pass of the event loop. |
| `procedure Minimize` |  |
| `procedure Restore` |  |
| `procedure Close` |  |
| `function CloseQuery: Boolean` | Asks OnCloseQuery; True if the window may close. |
| `function ShowModal: Integer` | Shows this form as a dialog above the main window and waits until it is closed: by a button with a ModalResult, ModalResult := ..., Close (mrCancel) or Escape. Returns the ModalResult. |
| `property ModalResult: Integer` | Setting it in a dialog form closes the dialog with that result. |
| `procedure WindowStateChanged(AState: TWindowState)` | Called by the platform layer when the user changed the window state. |
| `property Title: string` |  |
| `property Resizable: Boolean` | Can the user resize (and maximize) the window? |
| `property MinWidth: Integer` |  |
| `property MinHeight: Integer` |  |
| `property WindowState: TWindowState` |  |
| `property AlwaysOnTop: Boolean` |  |
| `property Appearance: TThemeMode` | The colors of the app: Light, Dark or System (as the computer is set). |
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
| `Shadow: TColor32` |  |
| `Backdrop: TColor32` |  |
| `Selection: TColor32` |  |
| `TooltipBack: TColor32` |  |
| `TooltipText: TColor32` |  |
| `Radius: Integer` |  |
| `FontSize: Integer` |  |
| `Dark: Boolean` |  |

## Other types

| | |
|---|---|
| `type TCloseQueryEvent = procedure(Sender: TObject; CanClose: Boolean)` |  |
| `type TControlClass = class of TControl` |  |
| `type TEditStates = array of TEditState` |  |
| `type TFormClass = class of TForm` |  |

## Routines

### UseDarkTheme

```pascal
procedure UseDarkTheme(Dark: Boolean)
```

Light or dark colors for every control; repaints.

### SetThemeValue

```pascal
function SetThemeValue(const Name: string; const Value: string): Boolean
```

Changes one theme value by its name in assets/theme.toml: 'accent',
'background', 'surface', 'text', 'border', 'danger', ... are colors
('#0EA5E9'); 'radius' and 'font_size' numbers. Hover and pressed shades
follow the color. False for an unknown name or a bad value.

### InvalidateArea

```pascal
procedure InvalidateArea(const R: TRectI)
```

Asks for a repaint of a part of the window (layout units).

### RequestAnimation

```pascal
procedure RequestAnimation
```

Asks for another frame soon (animations): of the whole window, or only
of the control that moves.

### AnimationTime

```pascal
function AnimationTime: QWord
```

The clock animations are drawn by (milliseconds); FrozenTime <> 0 stops it.

### RequestAnimation

```pascal
procedure RequestAnimation(Control: TControl)
```

### ProcessTimers

```pascal
function ProcessTimers(NowMs: QWord): Integer
```

Runs the timers that are due; the milliseconds until the next one (-1: none).

### WrapText

```pascal
function WrapText(Font: TPastelFont; const S: string; Width: Integer): TStringArray
```

Splits text into lines that fit Width (at spaces; long words are broken).

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

### RegisterNonVisual

```pascal
procedure RegisterNonVisual(AClass: TComponentClass)
```

Components without a place on the form (TTimer...) that .pform files can create.

### FindNonVisualClass

```pascal
function FindNonVisualClass(const AName: string): TComponentClass
```

### NonVisualClassCount

```pascal
function NonVisualClassCount: Integer
```

### NonVisualClassAt

```pascal
function NonVisualClassAt(Index: Integer): TComponentClass
```

## Constants and variables

| | |
|---|---|
| `var Theme: TTheme` |  |
| `var ThemeCustomizer: procedure` | Runs after UseDarkTheme set up the light or dark colors: changes to Theme go here. Pastel.App applies assets/theme.toml with it. |
| `var KeyAlt: Boolean` | Alt is held (with KeyDown). |
| `var MainForm: TForm` | The main window's form; dialogs are shown on it. Set by Pastel.App. |
| `var PartialRepaint: Boolean` | False: always paint the whole window (PASTEL_FULL_REPAINT=1). |
| `const MinShrink = 48` | A growing control in a row that is too narrow gets no narrower than this. |
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
| `const KEY_UP = $40000052` |  |
| `const KEY_DOWN = $40000051` |  |
| `const KEY_PAGEUP = $4000004B` |  |
| `const KEY_PAGEDOWN = $4000004E` |  |
| `const KEY_INSERT = $40000049` |  |
| `const KEY_F1 = $4000003A` | F2 .. F12 follow |
| `const KEY_MENU = $40000076` |  |
| `const KEY_APPLICATION = $40000065` |  |
| `const mrNone = 0` | Results of dialogs (ModalResult) |
| `const mrOk = 1` |  |
| `const mrCancel = 2` |  |
| `const mrAbort = 3` |  |
| `const mrRetry = 4` |  |
| `const mrIgnore = 5` |  |
| `const mrYes = 6` |  |
| `const mrNo = 7` |  |
| `const mrClose = 8` |  |
