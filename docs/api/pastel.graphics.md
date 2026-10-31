# Pastel.Graphics

Software 2D drawing: colors, an anti-aliased canvas and fonts.

  Everything is drawn by Pastel itself into a 32-bit pixel buffer, so it
  looks the same on every platform. A GPU backend (e.g. Skia) can later
  implement the same drawing calls.

`uses Pastel.Graphics;` · source: [framework/src/pastel.graphics.pas](../../framework/src/pastel.graphics.pas)

**Contents:** [TRectI](#trecti) · [TPastelFont](#tpastelfont) · [TBitmap32](#tbitmap32) · [TCanvas32](#tcanvas32) · [EPastelGraphics](#epastelgraphics) · [RGB](#rgb) · [RGBA](#rgba) · [WithAlpha](#withalpha) · [Mix](#mix) · [TryParseColor](#tryparsecolor) · [RectI](#recti) · [NextCodePoint](#nextcodepoint) · [PrevCharStart](#prevcharstart) · [GetFont](#getfont) · [SetFontFiles](#setfontfiles)

## Types

### TRectI

```pascal
type TRectI = record
```

| | |
|---|---|
| `X: Integer` |  |
| `Y: Integer` |  |
| `W: Integer` |  |
| `H: Integer` |  |
| `function Contains(PX: Integer; PY: Integer): Boolean` |  |
| `function Intersect(const R: TRectI): TRectI` |  |
| `function Union(const R: TRectI): TRectI` | The smallest rectangle around both (an empty one is ignored). |
| `function Inflate(D: Integer): TRectI` |  |

### TPastelFont

```pascal
type TPastelFont = class
```

| | |
|---|---|
| `constructor Create(const FileName: string; ASize: Integer)` |  |
| `destructor Destroy` |  |
| `function Glyph(CodePoint: Cardinal): PGlyph` |  |
| `function TextWidth(const S: string): Integer` |  |
| `function HitTest(const S: string; X: Integer): Integer` | Byte index in S whose left edge is closest to pixel offset X. |
| `property Size: Integer` |  |
| `property Bold: Boolean` |  |
| `property Ascent: Integer` |  |
| `property Descent: Integer` |  |
| `property LineHeight: Integer` |  |

### TBitmap32

```pascal
type TBitmap32 = class
```

A picture in memory: $AARRGGBB pixels, from PNG, JPEG or BMP files.

| | |
|---|---|
| `procedure SetSize(AWidth: Integer; AHeight: Integer)` |  |
| `procedure LoadFromFile(const FileName: string)` |  |
| `procedure LoadFromStream(Stream: TStream)` |  |
| `function Empty: Boolean` |  |
| `property Width: Integer` |  |
| `property Height: Integer` |  |

### TCanvas32

```pascal
type TCanvas32 = class
```

| | |
|---|---|
| `procedure SetSize(AWidth: Integer; AHeight: Integer)` | Width and height in layout units; with Scale 2 the pixels are twice as many. |
| `procedure Clear(C: TColor32)` |  |
| `procedure PushClip(const R: TRectI)` |  |
| `procedure PopClip` |  |
| `procedure FillRect(X: Integer; Y: Integer; W: Integer; H: Integer; C: TColor32)` |  |
| `procedure FillRoundRect(X: Integer; Y: Integer; W: Integer; H: Integer; Radius: Single; C: TColor32)` |  |
| `procedure StrokeRoundRect(X: Integer; Y: Integer; W: Integer; H: Integer; Radius: Single; Thickness: Single; C: TColor32)` |  |
| `procedure DrawText(Font: TPastelFont; X: Integer; Y: Integer; const S: string; C: TColor32)` | Y is the top of the text line; the baseline is Y + Font.Ascent. |
| `procedure DrawLine(X1: Single; Y1: Single; X2: Single; Y2: Single; Thickness: Single; C: TColor32)` | An anti-aliased line with round ends. |
| `procedure FillCircle(CX: Single; CY: Single; Radius: Single; C: TColor32)` |  |
| `procedure DrawBitmap(B: TBitmap32; X: Integer; Y: Integer; W: Integer; H: Integer; Smooth: Boolean = True; Opacity: Byte = 255)` | A picture scaled into the rectangle (bilinear when Smooth), with its transparency. |
| `function GetPixel(X: Integer; Y: Integer): TColor32` |  |
| `procedure SaveToPNG(const FileName: string)` |  |
| `function PixelRect(const R: TRectI): TRectI` | A rectangle in layout units, in pixels. |
| `function Data: Pointer` |  |
| `property Width: Integer` |  |
| `property Height: Integer` |  |
| `property PixelWidth: Integer` | The size in pixels (Width * Scale). |
| `property PixelHeight: Integer` |  |
| `property Scale: Single` | Pixels per layout unit: 2 on a "retina" or 200% screen. Text is drawn with a font of the scaled size, so it stays sharp. |

### EPastelGraphics

```pascal
type EPastelGraphics = class(Exception)
```

## Other types

| | |
|---|---|
| `type TColor32 = Cardinal` | $AARRGGBB. A distinct type so .pform files can use '#RRGGBB' for it. |

## Routines

### RGB

```pascal
function RGB(R: Byte; G: Byte; B: Byte): TColor32
```

### RGBA

```pascal
function RGBA(R: Byte; G: Byte; B: Byte; A: Byte): TColor32
```

### WithAlpha

```pascal
function WithAlpha(C: TColor32; A: Byte): TColor32
```

### Mix

```pascal
function Mix(A: TColor32; B: TColor32; T: Single): TColor32
```

### TryParseColor

```pascal
function TryParseColor(const S: string; out C: TColor32): Boolean
```

Parses '#RGB', '#RRGGBB' or '#AARRGGBB'.

### RectI

```pascal
function RectI(X: Integer; Y: Integer; W: Integer; H: Integer): TRectI
```

### NextCodePoint

```pascal
function NextCodePoint(const S: string; var I: Integer): Cardinal
```

UTF-8 helpers. NextCodePoint reads one character at byte index I (1-based)
and moves I past it.

### PrevCharStart

```pascal
function PrevCharStart(const S: string; I: Integer): Integer
```

### GetFont

```pascal
function GetFont(Size: Integer; Bold: Boolean = False): TPastelFont
```

Fonts are shared and cached by size and weight.

### SetFontFiles

```pascal
procedure SetFontFiles(const Regular: string; const Bold: string)
```

Use these .ttf files instead of the system font (after InitFonts).

