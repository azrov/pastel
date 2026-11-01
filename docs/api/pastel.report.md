# Pastel.Report

Reports: invoices, lists, letters as PDF (and HTML), written
  from top to bottom; the pages break by themselves.

    var
      R: TReport;
    begin
      R := TReport.Create;                       // A4, margins 18 mm
      try
        R.Logo := 'assets/logo.png';             // top right of the first page
        R.Footer := 'Salon Ayşe · Page {page} of {pages}';
        R.Title('Invoice 2026-0012');
        R.Fields(['Customer', 'Ayşe Yılmaz', 'Date', '3 November 2026']);
        R.Table(['Service', 'Qty', 'Price'], [0, 20, 30], 'LRR');   // 0: the rest of the width
        R.Row(['Color', '1', '900.50']);
        R.Row(['Cut', '1', '250.00']);
        R.EndTable;
        R.Total('Net', '1,150.50');
        R.Total('VAT 20%', '230.10');
        R.Total('Total', '1,380.60', True);
        R.Text('Thank you for your visit!');
        R.SaveToFile('invoice.pdf');             // .html: the same as a web page
      finally
        R.Free;
      end;
    end;

  Positions and sizes are in millimetres. For drawing of your own, Pdf is
  the page (Pastel.Pdf) and Y the place where the next thing goes.

`uses Pastel.Report;` · source: [framework/src/pastel.report.pas](../../framework/src/pastel.report.pas)

## Types

### TReport

```pascal
type TReport = class
```

| | |
|---|---|
| `constructor Create(const Size: string = 'A4'; Landscape: Boolean = False)` | Size: 'A4', 'A5', 'Letter', or '80 x 200' (millimetres) for a receipt. |
| `destructor Destroy` |  |
| `procedure NeedSpace(H: Single)` | Makes room for H millimetres: a new page when they do not fit. |
| `procedure NewPage` |  |
| `procedure Space(H: Single = 4)` | Space below the last thing. |
| `procedure Title(const S: string)` | A big bold line. |
| `procedure Heading(const S: string)` | A bold line, a little bigger than text. |
| `procedure Text(const S: string; Align: TPdfAlign = paLeft)` | A paragraph; long lines wrap. |
| `procedure Note(const S: string)` | Smaller grey text. |
| `procedure Fields(const NamesAndValues: array of string)` | Name, value, name, value...: two columns, for the details of an invoice. |
| `procedure Rule` | A thin line across the page. |
| `procedure Image(const FileName: string; Width: Single = 0; Align: TPdfAlign = paLeft)` | A picture; Width 0: its own size (96 pixels per inch), at most the page's width. |
| `procedure Table(const Heads: array of string; const Widths: array of Single; const Aligns: string = '')` | A table: the column titles, their widths (0: share what is left) and their alignment as letters ('LRR': left, right, right; C: centre). Rows follow with Row; on a new page the titles are repeated. |
| `procedure Row(const Cells: array of string; Bold: Boolean = False)` |  |
| `procedure EndTable` |  |
| `procedure Total(const Name: string; const Value: string; Bold: Boolean = False)` | A line at the right: 'Total' and its amount (bold for the last one). |
| `procedure SaveToFile(const FileName: string)` |  |
| `procedure SaveToStream(Stream: TStream)` |  |
| `function ToBytes: TBytes` | The report as PDF bytes (for a web answer or an e-mail). |
| `function ToHtml: string` | The same report as an HTML page. |
| `property Pdf: TPdfDocument` | The PDF, for drawing of your own. |
| `property Y: Single` | Where the next thing goes, millimetres from the top of the page. |
| `property Margin: Single` |  |
| `function ContentWidth: Single` | The width between the margins. |
| `property Footer: string` | Text at the bottom of every page; {page} and {pages} become numbers. |
| `property Header: string` | Small text at the top of every page but the first. |
| `property Logo: string` | A picture at the top right of the first page (a logo). |
| `property TextSize: Single` | The size of normal text in points (10 by default). |
| `property Accent: string` | The color of titles and table heads. |
| `property Striped: Boolean` | Every other table row with a light background (default True). |
| `property OnNewPage: TReportEvent` | Called on every new page, after the header: draw what every page has. |

## Other types

| | |
|---|---|
| `type TReportEvent = procedure(Report: TReport)` |  |

