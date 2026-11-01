(* Pastel - PDF files: pages with text, lines, boxes and pictures.

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
  Part of the Pastel project, MIT License. *)
unit Pastel.Pdf;

{$mode objfpc}{$H+}
{$R-}{$Q-}     { binary formats: numbers wrap around on purpose (checksums) }

interface

uses
  Classes, SysUtils;

type
  EPdfError = class(Exception);

  TPdfAlign = (paLeft, paCenter, paRight);

  { A TrueType font: what PDF needs of it. Internal, used by TPdfDocument. }
  TPdfFont = class
  private
    FData: TBytes;
    FTables: TStringList;          { tag=offset,length }
    FUnitsPerEm, FAscent, FDescent, FCapHeight: Integer;
    FBBox: array[0..3] of Integer;
    FNumGlyphs, FNumHMetrics: Integer;
    FLongLoca: Boolean;
    FCmapOffset, FCmapFormat: Integer;
    FWidths: array of Word;
    FUsed: array of Boolean;       { glyphs used in the document }
    FCache: TStringList;           { code point -> glyph, for speed }
    FName: string;
    function U16(P: Integer): Word;
    function S16(P: Integer): SmallInt;
    function U32(P: Integer): Cardinal;
    function Table(const Tag: string; out Offset, Len: Integer): Boolean;
    function LookupCmap(CodePoint: Cardinal): Integer;
    function GlyphRange(G: Integer; out Start, Len: Integer): Boolean;
    procedure AddComponents(G: Integer);
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function GlyphOf(CodePoint: Cardinal): Integer;
    { Width of a glyph in 1/1000 of the font size. }
    function Advance(G: Integer): Single;
    { The font file with only the used glyphs (the others empty). }
    function Subset: TBytes;
    property UnitsPerEm: Integer read FUnitsPerEm;
    property Name: string read FName;
  end;

  TPdfDocument = class
  private
    FPageW, FPageH: Single;                 { points }
    FPages: TFPList;                        { TStringList each: content operators }
    FPageSizes: array of array[0..1] of Single;
    FPage: Integer;
    FFonts: array[0..1] of TPdfFont;        { regular, bold }
    FFontFiles: array[0..1] of string;
    FBold: Boolean;
    FSize: Single;
    FTextColor, FFillColor, FStrokeColor: string;
    FLineWidth: Single;
    FImages: TStringList;                   { file name -> TPdfImage }
    FTitle, FAuthor, FSubject: string;
    function Content: TStringList;
    function Font: TPdfFont;
    function Pt(Mm: Single): Single;
    function Mm(Pt_: Single): Single;
    function Num(V: Single): string;
    function ColorOps(const Color: string; Fill: Boolean): string;
    function Encode(const S: string): string;
    function ImageIndex(const FileName: string): Integer;
    procedure EnsureFonts;
  public
    { Size: 'A4' (default), 'A5', 'A3', 'Letter', 'Legal', or 'W x H' in
      millimetres ('80 x 200' for a receipt). }
    constructor Create(const Size: string = 'A4'; Landscape: Boolean = False);
    destructor Destroy; override;
    { Uses these .ttf files instead of the system's font (Bold may be ''). }
    procedure LoadFonts(const Regular: string; const Bold: string = '');
    { A new page (the first one is made by the first drawing); it is the current page now. }
    procedure NewPage;
    { Draws on another page (0 = the first): for page numbers at the end. }
    procedure SetPage(Index: Integer);
    function PageCount: Integer;
    property Page: Integer read FPage;
    { The page's size in millimetres. }
    function PageWidth: Single;
    function PageHeight: Single;

    { Size in points (11 is usual for text), and bold or not. }
    procedure SetFont(Size: Single; Bold: Boolean = False);
    property FontSize: Single read FSize;
    property Bold: Boolean read FBold;
    { The height of a line of text in millimetres. }
    function LineHeight: Single;
    function TextWidth(const S: string): Single;
    { Text with its top at Y. }
    procedure Text(X, Y: Single; const S: string);
    { Text in a box W wide: left, centred or right of it. }
    procedure TextAligned(X, Y, W: Single; const S: string; Align: TPdfAlign);
    { The lines of S that fit into Width (at words; line breaks in S stay). }
    function WrapText(const S: string; Width: Single): TStringArray;
    { Wrapped text; returns the height it took. }
    function TextBox(X, Y, W: Single; const S: string; Align: TPdfAlign = paLeft): Single;

    procedure Line(X1, Y1, X2, Y2: Single);
    procedure Rect(X, Y, W, H: Single; Fill: Boolean = False; Stroke: Boolean = True);
    { A PNG or JPEG picture. W or H 0: from the other one, keeping the shape. }
    procedure Image(X, Y, W, H: Single; const FileName: string);
    { The size of a picture in pixels. }
    procedure ImageSize(const FileName: string; out W, H: Integer);

    { '#RRGGBB' }
    property TextColor: string read FTextColor write FTextColor;
    property FillColor: string read FFillColor write FFillColor;
    property StrokeColor: string read FStrokeColor write FStrokeColor;
    { Width of lines in millimetres (0.2 by default). }
    property LineWidth: Single read FLineWidth write FLineWidth;

    property Title: string read FTitle write FTitle;
    property Author: string read FAuthor write FAuthor;
    property Subject: string read FSubject write FSubject;

    procedure SaveToStream(Stream: TStream);
    procedure SaveToFile(const FileName: string);
    { The file as bytes (for a web answer or an e-mail attachment). }
    function ToBytes: TBytes;
  end;

{ The .ttf files used when none are given: PASTEL_FONT / PASTEL_FONT_BOLD,
  assets/fonts/ next to the program, or the system's. }
procedure FindPdfFonts(out Regular, Bold: string);

implementation

uses
  Math, StrUtils, ZStream, FPImage, FPReadPNG, FPReadJPEG;

type
  TPdfImage = class
    Width, Height: Integer;
    Data: TBytes;          { compressed }
    Filter: string;        { DCTDecode or FlateDecode }
    ColorSpace: string;
    Alpha: TBytes;         { FlateDecode'd soft mask, or empty }
  end;

{ ---- helpers ---- }

function Deflate(const Data: TBytes): TBytes;
var
  Out_: TMemoryStream;
  Z: TCompressionStream;
begin
  Out_ := TMemoryStream.Create;
  try
    Z := TCompressionStream.Create(clDefault, Out_);
    try
      if Length(Data) > 0 then
        Z.WriteBuffer(Data[0], Length(Data));
    finally
      Z.Free;
    end;
    Result := nil;
    SetLength(Result, Out_.Size);
    if Out_.Size > 0 then
      Move(Out_.Memory^, Result[0], Out_.Size);
  finally
    Out_.Free;
  end;
end;

function StrBytes(const S: string): TBytes;
begin
  Result := nil;
  SetLength(Result, Length(S));
  if S <> '' then
    Move(S[1], Result[0], Length(S));
end;

{ UTF-8 -> code points }
function CodePoints(const S: string): specialize TArray<Cardinal>;
var
  I, N, Count: Integer;
  C: Cardinal;
  B: Byte;
begin
  Result := nil;
  SetLength(Result, Length(S));
  Count := 0;
  I := 1;
  while I <= Length(S) do
  begin
    B := Ord(S[I]);
    if B < $80 then begin C := B; N := 0; end
    else if B and $E0 = $C0 then begin C := B and $1F; N := 1; end
    else if B and $F0 = $E0 then begin C := B and $0F; N := 2; end
    else if B and $F8 = $F0 then begin C := B and $07; N := 3; end
    else begin C := $FFFD; N := 0; end;
    Inc(I);
    while (N > 0) and (I <= Length(S)) and (Ord(S[I]) and $C0 = $80) do
    begin
      C := (C shl 6) or (Ord(S[I]) and $3F);
      Inc(I);
      Dec(N);
    end;
    Result[Count] := C;
    Inc(Count);
  end;
  SetLength(Result, Count);
end;

function UTF16Hex(const S: string): string;
var
  U: UnicodeString;
  I: Integer;
begin
  U := UTF8Decode(S);
  Result := '<FEFF';
  for I := 1 to Length(U) do
    Result := Result + IntToHex(Ord(U[I]), 4);
  Result := Result + '>';
end;

procedure FindPdfFonts(out Regular, Bold: string);

  function First(const Files: array of string): string;
  var
    F: string;
  begin
    for F in Files do
      if (F <> '') and FileExists(F) then
        Exit(F);
    Result := '';
  end;

var
  Here: string;
  {$IFDEF WINDOWS}
  Dir: string;
  {$ENDIF}
begin
  Regular := GetEnvironmentVariable('PASTEL_FONT');
  Bold := GetEnvironmentVariable('PASTEL_FONT_BOLD');
  Here := ExtractFilePath(ParamStr(0));
  if Regular = '' then
    Regular := First([Here + 'assets/fonts/Regular.ttf', 'assets/fonts/Regular.ttf']);
  if Bold = '' then
    Bold := First([Here + 'assets/fonts/Bold.ttf', 'assets/fonts/Bold.ttf']);
  {$IF defined(WINDOWS)}
  Dir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) + 'Fonts\';
  if Regular = '' then
    Regular := First([Dir + 'arial.ttf', Dir + 'segoeui.ttf', Dir + 'tahoma.ttf']);
  if Bold = '' then
    Bold := First([Dir + 'arialbd.ttf', Dir + 'segoeuib.ttf', Dir + 'tahomabd.ttf']);
  {$ELSEIF defined(DARWIN)}
  if Regular = '' then
    Regular := First(['/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf']);
  if Bold = '' then
    Bold := First(['/System/Library/Fonts/Supplemental/Arial Bold.ttf', '/Library/Fonts/Arial Bold.ttf']);
  {$ELSE}
  if Regular = '' then
    Regular := First([
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/TTF/DejaVuSans.ttf',
      '/usr/share/fonts/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf',
      '/usr/share/fonts/truetype/crosextra/Carlito-Regular.ttf']);
  if Bold = '' then
    Bold := First([
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
      '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
      '/usr/share/fonts/noto/NotoSans-Bold.ttf',
      '/usr/share/fonts/truetype/ubuntu/Ubuntu-B.ttf',
      '/usr/share/fonts/truetype/crosextra/Carlito-Bold.ttf']);
  {$ENDIF}
  if Bold = '' then
    Bold := Regular;
end;

{ ---- TPdfFont ---- }

constructor TPdfFont.Create(const FileName: string);
var
  F: TFileStream;
  I, N, P, Off, Len, Sub, Best, PlatformId, EncodingId, Fmt, NameOff, Count, StrOff: Integer;
  Tag, S: string;
begin
  inherited Create;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(FData, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(FData[0], F.Size);
  finally
    F.Free;
  end;
  if (Length(FData) < 12) or not ((U32(0) = $00010000) or (U32(0) = $74727565)) then
    raise EPdfError.CreateFmt('%s is not a TrueType font (.ttf with outlines; .otf with CFF is not supported)', [FileName]);
  FTables := TStringList.Create;
  N := U16(4);
  for I := 0 to N - 1 do
  begin
    P := 12 + I * 16;
    Tag := Chr(FData[P]) + Chr(FData[P + 1]) + Chr(FData[P + 2]) + Chr(FData[P + 3]);
    FTables.Values[Tag] := IntToStr(U32(P + 8)) + ',' + IntToStr(U32(P + 12));
  end;
  if not Table('head', Off, Len) or not Table('glyf', Off, Len) then
    raise EPdfError.CreateFmt('%s has no TrueType outlines', [FileName]);
  Table('head', Off, Len);
  FUnitsPerEm := U16(Off + 18);
  FBBox[0] := S16(Off + 36); FBBox[1] := S16(Off + 38); FBBox[2] := S16(Off + 40); FBBox[3] := S16(Off + 42);
  FLongLoca := S16(Off + 50) = 1;
  Table('hhea', Off, Len);
  FAscent := S16(Off + 4);
  FDescent := S16(Off + 6);
  FNumHMetrics := U16(Off + 34);
  FCapHeight := FAscent;
  if Table('OS/2', Off, Len) and (U16(Off) >= 2) and (Len >= 90) then
    FCapHeight := S16(Off + 88);
  Table('maxp', Off, Len);
  FNumGlyphs := U16(Off + 4);
  SetLength(FWidths, FNumGlyphs);
  Table('hmtx', Off, Len);
  for I := 0 to FNumGlyphs - 1 do
    if I < FNumHMetrics then
      FWidths[I] := U16(Off + I * 4)
    else
      FWidths[I] := FWidths[FNumHMetrics - 1];
  SetLength(FUsed, FNumGlyphs);
  FUsed[0] := True;
  { cmap: a Unicode subtable, format 12 (all of Unicode) before format 4 }
  Table('cmap', Off, Len);
  Best := -1;
  FCmapFormat := 0;
  for I := 0 to U16(Off + 2) - 1 do
  begin
    PlatformId := U16(Off + 4 + I * 8);
    EncodingId := U16(Off + 6 + I * 8);
    Sub := Off + Integer(U32(Off + 8 + I * 8));
    Fmt := U16(Sub);
    if ((PlatformId = 3) and ((EncodingId = 1) or (EncodingId = 10))) or (PlatformId = 0) then
      if (Fmt = 12) or ((Fmt = 4) and (FCmapFormat <> 12)) then
      begin
        Best := Sub;
        FCmapFormat := Fmt;
      end;
  end;
  if Best < 0 then
    raise EPdfError.CreateFmt('%s has no Unicode character map', [FileName]);
  FCmapOffset := Best;
  FCache := TStringList.Create;
  FCache.Sorted := True;
  { the PostScript name, for the PDF }
  FName := '';
  if Table('name', Off, Len) then
  begin
    Count := U16(Off + 2);
    StrOff := Off + U16(Off + 4);
    for I := 0 to Count - 1 do
    begin
      P := Off + 6 + I * 12;
      if U16(P + 6) = 6 then
      begin
        NameOff := StrOff + U16(P + 10);
        S := '';
        for N := 0 to U16(P + 8) - 1 do
          if FData[NameOff + N] in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9'), Ord('-')] then
            S := S + Chr(FData[NameOff + N]);
        if S <> '' then
        begin
          FName := S;
          Break;
        end;
      end;
    end;
  end;
  if FName = '' then
    FName := 'Font';
end;

destructor TPdfFont.Destroy;
begin
  FTables.Free;
  FCache.Free;
  inherited Destroy;
end;

function TPdfFont.U16(P: Integer): Word;
begin
  Result := (FData[P] shl 8) or FData[P + 1];
end;

function TPdfFont.S16(P: Integer): SmallInt;
begin
  Result := SmallInt(U16(P));
end;

function TPdfFont.U32(P: Integer): Cardinal;
begin
  Result := (Cardinal(FData[P]) shl 24) or (FData[P + 1] shl 16) or (FData[P + 2] shl 8) or FData[P + 3];
end;

function TPdfFont.Table(const Tag: string; out Offset, Len: Integer): Boolean;
var
  V: string;
begin
  V := FTables.Values[Tag];
  Result := V <> '';
  Offset := 0;
  Len := 0;
  if Result then
  begin
    Offset := StrToInt(Copy(V, 1, Pos(',', V) - 1));
    Len := StrToInt(Copy(V, Pos(',', V) + 1, MaxInt));
  end;
end;

function TPdfFont.LookupCmap(CodePoint: Cardinal): Integer;
var
  P, SegX2, I, Lo, Hi, Mid: Integer;
  EndC, StartC, Delta, RangeOff, G: Integer;
  Groups: Cardinal;
begin
  Result := 0;
  P := FCmapOffset;
  if FCmapFormat = 12 then
  begin
    Groups := U32(P + 12);
    Lo := 0;
    Hi := Integer(Groups) - 1;
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      I := P + 16 + Mid * 12;
      if CodePoint < U32(I) then
        Hi := Mid - 1
      else if CodePoint > U32(I + 4) then
        Lo := Mid + 1
      else
        Exit(Integer(U32(I + 8) + (CodePoint - U32(I))));
    end;
    Exit;
  end;
  if CodePoint > $FFFF then
    Exit;
  SegX2 := U16(P + 6);
  for I := 0 to SegX2 div 2 - 1 do
  begin
    EndC := U16(P + 14 + I * 2);
    if CodePoint > Cardinal(EndC) then
      Continue;
    StartC := U16(P + 16 + SegX2 + I * 2);
    if CodePoint < Cardinal(StartC) then
      Exit;
    Delta := S16(P + 16 + 2 * SegX2 + I * 2);
    RangeOff := U16(P + 16 + 3 * SegX2 + I * 2);
    if RangeOff = 0 then
      Exit((Integer(CodePoint) + Delta) and $FFFF);
    G := U16(P + 16 + 3 * SegX2 + I * 2 + RangeOff + 2 * (Integer(CodePoint) - StartC));
    if G <> 0 then
      G := (G + Delta) and $FFFF;
    Exit(G);
  end;
end;

function TPdfFont.GlyphOf(CodePoint: Cardinal): Integer;
var
  I: Integer;
  Key: string;
begin
  Key := IntToHex(CodePoint, 6);
  I := FCache.IndexOf(Key);
  if I >= 0 then
    Exit(PtrInt(FCache.Objects[I]));
  Result := LookupCmap(CodePoint);
  if (Result < 0) or (Result >= FNumGlyphs) then
    Result := 0;
  FCache.AddObject(Key, TObject(PtrInt(Result)));
end;

function TPdfFont.Advance(G: Integer): Single;
begin
  Result := FWidths[G] * 1000 / FUnitsPerEm;
end;

function TPdfFont.GlyphRange(G: Integer; out Start, Len: Integer): Boolean;
var
  LocaOff, LocaLen, GlyfOff, GlyfLen, A, B: Integer;
begin
  Table('loca', LocaOff, LocaLen);
  Table('glyf', GlyfOff, GlyfLen);
  if FLongLoca then
  begin
    A := U32(LocaOff + G * 4);
    B := U32(LocaOff + G * 4 + 4);
  end
  else
  begin
    A := U16(LocaOff + G * 2) * 2;
    B := U16(LocaOff + G * 2 + 2) * 2;
  end;
  Start := GlyfOff + A;
  Len := B - A;
  Result := Len > 0;
end;

procedure TPdfFont.AddComponents(G: Integer);
var
  Start, Len, P, Flags, C: Integer;
begin
  if not GlyphRange(G, Start, Len) or (S16(Start) >= 0) then
    Exit;
  { a composite glyph: made of other glyphs, which are needed too }
  P := Start + 10;
  repeat
    Flags := U16(P);
    C := U16(P + 2);
    if (C < FNumGlyphs) and not FUsed[C] then
    begin
      FUsed[C] := True;
      AddComponents(C);
    end;
    Inc(P, 4);
    if Flags and 1 <> 0 then Inc(P, 4) else Inc(P, 2);
    if Flags and 8 <> 0 then Inc(P, 2)
    else if Flags and $40 <> 0 then Inc(P, 4)
    else if Flags and $80 <> 0 then Inc(P, 8);
  until Flags and $20 = 0;
end;

function TPdfFont.Subset: TBytes;
const
  { cmap is not needed: the PDF names glyphs by number (CIDToGIDMap /Identity) }
  Keep: array[0..8] of string = ('OS/2', 'cvt ', 'fpgm', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp');
  KeepMore: array[0..0] of string = ('prep');
var
  Tags: TStringList;
  Bodies: array of TBytes;
  Glyf, Loca: TMemoryStream;
  I, G, Start, Len, Off, L, N, P, Pos_, Pad: Integer;
  Tag: string;
  Sum: Cardinal;
  B: TBytes;
  Out_: TMemoryStream;
  Used: array of Boolean;

  procedure W16(S: TStream; V: Word);
  var
    X: array[0..1] of Byte;
  begin
    X[0] := V shr 8; X[1] := V and $FF;
    S.WriteBuffer(X, 2);
  end;

  procedure W32(S: TStream; V: Cardinal);
  var
    X: array[0..3] of Byte;
  begin
    X[0] := V shr 24; X[1] := (V shr 16) and $FF; X[2] := (V shr 8) and $FF; X[3] := V and $FF;
    S.WriteBuffer(X, 4);
  end;

  function CheckSum(const D: TBytes): Cardinal;
  var
    J, K: Integer;
    V: Cardinal;
  begin
    Result := 0;
    J := 0;
    while J < Length(D) do
    begin
      V := 0;
      for K := 0 to 3 do
      begin
        V := V shl 8;
        if J + K < Length(D) then
          V := V or D[J + K];
      end;
      Result := Result + V;
      Inc(J, 4);
    end;
  end;

begin
  Used := Copy(FUsed);
  for G := 0 to FNumGlyphs - 1 do
    if Used[G] then
      AddComponents(G);
  Used := Copy(FUsed);
  Glyf := TMemoryStream.Create;
  Loca := TMemoryStream.Create;
  Tags := TStringList.Create;
  Out_ := TMemoryStream.Create;
  try
    for G := 0 to FNumGlyphs - 1 do
    begin
      W32(Loca, Glyf.Size);
      if Used[G] and GlyphRange(G, Start, Len) then
      begin
        Glyf.WriteBuffer(FData[Start], Len);
        while Glyf.Size mod 4 <> 0 do
          Glyf.WriteByte(0);
      end;
    end;
    W32(Loca, Glyf.Size);
    for Tag in Keep do
      if Table(Tag, Off, L) then
        Tags.Add(Tag);
    for Tag in KeepMore do
      if Table(Tag, Off, L) then
        Tags.Add(Tag);
    Tags.Sort;
    SetLength(Bodies, Tags.Count);
    for I := 0 to Tags.Count - 1 do
    begin
      Tag := Tags[I];
      if Tag = 'glyf' then
      begin
        SetLength(B, Glyf.Size);
        Move(Glyf.Memory^, B[0], Glyf.Size);
      end
      else if Tag = 'loca' then
      begin
        SetLength(B, Loca.Size);
        Move(Loca.Memory^, B[0], Loca.Size);
      end
      else
      begin
        Table(Tag, Off, L);
        B := Copy(FData, Off, L);
        if Tag = 'head' then
        begin
          B[8] := 0; B[9] := 0; B[10] := 0; B[11] := 0;   { checkSumAdjustment }
          B[50] := 0; B[51] := 1;                          { long loca }
        end;
      end;
      Bodies[I] := B;
    end;
    { the table directory, then the tables, 4-byte aligned }
    N := Tags.Count;
    W32(Out_, $00010000);
    W16(Out_, N);
    P := 1;
    L := 0;
    while P * 2 <= N do
    begin
      P := P * 2;
      Inc(L);
    end;
    W16(Out_, P * 16);
    W16(Out_, L);
    W16(Out_, N * 16 - P * 16);
    Pos_ := 12 + N * 16;
    for I := 0 to N - 1 do
    begin
      Tag := Tags[I];
      Out_.WriteBuffer(Tag[1], 4);
      Sum := CheckSum(Bodies[I]);
      W32(Out_, Sum);
      W32(Out_, Pos_);
      W32(Out_, Length(Bodies[I]));
      Inc(Pos_, (Length(Bodies[I]) + 3) and not 3);
    end;
    for I := 0 to N - 1 do
    begin
      if Length(Bodies[I]) > 0 then
        Out_.WriteBuffer(Bodies[I][0], Length(Bodies[I]));
      Pad := ((Length(Bodies[I]) + 3) and not 3) - Length(Bodies[I]);
      while Pad > 0 do
      begin
        Out_.WriteByte(0);
        Dec(Pad);
      end;
    end;
    Result := nil;
    SetLength(Result, Out_.Size);
    Move(Out_.Memory^, Result[0], Out_.Size);
  finally
    Glyf.Free;
    Loca.Free;
    Tags.Free;
    Out_.Free;
  end;
end;

{ ---- TPdfDocument ---- }

constructor TPdfDocument.Create(const Size: string; Landscape: Boolean);
var
  S: string;
  W, H, T: Single;
  P: Integer;
begin
  inherited Create;
  S := LowerCase(StringReplace(Size, ' ', '', [rfReplaceAll]));
  case S of
    '', 'a4': begin W := 210; H := 297; end;
    'a5': begin W := 148; H := 210; end;
    'a3': begin W := 297; H := 420; end;
    'letter': begin W := 215.9; H := 279.4; end;
    'legal': begin W := 215.9; H := 355.6; end;
  else
    P := Pos('x', S);
    if (P = 0) or not TryStrToFloat(Copy(S, 1, P - 1), W, DefaultFormatSettings) or
       not TryStrToFloat(Copy(S, P + 1, MaxInt), H, DefaultFormatSettings) or (W <= 0) or (H <= 0) then
      raise EPdfError.CreateFmt('unknown page size "%s" (A4, A5, A3, Letter, Legal or "80 x 200" in millimetres)', [Size]);
  end;
  if Landscape then
  begin
    T := W; W := H; H := T;
  end;
  FPageW := W * 72 / 25.4;
  FPageH := H * 72 / 25.4;
  FPages := TFPList.Create;
  FPage := -1;
  FSize := 11;
  FTextColor := '#000000';
  FFillColor := '#EEEEEE';
  FStrokeColor := '#000000';
  FLineWidth := 0.2;
  FImages := TStringList.Create;
  FImages.OwnsObjects := True;
end;

destructor TPdfDocument.Destroy;
var
  I: Integer;
begin
  if FPages <> nil then
    for I := 0 to FPages.Count - 1 do
      TStringList(FPages[I]).Free;
  FPages.Free;
  if FFonts[1] <> FFonts[0] then
    FFonts[1].Free;
  FFonts[0].Free;
  FImages.Free;
  inherited Destroy;
end;

procedure TPdfDocument.LoadFonts(const Regular, Bold: string);
begin
  FFontFiles[0] := Regular;
  FFontFiles[1] := Bold;
  if Bold = '' then
    FFontFiles[1] := Regular;
end;

procedure TPdfDocument.EnsureFonts;
var
  R, B: string;
begin
  if FFonts[0] <> nil then
    Exit;
  if FFontFiles[0] = '' then
  begin
    FindPdfFonts(R, B);
    FFontFiles[0] := R;
    FFontFiles[1] := B;
  end;
  if FFontFiles[0] = '' then
    raise EPdfError.Create('no TrueType font was found for the PDF; put one into assets/fonts/Regular.ttf ' +
      '(and Bold.ttf), set PASTEL_FONT, or call LoadFonts');
  FFonts[0] := TPdfFont.Create(FFontFiles[0]);
  if (FFontFiles[1] = '') or (FFontFiles[1] = FFontFiles[0]) then
    FFonts[1] := FFonts[0]
  else
    FFonts[1] := TPdfFont.Create(FFontFiles[1]);
end;

function TPdfDocument.Font: TPdfFont;
begin
  EnsureFonts;
  if FBold then Result := FFonts[1] else Result := FFonts[0];
end;

procedure TPdfDocument.NewPage;
var
  L: TStringList;
begin
  L := TStringList.Create;
  FPages.Add(L);
  SetLength(FPageSizes, FPages.Count);
  FPageSizes[FPages.Count - 1][0] := FPageW;
  FPageSizes[FPages.Count - 1][1] := FPageH;
  FPage := FPages.Count - 1;
end;

procedure TPdfDocument.SetPage(Index: Integer);
begin
  if (Index < 0) or (Index >= FPages.Count) then
    raise EPdfError.CreateFmt('there is no page %d (%d pages)', [Index, FPages.Count]);
  FPage := Index;
end;

function TPdfDocument.PageCount: Integer;
begin
  Result := FPages.Count;
end;

function TPdfDocument.PageWidth: Single;
begin
  Result := Mm(FPageW);
end;

function TPdfDocument.PageHeight: Single;
begin
  Result := Mm(FPageH);
end;

function TPdfDocument.Content: TStringList;
begin
  if FPage < 0 then
    NewPage;
  Result := TStringList(FPages[FPage]);
end;

function TPdfDocument.Pt(Mm: Single): Single;
begin
  Result := Mm * 72 / 25.4;
end;

function TPdfDocument.Mm(Pt_: Single): Single;
begin
  Result := Pt_ * 25.4 / 72;
end;

function TPdfDocument.Num(V: Single): string;
begin
  Result := FormatFloat('0.###', V, DefaultFormatSettings);
  if Result = '-0' then
    Result := '0';
end;

function TPdfDocument.ColorOps(const Color: string; Fill: Boolean): string;
var
  C: string;
  R, G, B: Integer;
begin
  C := Color;
  if (C <> '') and (C[1] = '#') then
    Delete(C, 1, 1);
  if Length(C) = 3 then
    C := C[1] + C[1] + C[2] + C[2] + C[3] + C[3];
  if (Length(C) <> 6) or not TryStrToInt('$' + C, R) then
    raise EPdfError.CreateFmt('"%s" is not a color (#RRGGBB)', [Color]);
  R := StrToInt('$' + Copy(C, 1, 2));
  G := StrToInt('$' + Copy(C, 3, 2));
  B := StrToInt('$' + Copy(C, 5, 2));
  Result := Num(R / 255) + ' ' + Num(G / 255) + ' ' + Num(B / 255);
  if Fill then Result := Result + ' rg' else Result := Result + ' RG';
end;

procedure TPdfDocument.SetFont(Size: Single; Bold: Boolean);
begin
  FSize := Size;
  FBold := Bold;
end;

function TPdfDocument.LineHeight: Single;
begin
  Result := Mm(FSize * 1.25);
end;

function TPdfDocument.TextWidth(const S: string): Single;
var
  C: Cardinal;
  F: TPdfFont;
  W: Single;
begin
  F := Font;
  W := 0;
  for C in CodePoints(S) do
    W := W + F.Advance(F.GlyphOf(C));
  Result := Mm(W * FSize / 1000);
end;

function TPdfDocument.Encode(const S: string): string;
var
  C: Cardinal;
  F: TPdfFont;
  G: Integer;
begin
  F := Font;
  Result := '<';
  for C in CodePoints(S) do
  begin
    G := F.GlyphOf(C);
    F.FUsed[G] := True;
    Result := Result + IntToHex(G, 4);
  end;
  Result := Result + '>';
end;

procedure TPdfDocument.Text(X, Y: Single; const S: string);
var
  F: TPdfFont;
  Base: Single;
begin
  if S = '' then
    Exit;
  F := Font;
  Base := FPageH - Pt(Y) - FSize * F.FAscent / F.FUnitsPerEm;
  Content.Add(Format('BT %s /F%d %s Tf %s %s Td %s Tj ET',
    [ColorOps(FTextColor, True), Ord(FBold) + 1, Num(FSize), Num(Pt(X)), Num(Base), Encode(S)]));
end;

procedure TPdfDocument.TextAligned(X, Y, W: Single; const S: string; Align: TPdfAlign);
begin
  case Align of
    paCenter: Text(X + (W - TextWidth(S)) / 2, Y, S);
    paRight: Text(X + W - TextWidth(S), Y, S);
  else
    Text(X, Y, S);
  end;
end;

function TPdfDocument.WrapText(const S: string; Width: Single): TStringArray;
var
  Para, Word_, Line_: string;
  Words: TStringArray;
  Count: Integer;

  procedure Add(const L: string);
  begin
    if Count >= Length(Result) then
      SetLength(Result, Count * 2 + 4);
    Result[Count] := L;
    Inc(Count);
  end;

begin
  Result := nil;
  Count := 0;
  for Para in StringReplace(S, #13, '', [rfReplaceAll]).Split([#10]) do
  begin
    Line_ := '';
    Words := Para.Split([' ']);
    for Word_ in Words do
    begin
      if (Line_ <> '') and (TextWidth(Line_ + ' ' + Word_) > Width) then
      begin
        Add(Line_);
        Line_ := Word_;
      end
      else if Line_ = '' then
        Line_ := Word_
      else
        Line_ := Line_ + ' ' + Word_;
    end;
    Add(Line_);
  end;
  SetLength(Result, Count);
end;

function TPdfDocument.TextBox(X, Y, W: Single; const S: string; Align: TPdfAlign): Single;
var
  L: string;
  Lines: TStringArray;
  Y0: Single;
begin
  Y0 := Y;
  Lines := WrapText(S, W);
  for L in Lines do
  begin
    TextAligned(X, Y, W, L, Align);
    Y := Y + LineHeight;
  end;
  Result := Y - Y0;
end;

procedure TPdfDocument.Line(X1, Y1, X2, Y2: Single);
begin
  Content.Add(Format('%s %s w %s %s m %s %s l S',
    [ColorOps(FStrokeColor, False), Num(Pt(FLineWidth)), Num(Pt(X1)), Num(FPageH - Pt(Y1)), Num(Pt(X2)), Num(FPageH - Pt(Y2))]));
end;

procedure TPdfDocument.Rect(X, Y, W, H: Single; Fill, Stroke: Boolean);
var
  Op: string;
begin
  if not Fill and not Stroke then
    Exit;
  if Fill and Stroke then Op := 'B' else if Fill then Op := 'f' else Op := 'S';
  Content.Add(Format('%s %s %s w %s %s %s %s re %s',
    [ColorOps(FFillColor, True), ColorOps(FStrokeColor, False), Num(Pt(FLineWidth)),
     Num(Pt(X)), Num(FPageH - Pt(Y + H)), Num(Pt(W)), Num(Pt(H)), Op]));
end;

function TPdfDocument.ImageIndex(const FileName: string): Integer;
var
  Img: TPdfImage;
  F: TFileStream;
  Raw, RGB, A: TBytes;
  P, I, X, Y, N: Integer;
  HasAlpha: Boolean;
  Pic: TFPMemoryImage;
  C: TFPColor;
begin
  Result := FImages.IndexOf(FileName);
  if Result >= 0 then
    Exit;
  if not FileExists(FileName) then
    raise EPdfError.CreateFmt('picture not found: %s', [FileName]);
  Img := TPdfImage.Create;
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Raw, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Raw[0], F.Size);
  finally
    F.Free;
  end;
  if (Length(Raw) > 4) and (Raw[0] = $FF) and (Raw[1] = $D8) then
  begin
    { JPEG: put in as it is; the size and colors from its SOF marker }
    P := 2;
    while P + 9 < Length(Raw) do
    begin
      if Raw[P] <> $FF then
        Break;
      if Raw[P + 1] in [$C0, $C1, $C2] then
      begin
        Img.Height := (Raw[P + 5] shl 8) or Raw[P + 6];
        Img.Width := (Raw[P + 7] shl 8) or Raw[P + 8];
        case Raw[P + 9] of
          1: Img.ColorSpace := 'DeviceGray';
          4: Img.ColorSpace := 'DeviceCMYK';
        else
          Img.ColorSpace := 'DeviceRGB';
        end;
        Break;
      end;
      P := P + 2 + ((Raw[P + 2] shl 8) or Raw[P + 3]);
    end;
    if Img.Width = 0 then
    begin
      Img.Free;
      raise EPdfError.CreateFmt('%s: not a JPEG that can be read', [FileName]);
    end;
    Img.Data := Raw;
    Img.Filter := 'DCTDecode';
  end
  else
  begin
    Pic := TFPMemoryImage.Create(0, 0);
    try
      try
        Pic.LoadFromFile(FileName);
      except
        on E: Exception do
        begin
          Img.Free;
          raise EPdfError.CreateFmt('%s: %s', [FileName, E.Message]);
        end;
      end;
      Img.Width := Pic.Width;
      Img.Height := Pic.Height;
      SetLength(RGB, Img.Width * Img.Height * 3);
      SetLength(A, Img.Width * Img.Height);
      HasAlpha := False;
      N := 0;
      for Y := 0 to Img.Height - 1 do
        for X := 0 to Img.Width - 1 do
        begin
          C := Pic.Colors[X, Y];
          RGB[N * 3] := C.Red shr 8;
          RGB[N * 3 + 1] := C.Green shr 8;
          RGB[N * 3 + 2] := C.Blue shr 8;
          A[N] := C.Alpha shr 8;
          if A[N] <> 255 then
            HasAlpha := True;
          Inc(N);
        end;
      Img.Data := Deflate(RGB);
      Img.Filter := 'FlateDecode';
      Img.ColorSpace := 'DeviceRGB';
      if HasAlpha then
        Img.Alpha := Deflate(A);
    finally
      Pic.Free;
    end;
  end;
  I := FImages.AddObject(FileName, Img);
  Result := I;
end;

procedure TPdfDocument.ImageSize(const FileName: string; out W, H: Integer);
var
  Img: TPdfImage;
begin
  Img := TPdfImage(FImages.Objects[ImageIndex(FileName)]);
  W := Img.Width;
  H := Img.Height;
end;

procedure TPdfDocument.Image(X, Y, W, H: Single; const FileName: string);
var
  I: Integer;
  Img: TPdfImage;
begin
  I := ImageIndex(FileName);
  Img := TPdfImage(FImages.Objects[I]);
  if (W <= 0) and (H <= 0) then
    W := Img.Width * 25.4 / 96;           { 96 pixels per inch }
  if W <= 0 then
    W := H * Img.Width / Img.Height
  else if H <= 0 then
    H := W * Img.Height / Img.Width;
  Content.Add(Format('q %s 0 0 %s %s %s cm /Im%d Do Q',
    [Num(Pt(W)), Num(Pt(H)), Num(Pt(X)), Num(FPageH - Pt(Y + H)), I + 1]));
end;

procedure TPdfDocument.SaveToStream(Stream: TStream);
var
  Offsets: array of Int64;
  Body: TMemoryStream;
  NextObj, I, G, FontObjs, ImgObjs, PagesObj, InfoObj, CatalogObj, F, Last: Integer;
  PageObjs: array of Integer;
  S, W, Res: string;
  Data: TBytes;
  Font_: TPdfFont;
  Img: TPdfImage;
  ToUni: TStringList;
  Fonts: Integer;

  function NewObj: Integer;
  begin
    Inc(NextObj);
    if NextObj >= Length(Offsets) then
      SetLength(Offsets, NextObj * 2 + 8);
    Result := NextObj;
  end;

  procedure Put(const T: string);
  begin
    if T <> '' then
      Body.WriteBuffer(T[1], Length(T));
  end;

  procedure StartObj(N: Integer);
  begin
    Offsets[N] := Body.Position;
    Put(IntToStr(N) + ' 0 obj' + #10);
  end;

  procedure EndObj;
  begin
    Put(#10'endobj'#10);
  end;

  procedure PutStream(N: Integer; const Dict: string; const D: TBytes);
  begin
    StartObj(N);
    Put('<< ' + Dict + ' /Length ' + IntToStr(Length(D)) + ' >>'#10'stream'#10);
    if Length(D) > 0 then
      Body.WriteBuffer(D[0], Length(D));
    Put(#10'endstream');
    EndObj;
  end;

  procedure PutObj(N: Integer; const T: string);
  begin
    StartObj(N);
    Put(T);
    EndObj;
  end;

  function Date(D: TDateTime): string;
  begin
    Result := '(D:' + FormatDateTime('yyyymmddhhnnss', D) + ')';
  end;

begin
  if FPages.Count = 0 then
    NewPage;
  EnsureFonts;
  Body := TMemoryStream.Create;
  ToUni := TStringList.Create;
  try
    NextObj := 0;
    SetLength(Offsets, 16);
    Put('%PDF-1.4'#10'%'#$E2#$E3#$CF#$D3#10);
    CatalogObj := NewObj;
    PagesObj := NewObj;
    InfoObj := NewObj;
    { fonts: Type0 with a TrueType CID font, glyph ids as the codes }
    if FFonts[1] = FFonts[0] then Fonts := 1 else Fonts := 2;
    FontObjs := NextObj + 1;
    for F := 0 to Fonts - 1 do
    begin
      Font_ := FFonts[F];
      I := NewObj;      { Type0 }
      NewObj;           { CIDFont }
      NewObj;           { descriptor }
      NewObj;           { font file }
      NewObj;           { ToUnicode }
    end;
    ImgObjs := NextObj + 1;
    for I := 0 to FImages.Count - 1 do
    begin
      NewObj;
      if Length(TPdfImage(FImages.Objects[I]).Alpha) > 0 then
        NewObj;
    end;
    SetLength(PageObjs, FPages.Count);
    for I := 0 to FPages.Count - 1 do
    begin
      PageObjs[I] := NewObj;
      NewObj;           { its content }
    end;

    { the resources every page shares }
    Res := '/Font << /F1 ' + IntToStr(FontObjs) + ' 0 R /F2 ' + IntToStr(FontObjs + 5 * (Fonts - 1)) + ' 0 R >>';
    if FImages.Count > 0 then
    begin
      Res := Res + ' /XObject <<';
      G := ImgObjs;
      for I := 0 to FImages.Count - 1 do
      begin
        Res := Res + ' /Im' + IntToStr(I + 1) + ' ' + IntToStr(G) + ' 0 R';
        Inc(G);
        if Length(TPdfImage(FImages.Objects[I]).Alpha) > 0 then
          Inc(G);
      end;
      Res := Res + ' >>';
    end;

    PutObj(CatalogObj, '<< /Type /Catalog /Pages ' + IntToStr(PagesObj) + ' 0 R >>');
    S := '';
    for I := 0 to High(PageObjs) do
      S := S + IntToStr(PageObjs[I]) + ' 0 R ';
    PutObj(PagesObj, '<< /Type /Pages /Count ' + IntToStr(FPages.Count) + ' /Kids [' + Trim(S) + '] >>');
    S := '<< /Producer (Pastel) /Creator (Pastel) /CreationDate ' + Date(Now);
    if FTitle <> '' then S := S + ' /Title ' + UTF16Hex(FTitle);
    if FAuthor <> '' then S := S + ' /Author ' + UTF16Hex(FAuthor);
    if FSubject <> '' then S := S + ' /Subject ' + UTF16Hex(FSubject);
    PutObj(InfoObj, S + ' >>');

    { pages first: drawing them decides which glyphs are used }
    for I := 0 to FPages.Count - 1 do
    begin
      PutObj(PageObjs[I], Format('<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %s %s] /Resources << %s >> /Contents %d 0 R >>',
        [PagesObj, Num(FPageSizes[I][0]), Num(FPageSizes[I][1]), Res, PageObjs[I] + 1]));
      PutStream(PageObjs[I] + 1, '/Filter /FlateDecode', Deflate(StrBytes(TStringList(FPages[I]).Text)));
    end;

    for F := 0 to Fonts - 1 do
    begin
      Font_ := FFonts[F];
      G := FontObjs + F * 5;
      PutObj(G, Format('<< /Type /Font /Subtype /Type0 /BaseFont /PAST%s+%s /Encoding /Identity-H ' +
        '/DescendantFonts [%d 0 R] /ToUnicode %d 0 R >>', [Chr(Ord('A') + F), Font_.Name, G + 1, G + 4]));
      { widths of the used glyphs }
      W := '';
      for I := 0 to Font_.FNumGlyphs - 1 do
        if Font_.FUsed[I] then
          W := W + IntToStr(I) + ' [' + IntToStr(Round(Font_.Advance(I))) + '] ';
      PutObj(G + 1, Format('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /PAST%s+%s ' +
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> ' +
        '/FontDescriptor %d 0 R /DW 1000 /W [%s] /CIDToGIDMap /Identity >>',
        [Chr(Ord('A') + F), Font_.Name, G + 2, Trim(W)]));
      PutObj(G + 2, Format('<< /Type /FontDescriptor /FontName /PAST%s+%s /Flags 32 /FontBBox [%d %d %d %d] ' +
        '/ItalicAngle 0 /Ascent %d /Descent %d /CapHeight %d /StemV %d /FontFile2 %d 0 R >>',
        [Chr(Ord('A') + F), Font_.Name,
         Round(Font_.FBBox[0] * 1000 / Font_.FUnitsPerEm), Round(Font_.FBBox[1] * 1000 / Font_.FUnitsPerEm),
         Round(Font_.FBBox[2] * 1000 / Font_.FUnitsPerEm), Round(Font_.FBBox[3] * 1000 / Font_.FUnitsPerEm),
         Round(Font_.FAscent * 1000 / Font_.FUnitsPerEm), Round(Font_.FDescent * 1000 / Font_.FUnitsPerEm),
         Round(Font_.FCapHeight * 1000 / Font_.FUnitsPerEm), 80 + 60 * F, G + 3]));
      Data := Font_.Subset;
      PutStream(G + 3, '/Filter /FlateDecode /Length1 ' + IntToStr(Length(Data)), Deflate(Data));
      { ToUnicode: glyph -> letter, so text can be copied and searched }
      ToUni.Clear;
      for I := 0 to Font_.FCache.Count - 1 do
      begin
        Last := PtrInt(Font_.FCache.Objects[I]);
        if (Last > 0) and Font_.FUsed[Last] and (StrToInt('$' + Font_.FCache[I]) <= $FFFF) then
          ToUni.Add(Format('<%s> <%s>', [IntToHex(Last, 4), IntToHex(StrToInt('$' + Font_.FCache[I]), 4)]));
      end;
      S := '/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) ' +
        '/Ordering (UCS) /Supplement 0 >> def /CMapName /Adobe-Identity-UCS def /CMapType 2 def ' +
        '1 begincodespacerange <0000> <FFFF> endcodespacerange'#10;
      I := 0;
      while I < ToUni.Count do
      begin
        S := S + IntToStr(Min(100, ToUni.Count - I)) + ' beginbfchar'#10;
        for G := I to Min(I + 99, ToUni.Count - 1) do
          S := S + ToUni[G] + #10;
        S := S + 'endbfchar'#10;
        Inc(I, 100);
      end;
      S := S + 'endcmap CMapName currentdict /CMap defineresource pop end end';
      PutStream(FontObjs + F * 5 + 4, '/Filter /FlateDecode', Deflate(StrBytes(S)));
    end;
    if Fonts = 1 then
      ; { F2 points at F1 }

    G := ImgObjs;
    for I := 0 to FImages.Count - 1 do
    begin
      Img := TPdfImage(FImages.Objects[I]);
      S := Format('/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /%s /BitsPerComponent 8 /Filter /%s',
        [Img.Width, Img.Height, Img.ColorSpace, Img.Filter]);
      if Length(Img.Alpha) > 0 then
        S := S + ' /SMask ' + IntToStr(G + 1) + ' 0 R';
      PutStream(G, S, Img.Data);
      if Length(Img.Alpha) > 0 then
      begin
        PutStream(G + 1, Format('/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray ' +
          '/BitsPerComponent 8 /Filter /FlateDecode', [Img.Width, Img.Height]), Img.Alpha);
        Inc(G);
      end;
      Inc(G);
    end;

    { the cross-reference table }
    I := Body.Position;
    Put('xref'#10'0 ' + IntToStr(NextObj + 1) + #10'0000000000 65535 f '#10);
    for G := 1 to NextObj do
      Put(Format('%.10d 00000 n '#10, [Offsets[G]]));
    Put(Format('trailer'#10'<< /Size %d /Root %d 0 R /Info %d 0 R >>'#10'startxref'#10'%d'#10'%%%%EOF'#10,
      [NextObj + 1, CatalogObj, InfoObj, I]));
    Body.Position := 0;
    Stream.CopyFrom(Body, Body.Size);
  finally
    Body.Free;
    ToUni.Free;
  end;
end;

procedure TPdfDocument.SaveToFile(const FileName: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmCreate);
  try
    SaveToStream(F);
  finally
    F.Free;
  end;
end;

function TPdfDocument.ToBytes: TBytes;
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

end.
