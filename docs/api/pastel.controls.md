# Pastel.Controls

More controls: check boxes, radio buttons, switches, lists,
  drop-downs, pictures, scrolling areas, tabs, progress bars, sliders,
  spinners, splitters, tool bars and status bars. They are registered for .pform files like the basic ones.

`uses Pastel.Controls;` · source: [framework/src/pastel.controls.pas](../../framework/src/pastel.controls.pas)

**Contents:** [TCheckBox](#tcheckbox) · [TRadioButton](#tradiobutton) · [TSwitch](#tswitch) · [TListBox](#tlistbox) · [TComboBox](#tcombobox) · [TImage](#timage) · [TScrollBox](#tscrollbox) · [TTabSheet](#ttabsheet) · [TTabControl](#ttabcontrol) · [TProgressBar](#tprogressbar) · [TSlider](#tslider) · [TSpinner](#tspinner) · [TSplitter](#tsplitter) · [TToolBar](#ttoolbar) · [TStatusBar](#tstatusbar) · [FindAppFile](#findappfile)

## Types

### TCheckBox

```pascal
type TCheckBox = class(TControl)
```

A box with a check mark and a text; Checked toggles on click and Space.

| | |
|---|---|
| `property Text: string` |  |
| `property Checked: Boolean` |  |
| `property OnChange: TNotifyEvent` |  |

### TRadioButton

```pascal
type TRadioButton = class(TCheckBox)
```

One choice of several: checking it unchecks the radio buttons next to it
(with the same parent).

### TSwitch

```pascal
type TSwitch = class(TCheckBox)
```

An on/off switch with an optional text after it.

### TListBox

```pascal
type TListBox = class(TControl)
```

A list of texts to choose from. Only the rows that show are drawn, so it
handles many thousands of items.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure MakeVisible(Index: Integer)` | Scrolls so the item shows. |
| `function Font: TPastelFont` |  |
| `function SelectedText: string` | The selected text, '' when nothing is selected. |
| `property HotTrack: Boolean` | Used by TComboBox: the row under the mouse is highlighted. |
| `property OnItemClick: TNotifyEvent` | A click on an item (also when it was selected already). |
| `property Items: TStrings` |  |
| `property ItemIndex: Integer` |  |
| `property ItemHeight: Integer` | Height of a row; 0: from the font. |
| `property OnChange: TNotifyEvent` |  |
| `property OnDblClick: TNotifyEvent` | A double click or Enter on an item. |

### TComboBox

```pascal
type TComboBox = class(TControl)
```

A drop-down list.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure DropDown` |  |
| `procedure CloseUp` |  |
| `function DroppedDown: Boolean` |  |
| `property Items: TStrings` |  |
| `property ItemIndex: Integer` |  |
| `property Text: string` | The chosen item; setting it chooses the item with that text. |
| `property Placeholder: string` | Shown when nothing is chosen. |
| `property OnChange: TNotifyEvent` |  |

### TImage

```pascal
type TImage = class(TControl)
```

A picture from a PNG, JPEG or BMP file.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `procedure LoadFromStream(Stream: TStream)` | Loads a picture from a stream (e.g. a resource or a download). |
| `property Picture: TBitmap32` |  |
| `property LoadError: string` | Why the picture could not be loaded, '' when it was. |
| `property FileName: string` | A file next to the program, in assets/ or a full path. |
| `property Fit: TImageFit` | Contain: all of it fits; Cover: fills, cut at the edges; Stretch; Center: real size. |

### TScrollBox

```pascal
type TScrollBox = class(TColumn)
```

A column whose content can be taller than the box: it scrolls.

| | |
|---|---|
| `procedure ScrollIntoView(C: TControl)` |  |
| `property ScrollY: Integer` |  |
| `property ContentHeight: Integer` |  |

### TTabSheet

```pascal
type TTabSheet = class(TColumn)
```

One page of a TTabControl.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Caption: string` |  |

### TTabControl

```pascal
type TTabControl = class(TControl)
```

Pages with tabs above them; its children are TTabSheets.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function ActiveSheet: TTabSheet` |  |
| `procedure ScrollIntoView(C: TControl)` |  |
| `function TabRect(ASheet: TTabSheet): TRectI` | Where the tab of a page is. |
| `property TabIndex: Integer` |  |
| `property OnChange: TNotifyEvent` |  |

### TProgressBar

```pascal
type TProgressBar = class(TControl)
```

How far a task is: Position of Max; Indeterminate when that is not known.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Position: Integer` |  |
| `property Max: Integer` |  |
| `property Indeterminate: Boolean` |  |

### TSlider

```pascal
type TSlider = class(TControl)
```

Choose a number by dragging a knob.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Min: Integer` |  |
| `property Max: Integer` |  |
| `property Position: Integer` |  |
| `property Step: Integer` | Arrow keys and the wheel move by this much. |
| `property OnChange: TNotifyEvent` |  |

### TSpinner

```pascal
type TSpinner = class(TControl)
```

A turning circle of dots: something is happening.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Active: Boolean` |  |

### TSplitter

```pascal
type TSplitter = class(TControl)
```

A bar between two controls of a TRow (or a TColumn) that the user drags
to share the room between them. It changes the Width (in a column: the
Height) of the control before it; give that one a Width and the one after
it Grow = 1.

| | |
|---|---|
| `class function DesktopOnly: Boolean` |  |
| `constructor Create(AOwner: TComponent)` |  |
| `function Target: TControl` | The control it resizes: the visible one before it; nil when there is none. |
| `procedure MoveTo(Size: Integer)` | Gives the target this size (clamped between MinSize and the room there is). |
| `property MinSize: Integer` | The smallest size of the controls on both sides. |
| `property OnMoved: TNotifyEvent` | The user let go of it at a new place. |

### TToolBar

```pascal
type TToolBar = class(TRow)
```

A row of buttons at the top of a form, under the menu: put TButtons with
Style = Flat in it (and a TSpacer to push the rest to the right).

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |

### TStatusBar

```pascal
type TStatusBar = class(TRow)
```

A line at the bottom of a form that says what is going on. Text is shown
when it has no children; otherwise put TLabels in it (a TSpacer between
them pushes the next ones to the right).

| | |
|---|---|
| `class function DesktopOnly: Boolean` |  |
| `constructor Create(AOwner: TComponent)` |  |
| `property Text: string` |  |

## Other types

| | |
|---|---|
| `type TImageFit = Pastel.UI.TImageFit` |  |

## Routines

### FindAppFile

```pascal
function FindAppFile(const FileName: string): string
```

Where a file named in a .pform (pictures) is: a full path, next to the
program, in assets/ next to it or in the current folder.

