# Reports, PDF, Excel and printing

Business programs hand out paper: invoices, receipts, lists, exports for the accountant. Pastel makes them without other programs or libraries, in desktop apps, services and command-line tools alike:

| Unit | For |
|---|---|
| [`Pastel.Report`](#reports) | Invoices, lists, letters: headings, text, tables and totals that flow over pages; PDF or HTML |
| [`Pastel.Pdf`](#pdf-pages-drawn-by-you) | PDF pages drawn by you: text, lines, boxes, pictures at exact places (labels, forms, receipts) |
| [`Pastel.Sheets`](#excel-and-csv) | Excel files (`.xlsx`) and CSV, written and read |
| [`Pastel.Xml`](#xml) | XML for other programs (e-invoices, exports) |
| [`Pastel.Print`](#printing-and-opening) | The printers, printing a file, opening it in the system's viewer |

The [salon example](../examples/salon-desk/README.md) uses all of them: its invoices as PDF, printed, as an Excel list — on the desktop and from its server.

## Reports

```pascal
uses
  Pastel.Report;

var
  R: TReport;
begin
  R := TReport.Create;                         // A4; 'A5', 'Letter', '80 x 200' (a receipt), Landscape
  try
    R.Logo := 'assets/logo.png';               // top right of the first page
    R.Footer := 'Salon Ayşe · Page {page} of {pages}';
    R.Title('Invoice 2026-0012');
    R.Fields(['Customer', 'Ayşe Yılmaz', 'Date', '3 November 2026']);
    R.Table(['Service', 'Qty', 'Price'], [0, 20, 30], 'LRR');
    R.Row(['Color', '1', '900.50']);
    R.Row(['Cut', '1', '250.00']);
    R.EndTable;
    R.Total('Net', '1,150.50');
    R.Total('VAT 20%', '230.10');
    R.Total('Total', '1,380.60', True);
    R.Text('Thank you for your visit!');
    R.SaveToFile('invoice.pdf');               // or 'invoice.html'
  finally
    R.Free;
  end;
end;
```

Everything is written from top to bottom; when the page is full, a new one starts, and a table repeats its heads on it.

| | |
|---|---|
| `Title(S)`, `Heading(S)` | A big title; a smaller bold heading |
| `Text(S, Align)`, `Note(S)` | A paragraph (long lines wrap; `paLeft`, `paCenter`, `paRight`); smaller grey text |
| `Fields([Name, Value, ...])` | Names and values in two columns |
| `Table(Heads, Widths, Aligns)`, `Row(Cells, Bold)`, `EndTable` | Widths in millimetres, `0` shares what is left; aligns as letters: `L`, `R`, `C`. Cells wrap |
| `Total(Name, Value, Bold)` | Sums at the right |
| `Image(File, Width, Align)`, `Rule`, `Space(Mm)`, `NewPage` | A picture (PNG or JPEG), a thin line, empty space, a page break |
| `Footer`, `Header`, `Logo` | On every page (`{page}`, `{pages}`), on pages after the first, on the first |
| `TextSize`, `Accent`, `Striped`, `Margin` | Size of text (10 pt), the color of titles and table heads, striped rows, the margin (18 mm) |
| `SaveToFile`, `ToBytes`, `ToHtml` | `.pdf` or `.html`; the PDF as bytes (web, e-mail); the HTML page |
| `Pdf`, `Y`, `OnNewPage` | The page under it, for drawing of your own at `Y`; a method called on every new page |

**Letters.** Text uses a TrueType font of the system (DejaVu Sans or Liberation Sans on Linux, Arial on Windows), or `assets/fonts/Regular.ttf` and `Bold.ttf` of your app, or `PASTEL_FONT`. Only the letters that are used go into the file, so an invoice of one page is around 30 KB, and every letter — ş, ğ, İ, €, ₺ — prints right everywhere.

**On a server**, the same report answers a request:

```pascal
procedure TInvoiceController.Pdf(Req: TWebRequest; Res: TWebResponse);
var
  R: TReport;
begin
  R := InvoiceReport(Req.Param('id'));
  try
    Res.Bytes(R.ToBytes, 'application/pdf');                 // shown in the browser
    // Res.Bytes(R.ToBytes, 'application/pdf', 'invoice.pdf'); // downloaded
  finally
    R.Free;
  end;
end;
```

## PDF: pages drawn by you

For things that must sit at exact places — labels, a form to fill in, a receipt — draw the page yourself. Positions are millimetres from the top left corner.

```pascal
uses
  Pastel.Pdf;

var
  Pdf: TPdfDocument;
begin
  Pdf := TPdfDocument.Create('A4');
  try
    Pdf.Title := 'Labels';
    Pdf.SetFont(14, True);                         // points, bold
    Pdf.Text(20, 20, 'Ayşe Yılmaz');
    Pdf.SetFont(10);
    Pdf.TextColor := '#555555';
    Pdf.TextBox(20, 28, 70, 'Atatürk Cad. 12' + LineEnding + 'Kadıköy, İstanbul');
    Pdf.StrokeColor := '#3355AA';
    Pdf.Rect(15, 15, 80, 30);                      // a frame
    Pdf.Image(70, 18, 20, 0, 'assets/logo.png');   // height 0: keeps the shape
    Pdf.NewPage;
    Pdf.Text(20, 20, 'The second page');
    Pdf.SaveToFile('labels.pdf');
  finally
    Pdf.Free;
  end;
end;
```

| | |
|---|---|
| `Text(X, Y, S)`, `TextAligned(X, Y, W, S, Align)`, `TextBox(X, Y, W, S, Align)` | Text with its top at Y; in a box W wide; wrapped (returns its height) |
| `TextWidth(S)`, `LineHeight`, `WrapText(S, W)` | Measuring |
| `Line(X1, Y1, X2, Y2)`, `Rect(X, Y, W, H, Fill, Stroke)`, `Image(X, Y, W, H, File)` | Shapes and pictures |
| `SetFont(Size, Bold)`, `TextColor`, `FillColor`, `StrokeColor`, `LineWidth` | Colors as `'#RRGGBB'`, widths in millimetres |
| `NewPage`, `SetPage(I)`, `PageCount`, `PageWidth`, `PageHeight` | Pages |
| `LoadFonts(Regular, Bold)` | Other `.ttf` files |
| `Title`, `Author`, `Subject` | Shown by PDF viewers |

## Excel and CSV

```pascal
uses
  Pastel.Sheets;

var
  S: TSpreadsheet;
begin
  S := TSpreadsheet.Create('Invoices');
  try
    S.Widths([14, 30, 12, 12]);                                 // in characters
    S.Row(['Number', 'Customer', 'Date', 'Total'], True);       // True: bold
    S.Row(['2026-0012', 'Ayşe Yılmaz', EncodeDate(2026, 11, 3), 1380.60]);
    S.AddSheet('Customers');                                     // a second tab
    S.AddJson(Customers, ['name', 'phone'], ['Name', 'Phone']);  // JSON rows from Pastel.Db
    S.SaveToFile('invoices.xlsx');
  finally
    S.Free;
  end;
end;
```

Numbers, dates (`TDateTime`) and `True`/`False` go into Excel as such, so it can sum and sort them; everything else is text. `ToBytes` gives the file for a web answer (`Res.Bytes(S.ToBytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'invoices.xlsx')`).

Reading:

```pascal
var
  Rows: TSheetRows;            // array of rows, each an array of texts
  Items: TJSONArray;
begin
  Rows := ReadSpreadsheet('prices.xlsx');        // .xlsx (sheet 0, or ReadXlsx(File, 1)) or .csv
  WriteLn(Rows[1][0]);
  Items := RowsToJson(Rows);                     // [{"Name": "Cut", "Price": "250"}, ...] — the first row names them
end;
```

Numbers come as text with a dot (`'1380.6'`), dates as Excel's day numbers (`46329` = 3 November 2026; `TDateTime` counts the same way).

**CSV:** `ReadCsv(File)` guesses the separator (`,`, `;` or tab) and understands quotes; `WriteCsv(File, Rows, ';')` writes what Excel opens right (with a UTF-8 mark; `;` where Excel expects it, in countries that write `1,5`). `ParseCsv(Text)` and `CsvText(Rows)` work on text.

## XML

```pascal
uses
  Pastel.Xml;

var
  X: TXmlWriter;
begin
  X := TXmlWriter.Create;
  try
    X.Open('invoice', ['number', '2026-0012', 'date', '2026-11-03']);
    X.Element('customer', 'Ayşe Yılmaz');
    X.Open('lines');
    X.Element('line', 'Color', ['price', '900.50']);
    X.Close;
    X.Close;
    X.SaveToFile('invoice.xml');          // or X.ToString
  finally
    X.Free;
  end;
end;
```

Texts and attributes are escaped (`&`, `<`, quotes); a missing `Close` is an error. To read XML, Free Pascal's `DOM` and `XMLRead` units are there: `ReadXMLFile(Doc, 'file.xml')`.

## Printing and opening

```pascal
uses
  Pastel.Print;

R.SaveToFile(FileName);
OpenDocument(FileName);            // the PDF viewer: a preview with its own Print button
PrintFile(FileName);               // straight to the default printer
PrintFile(FileName, 'Kitchen', 2); // another printer, two copies
```

| | |
|---|---|
| `Printers`, `DefaultPrinter` | The names of the printers |
| `PrintFile(File, Printer, Copies)` | Linux: CUPS (`lp`); Windows: the program that prints PDF files (SumatraPDF, Adobe Reader, a browser) |
| `OpenDocument(FileOrUrl)` | With the system's program for it: a PDF, a `.xlsx`, a web address. Nothing happens in UI tests (`PASTEL_HEADLESS=1`) |

`EPrintError` says what is missing (no printer program, no CUPS).

## In the salon example

- Desktop ([`Home.pas`](../examples/salon-desk/src/forms/Home.pas)): **PDF** saves the selected invoice next to the database and opens it, **Print** prints it, **Excel** saves every invoice as `.xlsx`.
- Server ([`saloncontroller.pas`](../examples/salon-api/src/controllers/saloncontroller.pas)): `GET /api/invoices/:id/pdf` and `GET /api/invoices.xlsx`.
- Both use the same [`SalonPrint`](../examples/salon-core/src/salonprint.pas) unit of the shared library, so the invoice looks the same wherever it is made.
