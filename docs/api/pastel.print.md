# Pastel.Print

Printing and opening documents with the system.

    R.SaveToFile(TempFile);           // a PDF from Pastel.Report
    OpenDocument(TempFile);           // shown in the PDF viewer: a preview, with its Print button
    PrintFile(TempFile);              // or straight to the default printer
    PrintFile(TempFile, 'Kitchen');   // to another one; Printers lists them

  Linux prints with CUPS (lp), Windows with the program that opens PDF files.

`uses Pastel.Print;` · source: [framework/src/pastel.print.pas](../../framework/src/pastel.print.pas)

## Types

### EPrintError

```pascal
type EPrintError = class(Exception)
```

## Routines

### Printers

```pascal
function Printers: TStringArray
```

The printers of this computer (their names).

### DefaultPrinter

```pascal
function DefaultPrinter: string
```

The default printer; '' when there is none.

### PrintFile

```pascal
procedure PrintFile(const FileName: string; const Printer: string = ''; Copies: Integer = 1)
```

Prints a PDF (or a picture, or a text file) on Printer, the default one when ''.

### OpenDocument

```pascal
procedure OpenDocument(const FileNameOrUrl: string)
```

Opens a file with the program the system uses for it (a PDF in the PDF
viewer, a .xlsx in the spreadsheet program, a web address in the browser).
Nothing happens while UI tests run (PASTEL_HEADLESS=1).

