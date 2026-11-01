# Pastel.Additional

More standard controls, like the "Additional" page of Delphi's palette:

    TGroupBox    a frame with a title around controls that belong together
    TRadioGroup  a framed list of choices: one of them is chosen (ItemIndex)
    TShape       a rectangle, rounded rectangle, ellipse or circle
    TBevel       a line or a frame that divides a form
    TPaintBox    a place to draw on yourself (OnPaint)

`uses Pastel.Additional;` · source: [framework/src/pastel.additional.pas](../../framework/src/pastel.additional.pas)

**Contents:** [TGroupBox](#tgroupbox) · [TRadioGroup](#tradiogroup) · [TShapeKind](#tshapekind) · [TShape](#tshape) · [TBevelKind](#tbevelkind) · [TBevel](#tbevel) · [TPaintBox](#tpaintbox)

## Types

### TGroupBox

```pascal
type TGroupBox = class(TBox)
```

A frame with a title (Text) around controls that belong together. Its
controls are placed freely (Left, Top) like in Delphi; Layout = Flow stacks them.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `function TitleHeight: Integer` | Height of the title row; free-placed controls start below it (Top >= TitleHeight). |
| `property Text: string` |  |
| `property Layout` |  |

### TRadioGroup

```pascal
type TRadioGroup = class(TControl)
```

A framed list of choices; one is chosen at a time. Items = ('Cash', 'Card');
ItemIndex is the chosen one (-1: none). Arrow keys move the choice.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `destructor Destroy` |  |
| `function ItemRect(Index: Integer): TRectI` | The place of item Index (for tests and custom drawing). |
| `property Value: string` | The text of the chosen item, '' when none is chosen. |
| `property Text: string` |  |
| `property Items: TStrings` |  |
| `property ItemIndex: Integer` |  |
| `property Columns: Integer` | The items fill the columns from top to bottom. |
| `property OnChange: TNotifyEvent` | The user chose another item. |

### TShapeKind

```pascal
type TShapeKind = (skRectangle, skRoundRect, skEllipse, skCircle)
```

- `skRectangle`
- `skRoundRect`
- `skEllipse`
- `skCircle`
### TShape

```pascal
type TShape = class(TControl)
```

A rectangle, rounded rectangle, ellipse or circle. Color fills it (default: the
theme's surface), BorderColor and BorderWidth outline it.

| | |
|---|---|
| `constructor Create(AOwner: TComponent)` |  |
| `property Shape: TShapeKind` |  |
| `property Color: TColor32` |  |
| `property BorderColor: TColor32` |  |
| `property BorderWidth: Integer` |  |
| `property Radius: Integer` | The corners of a RoundRect. |

### TBevelKind

```pascal
type TBevelKind = (bkHorizontal, bkVertical, bkFrame)
```

- `bkHorizontal`
- `bkVertical`
- `bkFrame`
### TBevel

```pascal
type TBevel = class(TControl)
```

A thin line across (Horizontal), down (Vertical) or a frame around its place.

| | |
|---|---|
| `property Kind: TBevelKind` |  |
| `property Color: TColor32` | The line's color; 0: the theme's border color. |

### TPaintBox

```pascal
type TPaintBox = class(TControl)
```

A place to draw on yourself: OnPaint gets the canvas, clipped to the box;
Bounds tells where the box is. Invalidate draws it again. The mouse events
give X, Y inside the box. Without OnPaint a thin frame shows where it is.

| | |
|---|---|
| `property Color: TColor32` | The background; 0: none. |
| `property OnPaint: TPaintEvent` |  |
| `property OnMouseDown: TPaintMouseEvent` |  |
| `property OnMouseMove: TPaintMouseEvent` |  |
| `property OnMouseUp: TPaintMouseEvent` |  |
| `property OnClick: TNotifyEvent` |  |

## Other types

| | |
|---|---|
| `type TPaintEvent = procedure(Sender: TObject; Canvas: TCanvas32)` |  |
| `type TPaintMouseEvent = procedure(Sender: TObject; X: Integer; Y: Integer)` |  |

