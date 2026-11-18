# Pastel.UI

Controls, layout and input handling.

  Controls are TComponent descendants with published properties, so they can
  be created from .pform files the same way Delphi creates forms from .dfm.
  Layout is a small flexbox-style model: TColumn and TRow place children one
  after another, Grow shares the free space, Align/Justify position them.

`uses Pastel.UI;` · source: [framework/src/pastel.ui.pas](../../framework/src/pastel.ui.pas)

**Contents:** [TAlignItems](#talignitems) · [TJustify](#tjustify) · [TImageFit](#timagefit) · [TLayoutKind](#tlayoutkind) · [TAnchorKind](#tanchorkind) · [TDock](#tdock) · [TTextAlign](#ttextalign) · [TButtonStyle](#tbuttonstyle) · [TKeyboardType](#tkeyboardtype) · [TReturnKeyType](#treturnkeytype) · [TScreenClass](#tscreenclass) · [TCursorKind](#tcursorkind) · [TWindowState](#twindowstate) · [TThemeMode](#tthememode) · [TGestureState](#tgesturestate) · [TGestureInfo](#tgestureinfo) · [TDragMode](#tdragmode) · [TFieldLook](#tfieldlook) · [TFocusLook](#tfocuslook) · [TSwitchLook](#tswitchlook) · [TStyleLook](#tstylelook) · [TUIStyle](#tuistyle) · [TControl](#tcontrol) · [TAction](#taction) · [TBox](#tbox) · [TColumn](#tcolumn) · [TPanel](#tpanel) · [TRow](#trow) · [TFlow](#tflow) · [TCard](#tcard) · [TSpacer](#tspacer) · [TLabel](#tlabel) · [TButton](#tbutton) · [TEditState](#teditstate) · [TVisualLine](#tvisualline) · [TSyntaxKind](#tsyntaxkind) · [TSyntaxSpan](#tsyntaxspan) · [TCustomEdit](#tcustomedit) · [TEdit](#tedit) · [TMemo](#tmemo) · [TPopupSide](#tpopupside) · [TPopup](#tpopup) · [TPullRefresh](#tpullrefresh) · [TTimer](#ttimer) · [TForm](#tform) · [TTheme](#ttheme) · [UseDarkTheme](#usedarktheme) · [UseStyle](#usestyle) · [PlatformStyle](#platformstyle) · [LoadStyle](#loadstyle) · [StyleNames](#stylenames) · [FindLook](#findlook) · [DrawFocus](#drawfocus) · [DrawFocus](#drawfocus) · [PaintField](#paintfield) · [FieldHeight](#fieldheight) · [StyleRadius](#styleradius) · [SyntaxColor](#syntaxcolor) · [SetThemeValue](#setthemevalue) · [InvalidateArea](#invalidatearea) · [RequestAnimation](#requestanimation) · [AnimationTime](#animationtime) · [RequestAnimation](#requestanimation) · [ProcessTimers](#processtimers) · [DrawGrip](#drawgrip) · [ReleaseLater](#releaselater) · [CallLater](#calllater) · [ProcessReleases](#processreleases) · [WrapText](#wraptext) · [RegisterControl](#registercontrol) · [FindControlClass](#findcontrolclass) · [ControlClassCount](#controlclasscount) · [ControlClassAt](#controlclassat) · [RegisterNonVisual](#registernonvisual) · [FindNonVisualClass](#findnonvisualclass) · [NonVisualClassCount](#nonvisualclasscount) · [NonVisualClassAt](#nonvisualclassat) · [Utf16ToByteIndex](#utf16tobyteindex) · [ByteToUtf16Index](#bytetoutf16index)

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
### TImageFit

```pascal
type TImageFit = (ifContain, ifCover, ifStretch, ifCenter)
```

How a picture fills its place: Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size.

- `ifContain` How a picture fills its place: Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size.
- `ifCover` How a picture fills its place: Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size.
- `ifStretch` How a picture fills its place: Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size.
- `ifCenter` How a picture fills its place: Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size.
### TLayoutKind

```pascal
type TLayoutKind = (lkFlow, lkFree)
```

How a box places its children. Flow: below each other (or side by side in a row), the
responsive way; Free: where their Left and Top say, like Delphi and Lazarus forms.

- `lkFlow` How a box places its children. Flow: below each other (or side by side in a row), the responsive way; Free: where their Left and Top say, like Delphi and Lazarus forms.
- `lkFree` How a box places its children. Flow: below each other (or side by side in a row), the responsive way; Free: where their Left and Top say, like Delphi and Lazarus forms.
### TAnchorKind

```pascal
type TAnchorKind = (akLeft, akTop, akRight, akBottom)
```

The edges of a free-placed control that keep their distance to the parent's edges when
the parent is resized: [Left, Top] stays put, [Left, Right] gets wider with it.

- `akLeft` The edges of a free-placed control that keep their distance to the parent's edges when the parent is resized: [Left, Top] stays put, [Left, Right] gets wider with it.
- `akTop` The edges of a free-placed control that keep their distance to the parent's edges when the parent is resized: [Left, Top] stays put, [Left, Right] gets wider with it.
- `akRight` The edges of a free-placed control that keep their distance to the parent's edges when the parent is resized: [Left, Top] stays put, [Left, Right] gets wider with it.
- `akBottom` The edges of a free-placed control that keep their distance to the parent's edges when the parent is resized: [Left, Top] stays put, [Left, Right] gets wider with it.
### TDock

```pascal
type TDock = (dkNone, dkTop, dkBottom, dkLeft, dkRight, dkFill)
```

A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.

- `dkNone` A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.
- `dkTop` A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.
- `dkBottom` A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.
- `dkLeft` A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.
- `dkRight` A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.
- `dkFill` A free-placed control docked to an edge of its parent (Delphi's Align): Fill takes what is left.
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
### TKeyboardType

```pascal
type TKeyboardType = (ktDefault, ktText, ktNumber, ktDecimal, ktPhone, ktEmail, ktUrl, ktTime)
```

The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType):
ktDefault lets the edit choose (TNumberEdit: numbers).

- `ktDefault` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktText` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktNumber` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktDecimal` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktPhone` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktEmail` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktUrl` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
- `ktTime` The on-screen keyboard of a phone for an edit (FireMonkey's KeyboardType): ktDefault lets the edit choose (TNumberEdit: numbers).
### TReturnKeyType

```pascal
type TReturnKeyType = (rkDefault, rkDone, rkGo, rkNext, rkSearch, rkSend)
```

What the Enter key of a phone's on-screen keyboard says and does:
rkNext goes to the next control, the others are Enter (OnSubmit).

- `rkDefault` What the Enter key of a phone's on-screen keyboard says and does: rkNext goes to the next control, the others are Enter (OnSubmit).
- `rkDone` What the Enter key of a phone's on-screen keyboard says and does: rkNext goes to the next control, the others are Enter (OnSubmit).
- `rkGo` What the Enter key of a phone's on-screen keyboard says and does: rkNext goes to the next control, the others are Enter (OnSubmit).
- `rkNext` What the Enter key of a phone's on-screen keyboard says and does: rkNext goes to the next control, the others are Enter (OnSubmit).
- `rkSearch` What the Enter key of a phone's on-screen keyboard says and does: rkNext goes to the next control, the others are Enter (OnSubmit).
- `rkSend` What the Enter key of a phone's on-screen keyboard says and does: rkNext goes to the next control, the others are Enter (OnSubmit).
### TScreenClass

```pascal
type TScreenClass = (scPhone, scTablet, scDesktop, scTV)
```

What kind of screen the app is on: a phone, a tablet, a computer's window, a TV.
Forms can change with it (OnScreenClassChange, views: Home.tablet.pform).

- `scPhone` What kind of screen the app is on: a phone, a tablet, a computer's window, a TV. Forms can change with it (OnScreenClassChange, views: Home.tablet.pform).
- `scTablet` What kind of screen the app is on: a phone, a tablet, a computer's window, a TV. Forms can change with it (OnScreenClassChange, views: Home.tablet.pform).
- `scDesktop` What kind of screen the app is on: a phone, a tablet, a computer's window, a TV. Forms can change with it (OnScreenClassChange, views: Home.tablet.pform).
- `scTV` What kind of screen the app is on: a phone, a tablet, a computer's window, a TV. Forms can change with it (OnScreenClassChange, views: Home.tablet.pform).
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
### TGestureState

```pascal
type TGestureState = (gsBegin, gsUpdate, gsEnd)
```

- `gsBegin`
- `gsUpdate`
- `gsEnd`
### TGestureInfo

```pascal
type TGestureInfo = record
```

Two fingers (or Ctrl and the wheel on a computer): how much bigger since the
last call (Scale 1.1: 10 % larger), how much turned (radians, clockwise), and
their middle (the form's units).

| | |
|---|---|
| `State: TGestureState` |  |
| `Scale: Single` |  |
| `Rotation: Single` |  |
| `X: Integer` |  |
| `Y: Integer` |  |

### TDragMode

```pascal
type TDragMode = (dmManual, dmAutomatic)
```

dmAutomatic: pressing it and moving drags it (to a control with OnDragDrop)

- `dmManual` dmAutomatic: pressing it and moving drags it (to a control with OnDragDrop)
- `dmAutomatic` dmAutomatic: pressing it and moving drags it (to a control with OnDragDrop)
### TFieldLook

```pascal
type TFieldLook = (flBox, flUnderline, flOutline)
```

How an edit or a combo box is drawn: a box with a border (Pastel), a box
with a line at the bottom (Fluent), an outline that gets thicker when
focused (Material).

- `flBox` How an edit or a combo box is drawn: a box with a border (Pastel), a box with a line at the bottom (Fluent), an outline that gets thicker when focused (Material).
- `flUnderline` How an edit or a combo box is drawn: a box with a border (Pastel), a box with a line at the bottom (Fluent), an outline that gets thicker when focused (Material).
- `flOutline` How an edit or a combo box is drawn: a box with a border (Pastel), a box with a line at the bottom (Fluent), an outline that gets thicker when focused (Material).
### TFocusLook

```pascal
type TFocusLook = (fkRing, fkOutline)
```

The keyboard's focus: a soft ring of the accent color (Pastel), or a line
around in the text color (Fluent, Material).

- `fkRing` The keyboard's focus: a soft ring of the accent color (Pastel), or a line around in the text color (Fluent, Material).
- `fkOutline` The keyboard's focus: a soft ring of the accent color (Pastel), or a line around in the text color (Fluent, Material).
### TSwitchLook

```pascal
type TSwitchLook = (swPill, swFluent, swMaterial)
```

- `swPill`
- `swFluent`
- `swMaterial`
### TStyleLook

```pascal
type TStyleLook = class
```

A named look in a style file ([look.Name]), for a control's StyleLookup:
what it sets instead of the style's (0 or -1: not set).

| | |
|---|---|
| `constructor Create` |  |
| `procedure Assign(Src: TStyleLook)` |  |

### TUIStyle

```pascal
type TUIStyle = record
```

The sizes and shapes of the controls in a style (UseStyle); the colors
are the Theme's, which a style sets too. Read it in a control of your own
to look like the others.

| | |
|---|---|
| `Name: string` | 'pastel', 'fluent', 'material' or a style file's name |
| `ButtonPadX: Integer` | buttons: the room around the text (both sides together), the corners (999: round ends), a border on secondary buttons, bold text |
| `ButtonPadY: Integer` | buttons: the room around the text (both sides together), the corners (999: round ends), a border on secondary buttons, bold text |
| `ButtonRadius: Integer` | buttons: the room around the text (both sides together), the corners (999: round ends), a border on secondary buttons, bold text |
| `ButtonBorder: Integer` | buttons: the room around the text (both sides together), the corners (999: round ends), a border on secondary buttons, bold text |
| `ButtonBold: Boolean` |  |
| `FlatPadX: Integer` |  |
| `FlatPadY: Integer` |  |
| `FlatAccent: Boolean` | flat buttons in the accent color (Material's text buttons) |
| `FlatOverlay: Boolean` | flat buttons shaded over what is under them (hover and press) |
| `FieldPadX: Integer` | edits, combo boxes, date pickers: the room left and right of the text, above and below together |
| `FieldPadY: Integer` | edits, combo boxes, date pickers: the room left and right of the text, above and below together |
| `FieldRadius: Integer` | edits, combo boxes, date pickers: the room left and right of the text, above and below together |
| `FieldLook: TFieldLook` |  |
| `CheckSize: Integer` |  |
| `CheckRadius: Integer` |  |
| `SwitchLook: TSwitchLook` |  |
| `SliderThumb: Integer` |  |
| `ProgressHeight: Integer` |  |
| `PopupRadius: Integer` |  |
| `DialogRadius: Integer` |  |
| `FocusLook: TFocusLook` |  |
| `DefaultButtonFirst: Boolean` | dialogs: the default button first (Windows: OK Cancel), the others as flat buttons |
| `DialogFlatButtons: Boolean` | dialogs: the default button first (Windows: OK Cancel), the others as flat buttons |
| `Radius: Integer` | the Theme's Radius: cards, lists, grids |

### TControl

```pascal
type TControl = class(TComponent)
```

| | |
|---|---|
| `function DragsAt(X: Integer; Y: Integer): Boolean` | True when a press at X, Y starts a drag of the control's own (a list's grip): a finger there drags instead of scrolling. |
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure Invalidate` | needs repaint only |
| `procedure SetFocus` |  |
| `function HitTest(X: Integer; Y: Integer): TControl` |  |
| `function ParentForm: TForm` |  |
| `function ParentPopup: TPopup` | The popup the control is in, or nil. |
| `procedure GetSize(AvailWidth: Integer; out W: Integer; out H: Integer)` | Preferred size including explicit Width/Height. |
| `class function DesktopOnly: Boolean` | True for controls that only make sense with a mouse and a big window (a menu bar, a splitter, a status bar): the designer says they will not be on phones. |
| `property Parent: TControl` |  |
| `property Children[Index: Integer]: TControl` |  |
| `property ChildCount: Integer` |  |
| `function IndexOfChild(C: TControl): Integer` |  |
| `property Bounds: TRectI` |  |
| `property OnDropFiles: TDropFilesEvent` | Files dropped on it from the file manager (computers); the control under the place or the first one above it that has the event, else the form's. |
| `property OnGesture: TGestureEvent` | Two fingers pinched or turned over it (a picture, a map, a drawing). |
| `property AccessibleName: string` | What a screen reader (TalkBack) says for it, when its text does not say it (an icon button: 'Delete'). |
| `property DragMode: TDragMode` | dmAutomatic: it can be dragged onto controls with OnDragDrop (a finger too). |
| `property OnStartDrag: TStartDragEvent` |  |
| `property OnDragOver: TDragOverEvent` | Something dragged over it: Accept := False refuses it. |
| `property OnDragDrop: TDragDropEvent` | Dropped on it. |
| `property OnEndDrag: TEndDragEvent` |  |
| `property Width: Integer` |  |
| `property Height: Integer` |  |
| `property Grow: Integer` |  |
| `property Left: Integer` | The place in a parent with Layout = Free (a TPanel, or a form with Layout = Free). |
| `property Top: Integer` |  |
| `property Anchors: TAnchors` | In a parent with Layout = Free: which edges follow the parent's when it is resized. |
| `property Dock: TDock` | In a parent with Layout = Free: docked to an edge (Top, Bottom, Left, Right) or Fill. |
| `property TabOrder: Integer` | The Tab key goes through the controls of a parent in TabOrder (equal ones in their order in the .pform). |
| `property TabStop: Boolean` | False: the Tab key passes it by (a click still focuses it). |
| `property Visible: Boolean` |  |
| `property Enabled: Boolean` |  |
| `property Hint: string` | Shown in a tooltip when the mouse rests on the control. |
| `property PopupMenu: TControl` | A TPopupMenu shown on a right click (or the menu key). |
| `property StyleLookup: string` | A [look.Name] of the style file in use: its colors, corners and sizes instead of the style's (buttons, labels, boxes, edits, combo boxes). |

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
| `property Icon: string` | A built-in icon for its buttons and menu items ('save', 'print'...). |
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
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `property Horizontal: Boolean` | True for TRow: children are placed left to right. |
| `property OnDropFiles` |  |
| `property Layout: TLayoutKind` | Flow (default): children below each other, or side by side in a row; Free: where their Left and Top say. |
| `property Gap: Integer` |  |
| `property Padding: Integer` |  |
| `property Align: TAlignItems` |  |
| `property Justify: TJustify` |  |
| `property Color: TColor32` |  |
| `property BorderColor: TColor32` |  |
| `property BorderWidth: Integer` |  |
| `property Radius: Integer` |  |
| `property BackgroundImage: string` | A picture behind the children: a file in assets/, next to the program, or a full path. |
| `property BackgroundFit: TImageFit` |  |
| `property MaxContentWidth: Integer` | The children use at most this width, in the middle: a form stays readable on a tablet, a TV or a wide window (0: all the width). |

### TColumn

```pascal
type TColumn = class(TBox)
```

### TPanel

```pascal
type TPanel = class(TBox)
```

A box whose children stay where they are put (Left, Top), like a Delphi TPanel.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Layout` |  |

### TRow

```pascal
type TRow = class(TBox)
```

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |

### TFlow

```pascal
type TFlow = class(TBox)
```

A row that wraps: children are placed left to right, and continue on
the next line when there is no room (chips, tags, buttons, small cards).
Gap is the space between them, also between lines; in each line the
ones with Grow share what is left.

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
| `property Color: TColor32` | Any background color instead of the style's (hover and press shade it); 0: the style's. |
| `property TextColor: TColor32` | Any text and icon color; 0: the style's. |
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

### TSyntaxKind

```pascal
type TSyntaxKind = (skText, skKeyword, skString, skNumber, skComment, skName, skSymbol, skError)
```

What a part of a code editor's text is (syntax highlighting); each has a
color of the theme (SyntaxColor).

- `skText` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skKeyword` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skString` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skNumber` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skComment` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skName` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skSymbol` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
- `skError` What a part of a code editor's text is (syntax highlighting); each has a color of the theme (SyntaxColor).
### TSyntaxSpan

```pascal
type TSyntaxSpan = record
```

A part of the text: Start (bytes, from 1), Len bytes.

| | |
|---|---|
| `Start: Integer` |  |
| `Len: Integer` |  |
| `Kind: TSyntaxKind` |  |

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
| `procedure RehighlightText` | Colors the text again (OnHighlight), when what it depends on changed. |
| `procedure ShowCompletions` | The completion list (typing a word shows it; Ctrl+Space too). |
| `procedure HideCompletions` |  |
| `function CompletionsShown: Boolean` |  |
| `procedure Complete(const Word: string)` | Puts Word in place of the word before the caret (the part after its last dot). |
| `procedure SelectAll` |  |
| `procedure CopyToClipboard` |  |
| `procedure CutToClipboard` |  |
| `procedure PasteFromClipboard` |  |
| `procedure Undo` |  |
| `procedure Redo` |  |
| `function CanUndo: Boolean` |  |
| `property CaretPos: Integer` |  |
| `function KeyboardKind: TKeyboardType` | The keyboard a phone shows: KeyboardType, or the edit's own choice for ktDefault (ktText for most). |
| `function WantsKeyboard: Boolean` | False when the edit brings a picker of its own on a phone (TTimeEdit) instead of the keyboard. |
| `property MultiLine: Boolean` |  |
| `property IsPassword: Boolean` |  |
| `property ReturnKeyType: TReturnKeyType` |  |
| `property SelStart: Integer` | The selection: SelStart counts from 0 (bytes), like Delphi. |
| `property SelLength: Integer` |  |
| `property SelText: string` |  |
| `property Text: string` |  |
| `property Placeholder: string` |  |
| `property ReadOnly: Boolean` |  |
| `property MaxLength: Integer` | At most this many bytes; 0: no limit. |
| `property OnChange: TNotifyEvent` |  |
| `property Error: string` | A problem with the value ('Fill this in'): a red border, and the text as a tooltip; typing clears it. TDataBinding.Validate sets it. |
| `property Completions: TStrings` | Words offered while typing (table names, keywords...): a list below the caret; Up/Down choose, Enter or Tab put it in, Escape closes it. |
| `property OnCompletions: TCompletionEvent` | The words for what is typed, when they depend on it (the columns after 'orders.'). |
| `property OnHighlight: THighlightEvent` | Syntax highlighting: Pastel.Syntax has HighlightSql, HighlightPascal... |

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
| `property KeyboardType: TKeyboardType` | The phone's on-screen keyboard for it: numbers, a phone pad, e-mail... |
| `property ReturnKeyType` | What the on-screen keyboard's Enter key says: Done, Next, Search... |
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
| `property OnDropFiles` |  |
| `property Text` |  |
| `property Placeholder` |  |
| `property ReadOnly` |  |
| `property MaxLength` |  |
| `property WordWrap: Boolean` |  |
| `property KeyboardType: TKeyboardType` | The phone's on-screen keyboard for it. |
| `property OnChange` |  |
| `property Completions` |  |
| `property OnCompletions` |  |
| `property OnHighlight` |  |

### TPopupSide

```pascal
type TPopupSide = (psAnchor, psLeft, psRight, psBottom)
```

Where a popup goes: below (or above) its anchor, centered; or along a side
of the window, as a drawer or a bottom sheet (the window dimmed behind).

- `psAnchor` Where a popup goes: below (or above) its anchor, centered; or along a side of the window, as a drawer or a bottom sheet (the window dimmed behind).
- `psLeft` Where a popup goes: below (or above) its anchor, centered; or along a side of the window, as a drawer or a bottom sheet (the window dimmed behind).
- `psRight` Where a popup goes: below (or above) its anchor, centered; or along a side of the window, as a drawer or a bottom sheet (the window dimmed behind).
- `psBottom` Where a popup goes: below (or above) its anchor, centered; or along a side of the window, as a drawer or a bottom sheet (the window dimmed behind).
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
| `procedure ShowModal(Form: TForm; OnDone: TModalDoneEvent; FreeWhenDone: Boolean = False)` | The same without waiting: returns at once, OnDone is called when it is closed (with ModalResult); FreeWhenDone frees it after that. Phones and browsers prefer it: nothing waits inside an event. |
| `procedure Close(AModalResult: Integer = 0)` |  |
| `property Modal: Boolean` |  |
| `property Closed: Boolean` |  |
| `property Shown: Boolean` |  |
| `property ModalResult: Integer` |  |
| `property Side: TPopupSide` | Along a side of the window (drawers, bottom sheets) instead of at its anchor. |
| `property ActiveControl: TControl` | Gets the focus when a modal popup opens; the first focusable control when nil. |
| `property OnClose: TNotifyEvent` |  |

### TPullRefresh

```pascal
type TPullRefresh = class(TComponent)
```

"Pull down to refresh" of a list (TListView, TGrid, TScrollBox): a finger
that pulls the list down past its top shows a circle; let go far enough and
OnRefresh is called, the circle turns until Refreshing := False. On a
computer F5 does it. Used by the controls; their OnRefresh and Refreshing.

| | |
|---|---|
| `constructor Create(AControl: TControl)` |  |
| `function Wheel(DY: Integer; AtTop: Boolean): Boolean` | a wheel step (a finger's on a phone) at the top: True when it pulls |
| `function Key(K: LongInt): Boolean` |  |
| `procedure Paint(C: TCanvas32)` |  |
| `property Refreshing: Boolean` |  |
| `property OnRefresh: TNotifyEvent` |  |

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
| `procedure ShowToast(const Msg: string; DurationMs: Integer = 2000)` | A short message near the bottom for a moment (Android's Toast); clicks go through it. Pastel.Dialogs' ShowToast uses the phone's own on Android. |
| `property ToastText: string` | The message shown by ShowToast ('' when none). |
| `procedure HandleMouseWheel(DX: Integer; DY: Integer)` |  |
| `procedure HandleGesture(const G: TGestureInfo)` | A pinch or a turn at G.X, G.Y: to the control there, or the first above it that takes it. |
| `procedure BeginDrag(C: TControl; const Data: string)` | Starts dragging C (DragMode = dmManual: from its MouseDown or OnMouseDown) with Data. |
| `property Dragging: Boolean` | True while something is dragged. |
| `property DragTarget: TControl` |  |
| `function SaveState: TStrings` | The app's own values kept while a phone stops it in the background (OnSaveState fills it; in OnCreate it has them again, else it is empty): SaveState.Values['page'] := IntToStr(Page); |
| `function HandleDropFiles(X: Integer; Y: Integer; const Files: TStringArray): Boolean` | Files dropped at X, Y (the platform layer): to the OnDropFiles there. True when one took them. |
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
| `procedure ShowModal(OnDone: TModalDoneEvent)` | The same without waiting: returns at once; OnDone(Self, ModalResult) is called when the dialog is closed. The way for phones (Delphi's ShowModal(procedure ...) on Android): AppointmentForm.ShowModal(@AppointmentClosed); ... procedure THomeForm.AppointmentClosed(Sender: TObject; AResult: Integer); begin if AResult = mrOk then Reload; end; |
| `procedure Show` | Shows the form in a window of its own beside the main one (computers; again: brings it to the front). Phones have one window: it is shown over the main form as without waiting (ShowModal(nil)). Close closes it. |
| `function Showing: Boolean` | True while it has a window of its own (Show). |
| `property ModalResult: Integer` | Setting it in a dialog form closes the dialog with that result. |
| `procedure WindowStateChanged(AState: TWindowState)` | Called by the platform layer when the user changed the window state. |
| `procedure SetScreenClass(AValue: TScreenClass)` | Called by the platform layer before laying the form out: the view for that kind of screen is applied (Home.tablet.pform) and OnScreenClassChange runs. |
| `function FocusInDirection(DX: Integer; DY: Integer): Boolean` | Moves the focus to the nearest control left, right, up or down (a TV's remote, arrow keys on a phone); False when there is none in that direction. |
| `procedure ActivateFocused` | The remote's OK button: presses the focused button, ticks a check box, opens a list (Space, else Enter). |
| `property ScreenClass: TScreenClass` | The kind of screen: scPhone, scTablet, scDesktop or scTV. |
| `property View: string` | The view applied: 'tablet' for Home.tablet.pform, '' for the form itself. |
| `property Title: string` |  |
| `property Resizable: Boolean` | Can the user resize (and maximize) the window? |
| `property MinWidth: Integer` |  |
| `property MinHeight: Integer` |  |
| `property WindowState: TWindowState` |  |
| `property AlwaysOnTop: Boolean` |  |
| `property Appearance: TThemeMode` | The colors of the app: Light, Dark or System (as the computer is set). |
| `property OnCreate: TNotifyEvent` |  |
| `property OnSaveState: TNotifyEvent` | A phone may stop an app in the background to free memory and start it again when the user comes back. What was typed, ticked and chosen comes back by itself; for more, put it into SaveState here (it is in SaveState again in OnCreate, when the app comes back). |
| `property OnCloseQuery: TCloseQueryEvent` | Set CanClose to False to keep the window open, e.g. to ask about unsaved work. |
| `property OnClose: TNotifyEvent` |  |
| `property OnResize: TNotifyEvent` |  |
| `property OnScreenClassChange: TNotifyEvent` | The kind of screen became known or changed (a phone turned into a tablet's split screen, a window made narrow): show, hide or arrange controls for it. |

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
| `Outline: TColor32` | the border of edits and combo boxes (Material's darker outline); Border in the others |

## Other types

| | |
|---|---|
| `type TAnchors = set of TAnchorKind` |  |
| `type TCloseQueryEvent = procedure(Sender: TObject; CanClose: Boolean)` |  |
| `type TModalDoneEvent = procedure(Sender: TObject; AResult: Integer)` | Called when a dialog shown without waiting is closed: Sender is the dialog (the form, the popup), AResult the button chosen (mrOk, mrCancel...). In a form's method the parameter cannot be called ModalResult (a property of the form): AResult, like Delphi. |
| `type TReorderEvent = procedure(Sender: TObject; FromIndex: Integer; ToIndex: Integer)` | A row moved by its grip (lists with AllowReorder): from where to where. |
| `type TDropFilesEvent = procedure(Sender: TObject; Files: TStringArray)` | Files dragged from the file manager and dropped on a control (computers). |
| `type TGestureEvent = procedure(Sender: TObject; Gesture: TGestureInfo; Handled: Boolean)` |  |
| `type TStartDragEvent = procedure(Sender: TObject; Data: string; Cancel: Boolean)` | What is dragged: a text (an item's, an id) set in OnStartDrag; Cancel: no drag. |
| `type TDragOverEvent = procedure(Sender: TObject; Source: TObject; Data: string; X: Integer; Y: Integer; Accept: Boolean)` | Source: the control it comes from; Accept: may it be dropped here (default True). |
| `type TDragDropEvent = procedure(Sender: TObject; Source: TObject; Data: string; X: Integer; Y: Integer)` |  |
| `type TEndDragEvent = procedure(Sender: TObject; Target: TObject; Data: string)` | Target: where it was dropped (nil: nowhere it was taken). |
| `type TControlClass = class of TControl` |  |
| `type TRectArray = array of TRectI` |  |
| `type TEditStates = array of TEditState` |  |
| `type TSyntaxSpans = array of TSyntaxSpan` |  |
| `type THighlightEvent = procedure(Sender: TObject; AText: string; Spans: TSyntaxSpans)` | Colors the text: add a span for each part that is not plain text. |
| `type TCompletionEvent = procedure(Sender: TObject; Word: string; Items: TStrings)` | Word is what is typed before the caret (letters, digits, _ and dots: 'orders.cu'); Items gets the words that may follow (only those that begin with the part after the last dot are shown). |
| `type TFormClass = class of TForm` |  |

## Routines

### UseDarkTheme

```pascal
procedure UseDarkTheme(Dark: Boolean)
```

Light or dark colors for every control; repaints.

### UseStyle

```pascal
function UseStyle(const Name: string): Boolean
```

Styles: 'pastel' (the same everywhere), 'fluent' (Windows 11), 'material'
(Android), 'auto' (the one of the platform it runs on: Fluent on Windows,
Material on Android, Pastel elsewhere), or a style loaded from a .pstyle
file (LoadStyle; an app's assets/styles/*.pstyle by their names). The
light or dark theme stays. False: no such style.

### PlatformStyle

```pascal
function PlatformStyle: string
```

The style 'auto' picks here.

### LoadStyle

```pascal
function LoadStyle(const Name: string; const Text: string): string
```

A style from the text of a .pstyle file (TOML: base = "material", [colors],
[colors.dark], [button], [field]..., [look.Name]); '' or what is wrong.

### StyleNames

```pascal
function StyleNames: TStringArray
```

The styles there are (built in and loaded).

### FindLook

```pascal
function FindLook(const Name: string): TStyleLook
```

A [look.Name] of the style in use (its dark one in the dark theme); nil: none.

### DrawFocus

```pascal
procedure DrawFocus(C: TCanvas32; const R: TRectI; Radius: Single)
```

The keyboard's focus around R, as the style draws it.

### DrawFocus

```pascal
procedure DrawFocus(C: TCanvas32; Ctrl: TControl; const R: TRectI; Radius: Single)
```

The same for a focused control: the ring always (Pastel), the outline when
the keyboard moved the focus (Fluent, Material).

### PaintField

```pascal
procedure PaintField(C: TCanvas32; const R: TRectI; Focused: Boolean; Hovered: Boolean; Enabled: Boolean; Editable: Boolean; Error: Boolean; Look: TStyleLook = nil)
```

The box of an edit, a combo box or a date picker in the style; Look may be nil.

### FieldHeight

```pascal
function FieldHeight(LineHeight: Integer): Integer
```

The height of such a box for a line of text.

### StyleRadius

```pascal
function StyleRadius(R: Integer): Integer
```

A radius of the style: -1 is the theme's Radius.

### SyntaxColor

```pascal
function SyntaxColor(Kind: TSyntaxKind): TColor32
```

The color of a kind of code (syntax highlighting) in the light or dark theme.

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

### DrawGrip

```pascal
procedure DrawGrip(C: TCanvas32; X: Integer; Y: Integer; W: Integer; H: Integer; Col: TColor32)
```

A list row's grip, three short lines ("hold here to move"), in the middle of X, Y, W, H.

### ReleaseLater

```pascal
procedure ReleaseLater(Obj: TObject)
```

Frees Obj soon, outside the event that is running (a dialog closed by its own button).

### CallLater

```pascal
procedure CallLater(Event: TNotifyEvent; Sender: TObject)
```

Calls Event(Sender) soon, outside the event that is running: answers that
come at once are given the same way as those that come later.

### ProcessReleases

```pascal
procedure ProcessReleases
```

Calls what CallLater was given, then frees what ReleaseLater was given
(ProcessTimers does it too).

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

### Utf16ToByteIndex

```pascal
function Utf16ToByteIndex(const S: string; U: Integer): Integer
```

Positions in a UTF-8 string, from 0: UTF-16 units (Java's, JavaScript's) to
bytes and back; a letter beyond the first 65536 (an emoji) is two units.

### ByteToUtf16Index

```pascal
function ByteToUtf16Index(const S: string; B: Integer): Integer
```

## Constants and variables

| | |
|---|---|
| `var Theme: TTheme` |  |
| `var UIStyle: TUIStyle` | The style in use; change it with UseStyle. |
| `var ThemeCustomizer: procedure` | Runs after UseDarkTheme set up the light or dark colors: changes to Theme go here. Pastel.App applies assets/theme.toml with it. |
| `var KeyAlt: Boolean` | Alt is held (with KeyDown). |
| `var ArrowKeysMoveFocus: Boolean` | Arrow keys a control does not use move the focus to the nearest control in that direction (a TV's remote). Pastel.App turns it on for Android. |
| `var MainForm: TForm` | The main window's form; dialogs are shown on it. Set by Pastel.App. |
| `var CloseFormHook: function (Form : TForm) : Boolean` |  |
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
| `var WheelFromTouch: Boolean` | Set by the app while a finger drags a list (phones): what pulls to refresh. |
| `const ReorderGripWidth = 36` | the width of a list row's grip (AllowReorder) |
