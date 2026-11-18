# Pastel.TrueType

TrueType fonts in plain Pascal: reads a .ttf (or the first font of a
  .ttc) and draws its glyphs with anti-aliasing, without FreeType.

  Pastel uses FreeType when it is there (it also hints small text); this unit
  is used where it is not: always on Android, and on a desktop without the
  FreeType library. Outlines with straight lines and quadratic curves (the
  "glyf" table) are supported, simple and composite glyphs, the cmap formats 4
  and 12 and kerning pairs of the "kern" table. Fonts with CFF outlines (.otf)
  are not.

`uses Pastel.TrueType;` · source: [framework/src/pastel.truetype.pas](../../framework/src/pastel.truetype.pas)

## Types

### ETrueType

```pascal
type ETrueType = class(Exception)
```

### TTrueTypeBitmap

```pascal
type TTrueTypeBitmap = record
```

A drawn glyph: Width x Height coverage bytes (0..255), row by row; Left is
the distance from the pen to the first column, Top from the baseline up to
the first row; Advance moves the pen.

| | |
|---|---|
| `Width: Integer` |  |
| `Height: Integer` |  |
| `Left: Integer` |  |
| `Top: Integer` |  |
| `Advance: Integer` |  |
| `Bits: array of Byte` |  |

### TTrueTypeFont

```pascal
type TTrueTypeFont = class
```

| | |
|---|---|
| `constructor Create(const FileName: string)` |  |
| `constructor CreateFromStream(Stream: TStream)` |  |
| `procedure Load` |  |
| `function GlyphIndex(CodePoint: Cardinal): Integer` | 0 when the font has no glyph for the code point. |
| `function AdvanceWidth(Glyph: Integer): Integer` | In font units. |
| `function Kerning(Left: Integer; Right: Integer): Integer` |  |
| `procedure Render(Glyph: Integer; Scale: Double; Embolden: Boolean; out Bitmap: TTrueTypeBitmap)` | Draws a glyph at Scale (pixels per font unit). Embolden thickens the strokes (a bold look from a regular font). |
| `property UnitsPerEm: Integer` |  |
| `property Ascender: Integer` |  |
| `property Descender: Integer` |  |
| `property LineGap: Integer` |  |
| `property NumGlyphs: Integer` |  |
| `function HasKerning: Boolean` |  |

