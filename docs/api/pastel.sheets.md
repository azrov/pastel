# Pastel.Sheets

Spreadsheets: Excel files (.xlsx) and CSV, written and read.

    var
      S: TSpreadsheet;
    begin
      S := TSpreadsheet.Create('Invoices');
      try
        S.Widths([14, 30, 12, 12]);
        S.Row(['Number', 'Customer', 'Date', 'Total'], True);       // True: bold
        S.Row(['2026-0012', 'Ayşe Yılmaz', EncodeDate(2026, 11, 3), 1380.60]);
        S.Row(['2026-0013', 'Ali Can', EncodeDate(2026, 11, 4), 250]);
        S.SaveToFile('invoices.xlsx');            // or .csv
      finally
        S.Free;
      end;
    end;

    Rows := ReadSpreadsheet('prices.xlsx');       // .xlsx or .csv: rows of texts
    Items := RowsToJson(Rows);                     // [{"Name": "Cut", "Price": "250"}, ...]

  Numbers, dates and true/false go into Excel as such (it can calculate
  with them); everything else as text. Reading gives texts: numbers with a
  dot ('1380.6'), dates as Excel's day numbers unless the cell is text.

`uses Pastel.Sheets;` · source: [framework/src/pastel.sheets.pas](../../framework/src/pastel.sheets.pas)

**Contents:** [ESheetError](#esheeterror) · [TSpreadsheet](#tspreadsheet) · [ReadSpreadsheet](#readspreadsheet) · [ReadXlsx](#readxlsx) · [ReadCsv](#readcsv) · [ParseCsv](#parsecsv) · [WriteCsv](#writecsv) · [CsvText](#csvtext) · [RowsToJson](#rowstojson)

## Types

### ESheetError

```pascal
type ESheetError = class(Exception)
```

### TSpreadsheet

```pascal
type TSpreadsheet = class
```

| | |
|---|---|
| `constructor Create(const FirstSheet: string = 'Sheet1')` |  |
| `destructor Destroy` |  |
| `procedure AddSheet(const Name: string)` | A new sheet (tab); rows go there from now on. |
| `procedure Widths(const W: array of Single)` | The widths of the columns, in characters. |
| `procedure Row(const Values: array of Variant; Bold: Boolean = False)` | One row: texts, numbers, dates (TDateTime as a Variant), True/False. |
| `procedure AddJson(Items: TJSONArray; const Fields: array of string; const Titles: array of string)` | JSON objects as rows: the fields in this order, with Titles as the first row. |
| `procedure SaveToFile(const FileName: string)` | .xlsx, or .csv (the sheet rows go to now). |
| `procedure SaveToStream(Stream: TStream)` |  |
| `function ToBytes: TBytes` | The .xlsx file as bytes (for a web answer). |

## Other types

| | |
|---|---|
| `type TSheetRows = array of TStringArray` |  |

## Routines

### ReadSpreadsheet

```pascal
function ReadSpreadsheet(const FileName: string; Sheet: Integer = 0): TSheetRows
```

The rows of a .xlsx (its sheet number Sheet, 0 = the first) or .csv file.

### ReadXlsx

```pascal
function ReadXlsx(const FileName: string; Sheet: Integer = 0): TSheetRows
```

### ReadCsv

```pascal
function ReadCsv(const FileName: string; Separator: Char = ''): TSheetRows
```

CSV; Separator #0: guessed from the first line (, ; or tab).

### ParseCsv

```pascal
function ParseCsv(const Text: string; Separator: Char = ''): TSheetRows
```

### WriteCsv

```pascal
procedure WriteCsv(const FileName: string; const Rows: TSheetRows; Separator: Char = ',')
```

CSV that Excel opens right (with a UTF-8 mark); ';' is what Excel expects
in countries that write 1,5 for one and a half.

### CsvText

```pascal
function CsvText(const Rows: TSheetRows; Separator: Char = ','): string
```

### RowsToJson

```pascal
function RowsToJson(const Rows: TSheetRows): TJSONArray
```

Rows as JSON objects, the first row giving the names.

