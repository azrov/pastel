# Pastel.Controls

More controls: check boxes, radio buttons, switches, lists,
  drop-downs, pictures, scrolling areas, tabs, progress bars, sliders and
  spinners. They are registered for .pform files like the basic ones.

`uses Pastel.Controls;` · source: [framework/src/pastel.controls.pas](../../framework/src/pastel.controls.pas)

**Contents:** [TCheckBox](#tcheckbox) · [TRadioButton](#tradiobutton) · [TSwitch](#tswitch) · [TListBox](#tlistbox) · [TComboBox](#tcombobox) · [TImageFit](#timagefit) · [TImage](#timage) · [TScrollBox](#tscrollbox) · [TTabSheet](#ttabsheet) · [TTabControl](#ttabcontrol) · [TProgressBar](#tprogressbar) · [TSlider](#tslider) · [TSpinner](#tspinner) · [FindAppFile](#findappfile)

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

### TImageFit

```pascal
type TImageFit = (ifContain, ifCover, ifStretch, ifCenter)
```

- `ifContain`
- `ifCover`
- `ifStretch`
- `ifCenter`
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

## Routines

### FindAppFile

```pascal
function FindAppFile(const FileName: string): string
```

Where a file named in a .pform (pictures) is: a full path, next to the
program, in assets/ next to it or in the current folder.

