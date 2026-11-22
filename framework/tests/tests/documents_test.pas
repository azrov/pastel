{ Tests for Pastel.Pdf, Pastel.Report, Pastel.Sheets and Pastel.Xml. }
unit Documents_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Variants, fpjson, Pastel.Testing, Pastel.Pdf, Pastel.Report, Pastel.Sheets, Pastel.Xml,
  Pastel.Files, Pastel.Json;

type
  TDocumentsTests = class(TTestSuite)
  private
    procedure NeedFont;
    procedure UnknownSize;
    procedure UnclosedXml;
  published
    procedure APdfWithTurkishLetters;
    procedure FontsAreSubset;
    procedure TextWrapsAtWords;
    procedure PageSizes;
    procedure AReportBreaksPagesAndRepeatsTableHeads;
    procedure AReportAsHtml;
    procedure SpreadsheetsGoAndComeBack;
    procedure CsvWithQuotesAndSemicolons;
    procedure RowsAsJson;
    procedure XmlIsEscaped;
  end;

implementation

function AsText(const B: TBytes): string;
begin
  SetString(Result, PAnsiChar(@B[0]), Length(B));
end;

procedure TDocumentsTests.NeedFont;
var
  R, B: string;
begin
  FindPdfFonts(R, B);
  if R = '' then
    Skip('no TrueType font on this computer');
end;

procedure TDocumentsTests.APdfWithTurkishLetters;
var
  Pdf: TPdfDocument;
  S: string;
begin
  NeedFont;
  Pdf := TPdfDocument.Create;
  try
    Pdf.Title := 'Fatura';
    Pdf.SetFont(14, True);
    Pdf.Text(20, 20, 'Şeyma Güneş İğdır 1.080,60 €');
    Pdf.SetFont(10);
    Pdf.Line(20, 30, 190, 30);
    Pdf.Rect(20, 35, 50, 10, True);
    S := AsText(Pdf.ToBytes);
  finally
    Pdf.Free;
  end;
  AssertStartsWith('%PDF-1.4', S);
  AssertContains('/Count 1', S);
  AssertContains('/Subtype /Type0', S, 'Unicode text: a CID font');
  AssertContains('/ToUnicode', S, 'the text can be copied');
  AssertContains('%%EOF', S);
end;

procedure TDocumentsTests.FontsAreSubset;
var
  Pdf: TPdfDocument;
  N: Integer;
begin
  NeedFont;
  Pdf := TPdfDocument.Create;
  try
    Pdf.Text(10, 10, 'Hello');
    N := Length(Pdf.ToBytes);
  finally
    Pdf.Free;
  end;
  AssertTrue(N < 60000, Format('only the used letters go into the file (%d bytes)', [N]));
end;

procedure TDocumentsTests.TextWrapsAtWords;
var
  Pdf: TPdfDocument;
  L: TStringArray;
begin
  NeedFont;
  Pdf := TPdfDocument.Create;
  try
    Pdf.SetFont(10);
    AssertTrue(Pdf.TextWidth('WWWW') > Pdf.TextWidth('iiii'));
    L := Pdf.WrapText('one two three four five six seven eight nine ten', 30);
    AssertTrue(Length(L) > 1, 'wrapped');
    AssertEquals('one', Copy(L[0], 1, 3));
    L := Pdf.WrapText('a'#10'b', 100);
    AssertEquals(2, Length(L), 'line breaks stay');
  finally
    Pdf.Free;
  end;
end;

procedure TDocumentsTests.UnknownSize;
begin
  TPdfDocument.Create('B9').Free;
end;

procedure TDocumentsTests.PageSizes;
var
  Pdf: TPdfDocument;
begin
  Pdf := TPdfDocument.Create('A4', True);
  try
    AssertEquals(297, Pdf.PageWidth, 0.01, 'landscape');
  finally
    Pdf.Free;
  end;
  Pdf := TPdfDocument.Create('80 x 200');
  try
    AssertEquals(80, Pdf.PageWidth, 0.01, 'a receipt');
  finally
    Pdf.Free;
  end;
  AssertRaises(EPdfError, @UnknownSize);
end;

procedure TDocumentsTests.AReportBreaksPagesAndRepeatsTableHeads;
var
  R: TReport;
  I: Integer;
  S: string;
begin
  NeedFont;
  R := TReport.Create;
  try
    R.Footer := 'Page {page} of {pages}';
    R.Title('Invoice');
    R.Table(['Service', 'Price'], [0, 30], 'LR');
    for I := 1 to 80 do
      R.Row(['Line ' + IntToStr(I), '10.00']);
    R.EndTable;
    R.Total('Total', '800.00', True);
    AssertTrue(R.Pdf.PageCount >= 2, 'more than one page');
    S := AsText(R.ToBytes);
  finally
    R.Free;
  end;
  AssertContains('/Count ', S);
end;

procedure TDocumentsTests.AReportAsHtml;
var
  R: TReport;
  H: string;
begin
  R := TReport.Create;
  try
    R.Title('Invoice <1>');
    R.Fields(['Customer', 'Ayşe & Ali']);
    R.Table(['A', 'B'], [0, 20], 'LR');
    R.Row(['x', '1']);
    R.EndTable;
    H := R.ToHtml;
  finally
    R.Free;
  end;
  AssertContains('<h1>Invoice &lt;1&gt;</h1>', H);
  AssertContains('<td>Ayşe &amp; Ali</td>', H);
  AssertContains('<td style="text-align:right">1</td>', H);
end;

procedure TDocumentsTests.SpreadsheetsGoAndComeBack;
var
  S: TSpreadsheet;
  F: string;
  Rows: TSheetRows;
begin
  F := JoinPath([MakeTempDir, 'test.xlsx']);
  S := TSpreadsheet.Create('Faturalar');
  try
    S.Row(['No', 'Müşteri', 'Tarih', 'Toplam', 'Ödendi'], True);
    S.Row(['2026-0012', 'Ayşe "Y" & Co', EncodeDate(2026, 11, 3), 1380.6, True]);
    S.AddSheet('İkinci');
    S.Row(['x']);
    S.SaveToFile(F);
  finally
    S.Free;
  end;
  Rows := ReadSpreadsheet(F);
  AssertEquals(2, Length(Rows));
  AssertEquals('Müşteri', Rows[0][1]);
  AssertEquals('Ayşe "Y" & Co', Rows[1][1]);
  AssertEquals('46329', Rows[1][2], 'a date is a day number');
  AssertEquals('1380.6', Rows[1][3]);
  AssertEquals('true', Rows[1][4]);
  Rows := ReadXlsx(F, 1);
  AssertEquals('x', Rows[0][0], 'the second sheet');
end;

procedure TDocumentsTests.CsvWithQuotesAndSemicolons;
var
  Rows: TSheetRows;
  Back: string;
begin
  Rows := ParseCsv('name;note'#13#10'Ayşe;"says ""hi""; twice"'#10'Ali;"two'#10'lines"'#10);
  AssertEquals(3, Length(Rows));
  AssertEquals('says "hi"; twice', Rows[1][1], 'the separator is guessed');
  AssertEquals('two'#10'lines', Rows[2][1]);
  Back := CsvText(Rows, ';');
  AssertContains('"says ""hi""; twice"', Back);
  AssertEquals(3, Length(ParseCsv(Back)));
end;

procedure TDocumentsTests.RowsAsJson;
var
  A: TJSONArray;
  Rows: TSheetRows;
begin
  Rows := ParseCsv('Name,Price'#10'Cut,250'#10);
  A := RowsToJson(Rows);
  try
    AssertEquals('[{"Name":"Cut","Price":"250"}]', StringReplace(A.AsJSON, ' ', '', [rfReplaceAll]));
  finally
    A.Free;
  end;
end;

procedure TDocumentsTests.UnclosedXml;
var
  X: TXmlWriter;
begin
  X := TXmlWriter.Create;
  try
    X.Open('a');
    X.ToString;
  finally
    X.Free;
  end;
end;

procedure TDocumentsTests.XmlIsEscaped;
var
  X: TXmlWriter;
  S: string;
begin
  X := TXmlWriter.Create;
  try
    X.Open('invoice', ['number', '1 & 2']);
    X.Element('customer', 'Ayşe <Co>');
    X.Element('empty', '');
    X.Close;
    S := X.ToString;
  finally
    X.Free;
  end;
  AssertContains('<invoice number="1 &amp; 2">', S);
  AssertContains('  <customer>Ayşe &lt;Co&gt;</customer>', S);
  AssertContains('<empty/>', S);
  AssertRaises(EXmlError, @UnclosedXml);
end;

initialization
  RegisterTests(TDocumentsTests);

end.
