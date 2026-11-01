# Pastel.Pdf

PDF files: pages with text, lines, boxes and pictures.

    var
      Pdf: TPdfDocument;
    begin
      Pdf := TPdfDocument.Create;            // A4, portrait; sizes in millimetres
      try
        Pdf.SetFont(18, True);
        Pdf.Text(20, 20, 'Fatura 2026-0012');
        Pdf.SetFont(11);
        Pdf.TextColor := '#555555';
        Pdf.Text(20, 30, 'Ayşe Yılmaz — 3 Kasım 2026');
        Pdf.Line(20, 38, 190, 38);
        Pdf.Image(150, 12, 40, 0, 'assets/logo.png');   // height 0: keep the shape
        Pdf.SaveToFile('fatura.pdf');
      finally
        Pdf.Free;
      end;
    end;

  Positions are in millimetres from the top left corner of the page. Text
  uses a TrueType font of the system (or one given with LoadFonts) that is
  put into the file, only with the letters that are used, so every letter
  (ş, ğ, İ, €, ...) prints right everywhere. Pictures: PNG and JPEG.

  For documents that flow over several pages (invoices, lists) Pastel.Report
  is easier: it places headings, paragraphs and tables and breaks pages.

`uses Pastel.Pdf;` · source: [framework/src/pastel.pdf.pas](../../framework/src/pastel.pdf.pas)

## Types

### EPdfError

```pascal
type EPdfError = class(Exception)
```

### TPdfAlign

```pascal
type TPdfAlign = (paLeft, paCenter, paRight)
```

- `paLeft`
- `paCenter`
- `paRight`
### TPdfFont

```pascal
type TPdfFont = class
```

A TrueType font: what PDF needs of it. Internal, used by TPdfDocument.

| | |
|---|---|
| `constructor Create(const FileName: string)` |  |
| `destructor Destroy` |  |
| `function GlyphOf(CodePoint: Cardinal): Integer` |  |
| `function Advance(G: Integer): Single` | Width of a glyph in 1/1000 of the font size. |
| `function Subset: TBytes` | The font file with only the used glyphs (the others empty). |
| `property UnitsPerEm: Integer` |  |
| `property Name: string` |  |

### TPdfDocument

```pascal
type TPdfDocument = class
```

| | |
|---|---|
| `constructor Create(const Size: string = 'A4'; Landscape: Boolean = False)` | Size: 'A4' (default), 'A5', 'A3', 'Letter', 'Legal', or 'W x H' in millimetres ('80 x 200' for a receipt). |
| `destructor Destroy` |  |
| `procedure LoadFonts(const Regular: string; const Bold: string = '')` | Uses these .ttf files instead of the system's font (Bold may be ''). |
| `procedure NewPage` | A new page (the first one is made by the first drawing); it is the current page now. |
| `procedure SetPage(Index: Integer)` | Draws on another page (0 = the first): for page numbers at the end. |
| `function PageCount: Integer` |  |
| `property Page: Integer` |  |
| `function PageWidth: Single` | The page's size in millimetres. |
| `function PageHeight: Single` |  |
| `procedure SetFont(Size: Single; Bold: Boolean = False)` | Size in points (11 is usual for text), and bold or not. |
| `property FontSize: Single` |  |
| `property Bold: Boolean` |  |
| `function LineHeight: Single` | The height of a line of text in millimetres. |
| `function TextWidth(const S: string): Single` |  |
| `procedure Text(X: Single; Y: Single; const S: string)` | Text with its top at Y. |
| `procedure TextAligned(X: Single; Y: Single; W: Single; const S: string; Align: TPdfAlign)` | Text in a box W wide: left, centred or right of it. |
| `function WrapText(const S: string; Width: Single): TStringArray` | The lines of S that fit into Width (at words; line breaks in S stay). |
| `function TextBox(X: Single; Y: Single; W: Single; const S: string; Align: TPdfAlign = paLeft): Single` | Wrapped text; returns the height it took. |
| `procedure Line(X1: Single; Y1: Single; X2: Single; Y2: Single)` |  |
| `procedure Rect(X: Single; Y: Single; W: Single; H: Single; Fill: Boolean = False; Stroke: Boolean = True)` |  |
| `procedure Image(X: Single; Y: Single; W: Single; H: Single; const FileName: string)` | A PNG or JPEG picture. W or H 0: from the other one, keeping the shape. |
| `procedure ImageSize(const FileName: string; out W: Integer; out H: Integer)` | The size of a picture in pixels. |
| `property TextColor: string` | '#RRGGBB' |
| `property FillColor: string` |  |
| `property StrokeColor: string` |  |
| `property LineWidth: Single` | Width of lines in millimetres (0.2 by default). |
| `property Title: string` |  |
| `property Author: string` |  |
| `property Subject: string` |  |
| `procedure SaveToStream(Stream: TStream)` |  |
| `procedure SaveToFile(const FileName: string)` |  |
| `function ToBytes: TBytes` | The file as bytes (for a web answer or an e-mail attachment). |

## Routines

### FindPdfFonts

```pascal
procedure FindPdfFonts(out Regular: string; out Bold: string)
```

The .ttf files used when none are given: PASTEL_FONT / PASTEL_FONT_BOLD,
assets/fonts/ next to the program, or the system's.

