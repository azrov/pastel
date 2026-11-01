(* Pastel - spreadsheets: Excel files (.xlsx) and CSV, written and read.

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
  Part of the Pastel project, MIT License. *)
unit Pastel.Sheets;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Variants, fpjson;

type
  ESheetError = class(Exception);
  TSheetRows = array of TStringArray;

  TSpreadsheet = class
  private
    FSheets: TStringList;           { name -> TStringList of row XML }
    FWidths: TStringList;           { name -> <cols> XML }
    FCurrent: Integer;
    function Rows: TStringList;
    function CellXml(Col, RowNo: Integer; const V: Variant; Bold: Boolean): string;
  public
    constructor Create(const FirstSheet: string = 'Sheet1');
    destructor Destroy; override;
    { A new sheet (tab); rows go there from now on. }
    procedure AddSheet(const Name: string);
    { The widths of the columns, in characters. }
    procedure Widths(const W: array of Single);
    { One row: texts, numbers, dates (TDateTime as a Variant), True/False. }
    procedure Row(const Values: array of Variant; Bold: Boolean = False);
    { JSON objects as rows: the fields in this order, with Titles as the first row. }
    procedure AddJson(Items: TJSONArray; const Fields: array of string; const Titles: array of string);
    { .xlsx, or .csv (the sheet rows go to now). }
    procedure SaveToFile(const FileName: string);
    procedure SaveToStream(Stream: TStream);
    { The .xlsx file as bytes (for a web answer). }
    function ToBytes: TBytes;
  end;

{ The rows of a .xlsx (its sheet number Sheet, 0 = the first) or .csv file. }
function ReadSpreadsheet(const FileName: string; Sheet: Integer = 0): TSheetRows;
function ReadXlsx(const FileName: string; Sheet: Integer = 0): TSheetRows;
{ CSV; Separator #0: guessed from the first line (, ; or tab). }
function ReadCsv(const FileName: string; Separator: Char = #0): TSheetRows;
function ParseCsv(const Text: string; Separator: Char = #0): TSheetRows;
{ CSV that Excel opens right (with a UTF-8 mark); ';' is what Excel expects
  in countries that write 1,5 for one and a half. }
procedure WriteCsv(const FileName: string; const Rows: TSheetRows; Separator: Char = ',');
function CsvText(const Rows: TSheetRows; Separator: Char = ','): string;
{ Rows as JSON objects, the first row giving the names. }
function RowsToJson(const Rows: TSheetRows): TJSONArray;

implementation

uses
  Math, StrUtils, DateUtils, Zipper, DOM, XMLRead;

function XmlEsc(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      #0..#8, #11, #12, #14..#31: ;       { not allowed in XML }
    else
      Result := Result + S[I];
    end;
end;

function ColName(Col: Integer): string;
begin
  Result := '';
  Inc(Col);
  while Col > 0 do
  begin
    Result := Chr(Ord('A') + (Col - 1) mod 26) + Result;
    Col := (Col - 1) div 26;
  end;
end;

{ ---- writing ---- }

constructor TSpreadsheet.Create(const FirstSheet: string);
begin
  inherited Create;
  FSheets := TStringList.Create;
  FSheets.OwnsObjects := True;
  FWidths := TStringList.Create;
  AddSheet(FirstSheet);
end;

destructor TSpreadsheet.Destroy;
begin
  FSheets.Free;
  FWidths.Free;
  inherited Destroy;
end;

procedure TSpreadsheet.AddSheet(const Name: string);
var
  N: string;
begin
  { Excel: at most 31 characters, none of []:*?/\ }
  N := Copy(Name, 1, 31);
  N := StringsReplace(N, ['[', ']', ':', '*', '?', '/', '\'], ['(', ')', '-', '-', '', '-', '-'], [rfReplaceAll]);
  if N = '' then
    N := 'Sheet' + IntToStr(FSheets.Count + 1);
  FCurrent := FSheets.AddObject(N, TStringList.Create);
  FWidths.Add('');
end;

function TSpreadsheet.Rows: TStringList;
begin
  Result := TStringList(FSheets.Objects[FCurrent]);
end;

procedure TSpreadsheet.Widths(const W: array of Single);
var
  I: Integer;
  S: string;
begin
  S := '<cols>';
  for I := 0 to High(W) do
    S := S + Format('<col min="%d" max="%d" width="%s" customWidth="1"/>',
      [I + 1, I + 1, FormatFloat('0.##', W[I], DefaultFormatSettings)]);
  FWidths[FCurrent] := S + '</cols>';
end;

function TSpreadsheet.CellXml(Col, RowNo: Integer; const V: Variant; Bold: Boolean): string;
var
  Ref, Style: string;
  D: Double;
begin
  Ref := ColName(Col) + IntToStr(RowNo);
  if Bold then Style := ' s="1"' else Style := '';
  case VarType(V) and varTypeMask of
    varEmpty, varNull:
      Result := '';
    varBoolean:
      Result := Format('<c r="%s" t="b"%s><v>%d</v></c>', [Ref, Style, Ord(Boolean(V))]);
    varDate:
      begin
        { Excel counts days from 30 December 1899, like TDateTime }
        D := VarToDateTime(V);
        if Frac(D) = 0 then
          Style := IfThen(Bold, ' s="3"', ' s="2"')
        else
          Style := IfThen(Bold, ' s="5"', ' s="4"');
        Result := Format('<c r="%s"%s><v>%s</v></c>', [Ref, Style, FloatToStr(D, DefaultFormatSettings)]);
      end;
    varSmallint, varInteger, varSingle, varDouble, varCurrency, varShortInt, varByte, varWord,
    varLongWord, varInt64, varQWord:
      Result := Format('<c r="%s"%s><v>%s</v></c>', [Ref, Style, FloatToStr(Double(V), DefaultFormatSettings)]);
  else
    Result := Format('<c r="%s" t="inlineStr"%s><is><t xml:space="preserve">%s</t></is></c>',
      [Ref, Style, XmlEsc(VarToStr(V))]);
  end;
end;

procedure TSpreadsheet.Row(const Values: array of Variant; Bold: Boolean);
var
  I, N: Integer;
  S: string;
begin
  N := Rows.Count + 1;
  S := Format('<row r="%d">', [N]);
  for I := 0 to High(Values) do
    S := S + CellXml(I, N, Values[I], Bold);
  Rows.Add(S + '</row>');
end;

procedure TSpreadsheet.AddJson(Items: TJSONArray; const Fields: array of string; const Titles: array of string);
var
  I, J: Integer;
  Vals: array of Variant;
  D: TJSONData;
  O: TJSONObject;
begin
  if Length(Titles) > 0 then
  begin
    SetLength(Vals, Length(Titles));
    for J := 0 to High(Titles) do
      Vals[J] := Titles[J];
    Row(Vals, True);
  end;
  SetLength(Vals, Length(Fields));
  for I := 0 to Items.Count - 1 do
  begin
    if not (Items[I] is TJSONObject) then
      Continue;
    O := TJSONObject(Items[I]);
    for J := 0 to High(Fields) do
    begin
      D := O.Find(Fields[J]);
      if (D = nil) or (D.JSONType = jtNull) then
        Vals[J] := Null
      else if D.JSONType = jtNumber then
        Vals[J] := D.AsFloat
      else if D.JSONType = jtBoolean then
        Vals[J] := D.AsBoolean
      else
        Vals[J] := D.AsString;
    end;
    Row(Vals);
  end;
end;

procedure TSpreadsheet.SaveToStream(Stream: TStream);
var
  Z: TZipper;
  Streams: TFPList;
  I: Integer;
  S, Sheets, Rels, Types: string;

  procedure Add(const Name, Text: string);
  var
    M: TStringStream;
  begin
    M := TStringStream.Create(Text);
    Streams.Add(M);
    Z.Entries.AddFileEntry(M, Name);
  end;

begin
  Z := TZipper.Create;
  Streams := TFPList.Create;
  try
    Sheets := '';
    Rels := '';
    Types := '';
    for I := 0 to FSheets.Count - 1 do
    begin
      Sheets := Sheets + Format('<sheet name="%s" sheetId="%d" r:id="rId%d"/>', [XmlEsc(FSheets[I]), I + 1, I + 1]);
      Rels := Rels + Format('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>', [I + 1, I + 1]);
      Types := Types + Format('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>', [I + 1]);
    end;
    Add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
      Types + '</Types>');
    Add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
      '</Relationships>');
    Add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' +
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>' + Sheets + '</sheets></workbook>');
    Add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + Rels +
      Format('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>', [FSheets.Count + 1]) +
      '</Relationships>');
    { styles: 0 normal, 1 bold, 2 date, 3 bold date, 4 date and time, 5 bold date and time }
    Add('xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm"/></numFmts>' +
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="6">' +
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
      '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
      '<xf numFmtId="14" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>' +
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
      '<xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>' +
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>');
    for I := 0 to FSheets.Count - 1 do
    begin
      S := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
        FWidths[I] + '<sheetData>' + TStringList(FSheets.Objects[I]).Text.Replace(LineEnding, '') +
        '</sheetData></worksheet>';
      Add(Format('xl/worksheets/sheet%d.xml', [I + 1]), S);
    end;
    Z.SaveToStream(Stream);
  finally
    for I := 0 to Streams.Count - 1 do
      TObject(Streams[I]).Free;
    Streams.Free;
    Z.Free;
  end;
end;

procedure TSpreadsheet.SaveToFile(const FileName: string);
var
  F: TFileStream;
  Rows_: TSheetRows;
  Tmp: string;
begin
  if SameText(ExtractFileExt(FileName), '.csv') then
  begin
    { through .xlsx and back: one way of turning values into text }
    Tmp := GetTempFileName('', 'pastel') + '.xlsx';
    try
      SaveToFile(Tmp);
      Rows_ := ReadXlsx(Tmp, FCurrent);
    finally
      DeleteFile(Tmp);
    end;
    WriteCsv(FileName, Rows_);
    Exit;
  end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(F);
  finally
    F.Free;
  end;
end;

function TSpreadsheet.ToBytes: TBytes;
var
  M: TMemoryStream;
begin
  M := TMemoryStream.Create;
  try
    SaveToStream(M);
    Result := nil;
    SetLength(Result, M.Size);
    if M.Size > 0 then
      Move(M.Memory^, Result[0], M.Size);
  finally
    M.Free;
  end;
end;

{ ---- reading .xlsx ---- }

type
  TMemUnzip = class
    Files: TStringList;     { name -> TMemoryStream }
    constructor Create;
    destructor Destroy; override;
    procedure CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    function Doc(const Name: string): TXMLDocument;
  end;

constructor TMemUnzip.Create;
begin
  Files := TStringList.Create;
  Files.OwnsObjects := True;
end;

destructor TMemUnzip.Destroy;
begin
  Files.Free;
  inherited Destroy;
end;

procedure TMemUnzip.CreateStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream := TMemoryStream.Create;
end;

procedure TMemUnzip.DoneStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
begin
  AStream.Position := 0;
  Files.AddObject(AItem.ArchiveFileName, AStream);
  AStream := nil;
end;

function TMemUnzip.Doc(const Name: string): TXMLDocument;
var
  I: Integer;
begin
  Result := nil;
  I := Files.IndexOf(Name);
  if I < 0 then
    Exit;
  TStream(Files.Objects[I]).Position := 0;
  ReadXMLFile(Result, TStream(Files.Objects[I]));
end;

function TextOf(N: TDOMNode): string;
var
  C: TDOMNode;
begin
  { the <t> elements inside (a shared string can be rich text: <r><t>) }
  Result := '';
  C := N.FirstChild;
  while C <> nil do
  begin
    if C.NodeName = 't' then
      Result := Result + UTF8Encode(C.TextContent)
    else if C.NodeName = 'r' then
      Result := Result + TextOf(C);
    C := C.NextSibling;
  end;
end;

function ReadXlsx(const FileName: string; Sheet: Integer): TSheetRows;
var
  U: TUnZipper;
  M: TMemUnzip;
  Book, Rels, Strings, Data: TXMLDocument;
  Shared: TStringList;
  N, Row_, C, V: TDOMNode;
  Sheets: TDOMNodeList;
  Target, Rid, Ref, T, Val, Letters: string;
  RowNo, Col, K: Integer;
  Cells: TStringArray;
begin
  Result := nil;
  if not FileExists(FileName) then
    raise ESheetError.CreateFmt('%s does not exist', [FileName]);
  M := TMemUnzip.Create;
  U := TUnZipper.Create;
  Shared := TStringList.Create;
  Book := nil; Rels := nil; Strings := nil; Data := nil;
  try
    U.FileName := FileName;
    U.OnCreateStream := @M.CreateStream;
    U.OnDoneStream := @M.DoneStream;
    try
      U.UnZipAllFiles;
    except
      on E: Exception do
        raise ESheetError.CreateFmt('%s is not an Excel file (.xlsx): %s', [FileName, E.Message]);
    end;
    Book := M.Doc('xl/workbook.xml');
    Rels := M.Doc('xl/_rels/workbook.xml.rels');
    if (Book = nil) or (Rels = nil) then
      raise ESheetError.CreateFmt('%s is not an Excel file (.xlsx)', [FileName]);
    Sheets := Book.GetElementsByTagName('sheet');
    try
      if (Sheet < 0) or (Sheet >= Integer(Sheets.Count)) then
        raise ESheetError.CreateFmt('%s has no sheet %d (it has %d)', [FileName, Sheet, Sheets.Count]);
      Rid := UTF8Encode(TDOMElement(Sheets[Sheet]).GetAttribute('r:id'));
    finally
      Sheets.Free;
    end;
    Target := '';
    N := Rels.DocumentElement.FirstChild;
    while N <> nil do
    begin
      if (N is TDOMElement) and (UTF8Encode(TDOMElement(N).GetAttribute('Id')) = Rid) then
        Target := UTF8Encode(TDOMElement(N).GetAttribute('Target'));
      N := N.NextSibling;
    end;
    if Copy(Target, 1, 1) = '/' then
      Delete(Target, 1, 1)
    else
      Target := 'xl/' + Target;
    Strings := M.Doc('xl/sharedStrings.xml');
    if Strings <> nil then
    begin
      N := Strings.DocumentElement.FirstChild;
      while N <> nil do
      begin
        if N.NodeName = 'si' then
          Shared.Add(TextOf(N));
        N := N.NextSibling;
      end;
    end;
    Data := M.Doc(Target);
    if Data = nil then
      raise ESheetError.CreateFmt('%s: the sheet %s is missing', [FileName, Target]);
    N := Data.DocumentElement.FindNode('sheetData');
    if N = nil then
      Exit;
    Row_ := N.FirstChild;
    while Row_ <> nil do
    begin
      if Row_.NodeName = 'row' then
      begin
        RowNo := StrToIntDef(UTF8Encode(TDOMElement(Row_).GetAttribute('r')), Length(Result) + 1);
        while Length(Result) < RowNo - 1 do
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := nil;
        end;
        Cells := nil;
        C := Row_.FirstChild;
        Col := 0;
        while C <> nil do
        begin
          if C.NodeName = 'c' then
          begin
            Ref := UTF8Encode(TDOMElement(C).GetAttribute('r'));
            if Ref <> '' then
            begin
              Letters := '';
              for K := 1 to Length(Ref) do
                if Ref[K] in ['A'..'Z'] then Letters := Letters + Ref[K];
              Col := 0;
              for K := 1 to Length(Letters) do
                Col := Col * 26 + Ord(Letters[K]) - Ord('A') + 1;
              Dec(Col);
            end;
            T := UTF8Encode(TDOMElement(C).GetAttribute('t'));
            Val := '';
            if T = 'inlineStr' then
            begin
              V := C.FindNode('is');
              if V <> nil then Val := TextOf(V);
            end
            else
            begin
              V := C.FindNode('v');
              if V <> nil then Val := UTF8Encode(V.TextContent);
              if (T = 's') and (StrToIntDef(Val, -1) >= 0) and (StrToInt(Val) < Shared.Count) then
                Val := Shared[StrToInt(Val)]
              else if T = 'b' then
                Val := IfThen(Val = '1', 'true', 'false');
            end;
            while Length(Cells) <= Col do
            begin
              SetLength(Cells, Length(Cells) + 1);
              Cells[High(Cells)] := '';
            end;
            Cells[Col] := Val;
            Inc(Col);
          end;
          C := C.NextSibling;
        end;
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Cells;
      end;
      Row_ := Row_.NextSibling;
    end;
  finally
    Book.Free; Rels.Free; Strings.Free; Data.Free;
    Shared.Free;
    U.Free;
    M.Free;
  end;
end;

{ ---- CSV ---- }

function ParseCsv(const Text: string; Separator: Char): TSheetRows;
var
  I, N: Integer;
  Field: string;
  Cells: TStringArray;
  InQuotes, Any: Boolean;
  First: string;

  procedure EndField;
  begin
    SetLength(Cells, Length(Cells) + 1);
    Cells[High(Cells)] := Field;
    Field := '';
  end;

  procedure EndRow;
  begin
    EndField;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Cells;
    Cells := nil;
  end;

begin
  Result := nil;
  I := 1;
  if Copy(Text, 1, 3) = #$EF#$BB#$BF then
    I := 4;
  if Separator = #0 then
  begin
    N := PosEx(#10, Text, I);
    if N = 0 then N := Length(Text) + 1;
    First := Copy(Text, I, N - I);
    if (Pos(#9, First) > 0) then Separator := #9
    else if WordCount(First, [';']) > WordCount(First, [',']) then Separator := ';'
    else Separator := ',';
  end;
  Field := '';
  Cells := nil;
  InQuotes := False;
  Any := False;
  while I <= Length(Text) do
  begin
    if InQuotes then
    begin
      if Text[I] = '"' then
      begin
        if (I < Length(Text)) and (Text[I + 1] = '"') then
        begin
          Field := Field + '"';
          Inc(I);
        end
        else
          InQuotes := False;
      end
      else
        Field := Field + Text[I];
    end
    else if Text[I] = '"' then
      InQuotes := True
    else if Text[I] = Separator then
      EndField
    else if Text[I] = #10 then
    begin
      EndRow;
      Any := False;
      Inc(I);
      Continue;
    end
    else if Text[I] <> #13 then
      Field := Field + Text[I];
    Any := True;
    Inc(I);
  end;
  if Any or (Field <> '') or (Length(Cells) > 0) then
    EndRow;
end;

function ReadCsv(const FileName: string; Separator: Char): TSheetRows;
var
  L: TStringStream;
begin
  if not FileExists(FileName) then
    raise ESheetError.CreateFmt('%s does not exist', [FileName]);
  L := TStringStream.Create('');
  try
    L.LoadFromFile(FileName);
    Result := ParseCsv(L.DataString, Separator);
  finally
    L.Free;
  end;
end;

function CsvText(const Rows: TSheetRows; Separator: Char): string;
var
  R: TStringArray;
  I: Integer;
  S, Line: string;
begin
  Result := '';
  for R in Rows do
  begin
    Line := '';
    for I := 0 to High(R) do
    begin
      S := R[I];
      if (Pos(Separator, S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) then
        S := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
      if I > 0 then
        Line := Line + Separator;
      Line := Line + S;
    end;
    Result := Result + Line + #13#10;
  end;
end;

procedure WriteCsv(const FileName: string; const Rows: TSheetRows; Separator: Char);
var
  F: TFileStream;
  S: string;
begin
  S := #$EF#$BB#$BF + CsvText(Rows, Separator);
  F := TFileStream.Create(FileName, fmCreate);
  try
    F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
end;

function ReadSpreadsheet(const FileName: string; Sheet: Integer): TSheetRows;
begin
  if SameText(ExtractFileExt(FileName), '.csv') or SameText(ExtractFileExt(FileName), '.txt') then
    Result := ReadCsv(FileName)
  else
    Result := ReadXlsx(FileName, Sheet);
end;

function RowsToJson(const Rows: TSheetRows): TJSONArray;
var
  I, J: Integer;
  O: TJSONObject;
  Name: string;
begin
  Result := TJSONArray.Create;
  if Length(Rows) = 0 then
    Exit;
  for I := 1 to High(Rows) do
  begin
    if Length(Rows[I]) = 0 then
      Continue;
    O := TJSONObject.Create;
    for J := 0 to High(Rows[0]) do
    begin
      Name := Rows[0][J];
      if Name = '' then
        Name := ColName(J);
      if O.IndexOfName(Name) >= 0 then
        Name := Name + '_' + IntToStr(J + 1);
      if J <= High(Rows[I]) then
        O.Add(Name, Rows[I][J])
      else
        O.Add(Name, '');
    end;
    Result.Add(O);
  end;
end;

end.
