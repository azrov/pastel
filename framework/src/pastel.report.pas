(* Pastel - reports: invoices, lists, letters as PDF (and HTML), written
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
  Part of the Pastel project, MIT License. *)
unit Pastel.Report;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Pdf;

type
  TReport = class;
  TReportEvent = procedure(Report: TReport) of object;

  TReport = class
  private
    FPdf: TPdfDocument;
    FHtml: TStringList;
    FMargin: Single;
    FY: Single;
    FFooter, FHeader, FLogo: string;
    FOnNewPage: TReportEvent;
    FTextSize: Single;
    FAccent: string;
    { the table being written }
    FInTable: Boolean;
    FHeads: TStringArray;
    FWidths: array of Single;
    FAligns: string;
    FRowCount: Integer;
    FStriped: Boolean;
    function Bottom: Single;
    procedure StartPage;
    procedure TableHeader;
    function ColumnAlign(I: Integer): TPdfAlign;
    function Esc(const S: string): string;
  public
    { Size: 'A4', 'A5', 'Letter', or '80 x 200' (millimetres) for a receipt. }
    constructor Create(const Size: string = 'A4'; Landscape: Boolean = False);
    destructor Destroy; override;

    { Makes room for H millimetres: a new page when they do not fit. }
    procedure NeedSpace(H: Single);
    procedure NewPage;
    { Space below the last thing. }
    procedure Space(H: Single = 4);

    { A big bold line. }
    procedure Title(const S: string);
    { A bold line, a little bigger than text. }
    procedure Heading(const S: string);
    { A paragraph; long lines wrap. }
    procedure Text(const S: string; Align: TPdfAlign = paLeft);
    { Smaller grey text. }
    procedure Note(const S: string);
    { Name, value, name, value...: two columns, for the details of an invoice. }
    procedure Fields(const NamesAndValues: array of string);
    { A thin line across the page. }
    procedure Rule;
    { A picture; Width 0: its own size (96 pixels per inch), at most the page's width. }
    procedure Image(const FileName: string; Width: Single = 0; Align: TPdfAlign = paLeft);

    { A table: the column titles, their widths (0: share what is left) and
      their alignment as letters ('LRR': left, right, right; C: centre).
      Rows follow with Row; on a new page the titles are repeated. }
    procedure Table(const Heads: array of string; const Widths: array of Single; const Aligns: string = '');
    procedure Row(const Cells: array of string; Bold: Boolean = False);
    procedure EndTable;
    { A line at the right: 'Total' and its amount (bold for the last one). }
    procedure Total(const Name, Value: string; Bold: Boolean = False);

    procedure SaveToFile(const FileName: string);
    procedure SaveToStream(Stream: TStream);
    { The report as PDF bytes (for a web answer or an e-mail). }
    function ToBytes: TBytes;
    { The same report as an HTML page. }
    function ToHtml: string;

    { The PDF, for drawing of your own. }
    property Pdf: TPdfDocument read FPdf;
    { Where the next thing goes, millimetres from the top of the page. }
    property Y: Single read FY write FY;
    property Margin: Single read FMargin write FMargin;
    { The width between the margins. }
    function ContentWidth: Single;
    { Text at the bottom of every page; {page} and {pages} become numbers. }
    property Footer: string read FFooter write FFooter;
    { Small text at the top of every page but the first. }
    property Header: string read FHeader write FHeader;
    { A picture at the top right of the first page (a logo). }
    property Logo: string read FLogo write FLogo;
    { The size of normal text in points (10 by default). }
    property TextSize: Single read FTextSize write FTextSize;
    { The color of titles and table heads. }
    property Accent: string read FAccent write FAccent;
    { Every other table row with a light background (default True). }
    property Striped: Boolean read FStriped write FStriped;
    { Called on every new page, after the header: draw what every page has. }
    property OnNewPage: TReportEvent read FOnNewPage write FOnNewPage;
  end;

implementation

uses
  Math, StrUtils;

function AlignName(A: TPdfAlign): string;
begin
  case A of
    paCenter: Result := 'center';
    paRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

constructor TReport.Create(const Size: string; Landscape: Boolean);
begin
  inherited Create;
  FPdf := TPdfDocument.Create(Size, Landscape);
  FHtml := TStringList.Create;
  FMargin := 18;
  if FPdf.PageWidth < 100 then
    FMargin := 4;            { a receipt }
  FTextSize := 10;
  FAccent := '#1F2937';
  FStriped := True;
  FY := -1;                  { no page yet }
end;

destructor TReport.Destroy;
begin
  FPdf.Free;
  FHtml.Free;
  inherited Destroy;
end;

function TReport.ContentWidth: Single;
begin
  Result := FPdf.PageWidth - 2 * FMargin;
end;

function TReport.Bottom: Single;
begin
  Result := FPdf.PageHeight - FMargin;
  if FFooter <> '' then
    Result := Result - 8;
end;

function TReport.Esc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

procedure TReport.StartPage;
var
  W, H: Integer;
  LW: Single;
begin
  FPdf.NewPage;
  FY := FMargin;
  if (FPdf.PageCount = 1) and (FLogo <> '') and FileExists(FLogo) then
  begin
    FPdf.ImageSize(FLogo, W, H);
    LW := Min(45, W * 25.4 / 96);
    if H * LW / W > 25 then
      LW := 25 * W / H;
    FPdf.Image(FMargin + ContentWidth - LW, FMargin, LW, 0, FLogo);
  end;
  if (FPdf.PageCount > 1) and (FHeader <> '') then
  begin
    FPdf.SetFont(FTextSize - 2);
    FPdf.TextColor := '#6B7280';
    FPdf.Text(FMargin, FMargin - 8, FHeader);
  end;
  if Assigned(FOnNewPage) then
    FOnNewPage(Self);
end;

procedure TReport.NewPage;
begin
  StartPage;
  if FInTable then
    TableHeader;
end;

procedure TReport.NeedSpace(H: Single);
begin
  if (FY < 0) or (FY + H > Bottom) then
    NewPage;
end;

procedure TReport.Space(H: Single);
begin
  if FY < 0 then
    StartPage;
  FY := FY + H;
  FHtml.Add(Format('<div style="height:%dmm"></div>', [Round(H)]));
end;

procedure TReport.Title(const S: string);
begin
  FPdf.SetFont(FTextSize + 8, True);
  NeedSpace(FPdf.LineHeight + 4);
  FPdf.TextColor := FAccent;
  FY := FY + FPdf.TextBox(FMargin, FY, ContentWidth - IfThen(FLogo <> '', 50, 0), S) + 4;
  FHtml.Add('<h1>' + Esc(S) + '</h1>');
end;

procedure TReport.Heading(const S: string);
begin
  FPdf.SetFont(FTextSize + 2, True);
  if FY > FMargin then
    FY := FY + 3;
  NeedSpace(FPdf.LineHeight * 2);
  FPdf.TextColor := FAccent;
  FY := FY + FPdf.TextBox(FMargin, FY, ContentWidth, S) + 1.5;
  FHtml.Add('<h2>' + Esc(S) + '</h2>');
end;

procedure TReport.Text(const S: string; Align: TPdfAlign);
var
  L: string;
  A: string;
begin
  FPdf.SetFont(FTextSize);
  FPdf.TextColor := '#111827';
  for L in FPdf.WrapText(S, ContentWidth) do
  begin
    NeedSpace(FPdf.LineHeight);
    FPdf.SetFont(FTextSize);
    FPdf.TextColor := '#111827';
    FPdf.TextAligned(FMargin, FY, ContentWidth, L, Align);
    FY := FY + FPdf.LineHeight;
  end;
  FY := FY + 2;
  case Align of
    paCenter: A := ' style="text-align:center"';
    paRight: A := ' style="text-align:right"';
  else
    A := '';
  end;
  FHtml.Add('<p' + A + '>' + StringReplace(Esc(S), #10, '<br>', [rfReplaceAll]) + '</p>');
end;

procedure TReport.Note(const S: string);
var
  L: string;
begin
  FPdf.SetFont(FTextSize - 1.5);
  for L in FPdf.WrapText(S, ContentWidth) do
  begin
    NeedSpace(FPdf.LineHeight);
    FPdf.SetFont(FTextSize - 1.5);
    FPdf.TextColor := '#6B7280';
    FPdf.Text(FMargin, FY, L);
    FY := FY + FPdf.LineHeight;
  end;
  FY := FY + 2;
  FHtml.Add('<p class="note">' + Esc(S) + '</p>');
end;

procedure TReport.Fields(const NamesAndValues: array of string);
var
  I: Integer;
  NameW, H: Single;
begin
  FPdf.SetFont(FTextSize, True);
  NameW := 0;
  I := 0;
  while I < High(NamesAndValues) do
  begin
    NameW := Max(NameW, FPdf.TextWidth(NamesAndValues[I]));
    Inc(I, 2);
  end;
  NameW := Min(NameW + 6, ContentWidth / 2);
  FHtml.Add('<table class="fields">');
  I := 0;
  while I < High(NamesAndValues) do
  begin
    FPdf.SetFont(FTextSize);
    H := FPdf.LineHeight * Length(FPdf.WrapText(NamesAndValues[I + 1], ContentWidth - NameW));
    NeedSpace(H);
    FPdf.SetFont(FTextSize);
    FPdf.TextColor := '#6B7280';
    FPdf.Text(FMargin, FY, NamesAndValues[I]);
    FPdf.TextColor := '#111827';
    FPdf.TextBox(FMargin + NameW, FY, ContentWidth - NameW, NamesAndValues[I + 1]);
    FY := FY + H + 0.8;
    FHtml.Add('<tr><th>' + Esc(NamesAndValues[I]) + '</th><td>' + Esc(NamesAndValues[I + 1]) + '</td></tr>');
    Inc(I, 2);
  end;
  FHtml.Add('</table>');
  FY := FY + 2;
end;

procedure TReport.Rule;
begin
  NeedSpace(4);
  FPdf.StrokeColor := '#D1D5DB';
  FPdf.LineWidth := 0.3;
  FPdf.Line(FMargin, FY + 1.5, FMargin + ContentWidth, FY + 1.5);
  FY := FY + 4;
  FHtml.Add('<hr>');
end;

procedure TReport.Image(const FileName: string; Width: Single; Align: TPdfAlign);
var
  W, H: Integer;
  IW, IH, X: Single;
  A: string;
begin
  if FY < 0 then
    StartPage;
  FPdf.ImageSize(FileName, W, H);
  IW := Width;
  if IW <= 0 then
    IW := W * 25.4 / 96;
  IW := Min(IW, ContentWidth);
  IH := IW * H / W;
  NeedSpace(IH);
  case Align of
    paCenter: X := FMargin + (ContentWidth - IW) / 2;
    paRight: X := FMargin + ContentWidth - IW;
  else
    X := FMargin;
  end;
  FPdf.Image(X, FY, IW, IH, FileName);
  FY := FY + IH + 3;
  case Align of
    paCenter: A := 'center';
    paRight: A := 'right';
  else
    A := 'left';
  end;
  FHtml.Add(Format('<p style="text-align:%s"><img src="%s" style="width:%dmm"></p>', [A, Esc(FileName), Round(IW)]));
end;

function TReport.ColumnAlign(I: Integer): TPdfAlign;
begin
  Result := paLeft;
  if I < Length(FAligns) then
    case UpCase(FAligns[I + 1]) of
      'R': Result := paRight;
      'C': Result := paCenter;
    end;
end;

procedure TReport.Table(const Heads: array of string; const Widths: array of Single; const Aligns: string);
var
  I, Free_: Integer;
  Used: Single;
  H: string;
begin
  SetLength(FHeads, Length(Heads));
  for I := 0 to High(Heads) do
    FHeads[I] := Heads[I];
  SetLength(FWidths, Length(Heads));
  Used := 0;
  Free_ := 0;
  for I := 0 to High(Heads) do
  begin
    if I <= High(Widths) then FWidths[I] := Widths[I] else FWidths[I] := 0;
    if FWidths[I] > 0 then Used := Used + FWidths[I] else Inc(Free_);
  end;
  for I := 0 to High(FWidths) do
    if FWidths[I] <= 0 then
      FWidths[I] := Max(10, (ContentWidth - Used) / Max(1, Free_));
  FAligns := Aligns;
  FRowCount := 0;
  FInTable := True;
  FPdf.SetFont(FTextSize, True);
  NeedSpace(FPdf.LineHeight * 3);
  TableHeader;
  H := '<table class="grid"><thead><tr>';
  for I := 0 to High(Heads) do
    H := H + Format('<th style="text-align:%s">%s</th>', [AlignName(ColumnAlign(I)), Esc(Heads[I])]);
  FHtml.Add(H + '</tr></thead><tbody>');
end;

procedure TReport.TableHeader;
var
  I: Integer;
  X, H: Single;
begin
  FPdf.SetFont(FTextSize - 0.5, True);
  H := FPdf.LineHeight + 3;
  FPdf.FillColor := FAccent;
  FPdf.Rect(FMargin, FY, ContentWidth, H, True, False);
  FPdf.TextColor := '#FFFFFF';
  X := FMargin;
  for I := 0 to High(FHeads) do
  begin
    FPdf.TextAligned(X + 2, FY + 1.5, FWidths[I] - 4, FHeads[I], ColumnAlign(I));
    X := X + FWidths[I];
  end;
  FY := FY + H;
end;

procedure TReport.Row(const Cells: array of string; Bold: Boolean);
var
  I, N: Integer;
  X, H: Single;
  Lines: array of TStringArray;
  R: string;
  L: Integer;
begin
  if not FInTable then
    raise EPdfError.Create('Row needs a Table first');
  FPdf.SetFont(FTextSize - 0.5, Bold);
  SetLength(Lines, Length(FHeads));
  N := 1;
  for I := 0 to High(FHeads) do
  begin
    if I <= High(Cells) then
      Lines[I] := FPdf.WrapText(Cells[I], FWidths[I] - 4)
    else
      Lines[I] := nil;
    N := Max(N, Length(Lines[I]));
  end;
  H := N * FPdf.LineHeight + 2.4;
  NeedSpace(H);
  FPdf.SetFont(FTextSize - 0.5, Bold);
  if FStriped and Odd(FRowCount) then
  begin
    FPdf.FillColor := '#F3F4F6';
    FPdf.Rect(FMargin, FY, ContentWidth, H, True, False);
  end;
  FPdf.TextColor := '#111827';
  X := FMargin;
  for I := 0 to High(FHeads) do
  begin
    for L := 0 to High(Lines[I]) do
      FPdf.TextAligned(X + 2, FY + 1.2 + L * FPdf.LineHeight, FWidths[I] - 4, Lines[I][L], ColumnAlign(I));
    X := X + FWidths[I];
  end;
  FPdf.StrokeColor := '#E5E7EB';
  FPdf.LineWidth := 0.2;
  FPdf.Line(FMargin, FY + H, FMargin + ContentWidth, FY + H);
  FY := FY + H;
  Inc(FRowCount);
  R := '<tr' + IfThen(Bold, ' class="bold"', '') + '>';
  for I := 0 to High(FHeads) do
    if I <= High(Cells) then
      R := R + Format('<td style="text-align:%s">%s</td>',
        [AlignName(ColumnAlign(I)), StringReplace(Esc(Cells[I]), #10, '<br>', [rfReplaceAll])])
    else
      R := R + '<td></td>';
  FHtml.Add(R + '</tr>');
end;

procedure TReport.EndTable;
begin
  if not FInTable then
    Exit;
  FInTable := False;
  FY := FY + 3;
  FHtml.Add('</tbody></table>');
end;

procedure TReport.Total(const Name, Value: string; Bold: Boolean);
var
  W: Single;
begin
  FPdf.SetFont(FTextSize + Ord(Bold), Bold);
  NeedSpace(FPdf.LineHeight + 1);
  FPdf.SetFont(FTextSize + Ord(Bold), Bold);
  W := Min(ContentWidth, 80);
  if Bold then
  begin
    FPdf.StrokeColor := FAccent;
    FPdf.LineWidth := 0.4;
    FPdf.Line(FMargin + ContentWidth - W, FY, FMargin + ContentWidth, FY);
    FY := FY + 1;
  end;
  FPdf.TextColor := IfThen(Bold, FAccent, '#374151');
  FPdf.Text(FMargin + ContentWidth - W, FY, Name);
  FPdf.TextAligned(FMargin + ContentWidth - W, FY, W - 2, Value, paRight);
  FY := FY + FPdf.LineHeight + 0.6;
  FHtml.Add(Format('<div class="total%s"><span>%s</span><span>%s</span></div>', [IfThen(Bold, ' bold', ''), Esc(Name), Esc(Value)]));
end;

procedure TReport.SaveToStream(Stream: TStream);
var
  I: Integer;
  S: string;
begin
  if FPdf.PageCount = 0 then
    StartPage;
  if FFooter <> '' then
    for I := 0 to FPdf.PageCount - 1 do
    begin
      FPdf.SetPage(I);
      S := StringReplace(FFooter, '{page}', IntToStr(I + 1), [rfReplaceAll]);
      S := StringReplace(S, '{pages}', IntToStr(FPdf.PageCount), [rfReplaceAll]);
      FPdf.SetFont(FTextSize - 2);
      FPdf.TextColor := '#6B7280';
      FPdf.TextAligned(FMargin, FPdf.PageHeight - FMargin - 4, ContentWidth, S, paCenter);
    end;
  FPdf.SaveToStream(Stream);
end;

procedure TReport.SaveToFile(const FileName: string);
var
  F: TFileStream;
  L: TStringList;
begin
  if SameText(ExtractFileExt(FileName), '.html') or SameText(ExtractFileExt(FileName), '.htm') then
  begin
    L := TStringList.Create;
    try
      L.Text := ToHtml;
      L.SaveToFile(FileName);
    finally
      L.Free;
    end;
    Exit;
  end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(F);
  finally
    F.Free;
  end;
end;

function TReport.ToBytes: TBytes;
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

function TReport.ToHtml: string;
begin
  Result := '<!DOCTYPE html>' + LineEnding + '<html><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>' + Esc(FPdf.Title) + '</title><style>' +
    'body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#111827;max-width:780px;margin:24px auto;padding:0 16px;font-size:15px}' +
    'h1,h2{color:' + FAccent + '}h1{font-size:26px}h2{font-size:18px;margin-top:22px}' +
    '.note{color:#6B7280;font-size:13px}hr{border:0;border-top:1px solid #D1D5DB}' +
    'table{border-collapse:collapse;width:100%;margin:8px 0 14px}' +
    '.fields{width:auto}.fields th{color:#6B7280;font-weight:normal;text-align:left;padding:2px 16px 2px 0}' +
    '.grid th{background:' + FAccent + ';color:#fff;padding:6px 8px}.grid td{padding:5px 8px;border-bottom:1px solid #E5E7EB}' +
    '.grid tbody tr:nth-child(even){background:#F3F4F6}.bold td{font-weight:bold}' +
    '.total{display:flex;justify-content:space-between;width:300px;margin-left:auto;padding:2px 0}' +
    '.total.bold{font-weight:bold;color:' + FAccent + ';border-top:2px solid ' + FAccent + ';font-size:17px}' +
    '@media print{body{margin:0}}</style></head><body>' + LineEnding + FHtml.Text + '</body></html>' + LineEnding;
end;

end.
