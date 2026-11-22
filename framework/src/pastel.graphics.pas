{ Pastel - software 2D drawing: colors, an anti-aliased canvas and fonts.

  Everything is drawn by Pastel itself into a 32-bit pixel buffer, so it
  looks the same on every platform. A GPU backend (e.g. Skia) can later
  implement the same drawing calls.
  Part of the Pastel project, MIT License. }
unit Pastel.Graphics;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{ the drawing loops are optimized in debug builds too: a debug app should
  scroll as smoothly as the release one }
{$OPTIMIZATION ON}
{$INLINE ON}

interface

uses
  Classes, SysUtils, Pastel.FreeType, Pastel.TrueType, Pastel.Env;

type
  { $AARRGGBB. A distinct type so .pform files can use '#RRGGBB' for it. }
  TColor32 = type Cardinal;

  TRectI = record
    X, Y, W, H: Integer;
    function Contains(PX, PY: Integer): Boolean;
    function Intersect(const R: TRectI): TRectI;
    { The smallest rectangle around both (an empty one is ignored). }
    function Union(const R: TRectI): TRectI;
    function Inflate(D: Integer): TRectI;
  end;

  { Internal: a glyph of the font cache. }
  PGlyph = ^TGlyph;
  { Internal: a rendered glyph. }
  TGlyph = record
    Index: FT_UInt;
    Width, Height, Left, Top, Advance: Integer;
    Bits: array of Byte;
  end;

  { Internal: glyph cache, 256-entry pages allocated when first used. }
  TGlyphPage = array[0..255] of PGlyph;
  { Internal: see TGlyphPage. }
  PGlyphPage = ^TGlyphPage;

  TPastelFont = class
  private
    FFace: PFT_Face;
    FTT: TTrueTypeFont;          { the font without FreeType (not owned) }
    FTTScale: Double;
    FEmbolden: Boolean;
    FSize: Integer;
    FBold: Boolean;
    FAscent, FDescent, FLineHeight: Integer;
    FHasKerning: Boolean;
    FPages: array[0..$10FF] of PGlyphPage;
    function Kerning(Left, Right: FT_UInt): Integer;
  public
    constructor Create(const FileName: string; ASize: Integer; AEmbolden: Boolean = False);
    destructor Destroy; override;
    function Glyph(CodePoint: Cardinal): PGlyph;
    function TextWidth(const S: string): Integer;
    { Byte index in S whose left edge is closest to pixel offset X. }
    function HitTest(const S: string; X: Integer): Integer;
    property Size: Integer read FSize;
    property Bold: Boolean read FBold;
    property Ascent: Integer read FAscent;
    property Descent: Integer read FDescent;
    property LineHeight: Integer read FLineHeight;
  end;

  { A picture in memory: $AARRGGBB pixels, from PNG, JPEG or BMP files. }
  TBitmap32 = class
  private
    FWidth, FHeight: Integer;
  public
    Pixels: array of Cardinal;
    procedure SetSize(AWidth, AHeight: Integer);
    procedure LoadFromFile(const FileName: string);
    procedure LoadFromStream(Stream: TStream);
    function Empty: Boolean;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

  TCanvas32 = class
  private
    FPixels: array of Cardinal;
    FWidth, FHeight: Integer;         { in pixels }
    FLogW, FLogH: Integer;            { in layout units }
    FScale: Single;
    FClip: TRectI;
    FClipStack: array of TRectI;
    procedure Blend(Index: Integer; C: TColor32; Coverage: Integer); inline;
    function Sc: Single; inline;
    function ToPixels(const R: TRectI): TRectI;
    procedure FillRectRaw(X, Y, W, H: Integer; C: TColor32);
    procedure FillRoundRectRaw(X, Y, W, H: Integer; Radius: Single; C: TColor32);
    procedure StrokeRoundRectRaw(X, Y, W, H: Integer; Radius, Thickness: Single; C: TColor32);
    procedure DrawTextRaw(Font: TPastelFont; X, Y: Integer; const S: string; C: TColor32);
    procedure DrawLineRaw(X1, Y1, X2, Y2, Thickness: Single; C: TColor32);
    procedure FillCircleRaw(CX, CY, Radius: Single; C: TColor32);
    procedure DrawBitmapRaw(B: TBitmap32; X, Y, W, H: Integer; Smooth: Boolean; Opacity: Byte);
    procedure SetScale(AValue: Single);
  public
    { Width and height in layout units; with Scale 2 the pixels are twice as many. }
    procedure SetSize(AWidth, AHeight: Integer);
    procedure Clear(C: TColor32);
    procedure PushClip(const R: TRectI);
    procedure PopClip;
    procedure FillRect(X, Y, W, H: Integer; C: TColor32);
    procedure FillRoundRect(X, Y, W, H: Integer; Radius: Single; C: TColor32);
    procedure StrokeRoundRect(X, Y, W, H: Integer; Radius, Thickness: Single; C: TColor32);
    { Y is the top of the text line; the baseline is Y + Font.Ascent. }
    procedure DrawText(Font: TPastelFont; X, Y: Integer; const S: string; C: TColor32);
    { An anti-aliased line with round ends. }
    procedure DrawLine(X1, Y1, X2, Y2, Thickness: Single; C: TColor32);
    procedure FillCircle(CX, CY, Radius: Single; C: TColor32);
    { A slice of a circle (a ring when InnerRadius > 0): from Start, Sweep long
      (radians; 0 is up, clockwise), for pie and donut charts. }
    procedure FillPie(CX, CY, Radius, InnerRadius, Start, Sweep: Single; C: TColor32);
    { A picture scaled into the rectangle (bilinear when Smooth), with its transparency. }
    procedure DrawBitmap(B: TBitmap32; X, Y, W, H: Integer; Smooth: Boolean = True; Opacity: Byte = 255);
    function GetPixel(X, Y: Integer): TColor32;
    procedure SaveToPNG(const FileName: string);
    { A rectangle in layout units, in pixels. }
    function PixelRect(const R: TRectI): TRectI;
    function Data: Pointer;
    property Width: Integer read FLogW;
    property Height: Integer read FLogH;
    { The size in pixels (Width * Scale). }
    property PixelWidth: Integer read FWidth;
    property PixelHeight: Integer read FHeight;
    { Pixels per layout unit: 2 on a "retina" or 200% screen. Text is drawn
      with a font of the scaled size, so it stays sharp. }
    property Scale: Single read FScale write SetScale;
  end;

  EPastelGraphics = class(Exception);

function RGB(R, G, B: Byte): TColor32; inline;
function RGBA(R, G, B, A: Byte): TColor32; inline;
function WithAlpha(C: TColor32; A: Byte): TColor32; inline;
function Mix(A, B: TColor32; T: Single): TColor32;
{ Parses '#RGB', '#RRGGBB' or '#AARRGGBB'. }
function TryParseColor(const S: string; out C: TColor32): Boolean;
function RectI(X, Y, W, H: Integer): TRectI; inline;

{ UTF-8 helpers. NextCodePoint reads one character at byte index I (1-based)
  and moves I past it. }
function NextCodePoint(const S: string; var I: Integer): Cardinal;
function PrevCharStart(const S: string; I: Integer): Integer;
{ S cut to fit Width (pixels of Font), with '…'; one line (a line break ends
  it). Quick for long texts: only what can fit is measured, the cut found by halving. }
function FitText(Font: TPastelFont; const S: string; Width: Integer): string;

{ Fonts are shared and cached by size and weight. }
function GetFont(Size: Integer; Bold: Boolean = False): TPastelFont;

var
  { Every text is drawn this much larger: the size of text chosen in a phone's
    settings (Pastel.App sets it, at most 1.3 so forms keep their shape). }
  TextScale: Single = 1;

{ Use these .ttf files instead of the system font (after InitFonts). }
procedure SetFontFiles(const Regular, Bold: string);
{ Internal: initializes FreeType and finds a system font (Pastel.App does it). Returns '' or an error. }
function InitFonts: string;
{ Internal: frees the fonts at the end. }
procedure DoneFonts;
{ True when text is drawn by Pastel.TrueType instead of FreeType (always on
  Android; on a desktop without the FreeType library, or with PASTEL_FONT_ENGINE=pascal). }
function PascalFonts: Boolean;

implementation

uses
  Math, FPImage, FPReadPNG, FPReadJPEG, FPReadBMP;

var
  FTLib: PFT_Library = nil;
  RegularFontFile, BoldFontFile: string;
  FontCache: TStringList = nil;
  UsePascalFonts: Boolean = False;
  FontFiles: TStringList = nil;     { file name -> TTrueTypeFont, read once }

function PascalFonts: Boolean;
begin
  Result := UsePascalFonts;
end;

function LoadedFontFile(const FileName: string): TTrueTypeFont;
var
  I: Integer;
begin
  if FontFiles = nil then
  begin
    FontFiles := TStringList.Create;
    FontFiles.Sorted := True;
    FontFiles.OwnsObjects := True;
  end;
  I := FontFiles.IndexOf(FileName);
  if I >= 0 then
    Exit(TTrueTypeFont(FontFiles.Objects[I]));
  try
    Result := TTrueTypeFont.Create(FileName);
  except
    on E: Exception do
      raise EPastelGraphics.Create('cannot open font ' + FileName + ': ' + E.Message);
  end;
  FontFiles.AddObject(FileName, Result);
end;

{ ---- colors ---- }

function RGB(R, G, B: Byte): TColor32;
begin
  Result := TColor32($FF000000 or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or B);
end;

function RGBA(R, G, B, A: Byte): TColor32;
begin
  Result := TColor32((Cardinal(A) shl 24) or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or B);
end;

function WithAlpha(C: TColor32; A: Byte): TColor32;
begin
  Result := TColor32((Cardinal(C) and $00FFFFFF) or (Cardinal(A) shl 24));
end;

function Mix(A, B: TColor32; T: Single): TColor32;

  function Ch(Shift: Integer): Cardinal;
  var
    CA, CB: Integer;
  begin
    CA := (Cardinal(A) shr Shift) and $FF;
    CB := (Cardinal(B) shr Shift) and $FF;
    Result := Cardinal(EnsureRange(Round(CA + (CB - CA) * T), 0, 255)) shl Shift;
  end;

begin
  Result := TColor32(Ch(24) or Ch(16) or Ch(8) or Ch(0));
end;

function TryParseColor(const S: string; out C: TColor32): Boolean;
var
  H: string;
  V: LongInt;
begin
  Result := False;
  if (Length(S) < 2) or (S[1] <> '#') then
    Exit;
  H := Copy(S, 2, MaxInt);
  if Length(H) = 3 then
    H := H[1] + H[1] + H[2] + H[2] + H[3] + H[3];
  if Length(H) = 6 then
    H := 'FF' + H;
  if Length(H) <> 8 then
    Exit;
  if not TryStrToInt('$' + H, V) then
    Exit;
  C := TColor32(Cardinal(V));
  Result := True;
end;

function RectI(X, Y, W, H: Integer): TRectI;
begin
  Result.X := X;
  Result.Y := Y;
  Result.W := W;
  Result.H := H;
end;

function TRectI.Contains(PX, PY: Integer): Boolean;
begin
  Result := (PX >= X) and (PY >= Y) and (PX < X + W) and (PY < Y + H);
end;

function TRectI.Intersect(const R: TRectI): TRectI;
var
  X2, Y2: Integer;
begin
  Result.X := Max(X, R.X);
  Result.Y := Max(Y, R.Y);
  X2 := Min(X + W, R.X + R.W);
  Y2 := Min(Y + H, R.Y + R.H);
  Result.W := Max(0, X2 - Result.X);
  Result.H := Max(0, Y2 - Result.Y);
end;

function TRectI.Union(const R: TRectI): TRectI;
var
  X2, Y2: Integer;
begin
  if (R.W <= 0) or (R.H <= 0) then
    Exit(Self);
  if (W <= 0) or (H <= 0) then
    Exit(R);
  Result.X := Min(X, R.X);
  Result.Y := Min(Y, R.Y);
  X2 := Max(X + W, R.X + R.W);
  Y2 := Max(Y + H, R.Y + R.H);
  Result.W := X2 - Result.X;
  Result.H := Y2 - Result.Y;
end;

function TRectI.Inflate(D: Integer): TRectI;
begin
  Result.X := X - D;
  Result.Y := Y - D;
  Result.W := W + 2 * D;
  Result.H := H + 2 * D;
end;

{ ---- UTF-8 ---- }

function NextCodePoint(const S: string; var I: Integer): Cardinal;
var
  B: Byte;
  N, K: Integer;
begin
  B := Ord(S[I]);
  if B < $80 then
  begin
    Inc(I);
    Exit(B);
  end;
  if (B and $E0) = $C0 then begin Result := B and $1F; N := 1; end
  else if (B and $F0) = $E0 then begin Result := B and $0F; N := 2; end
  else if (B and $F8) = $F0 then begin Result := B and $07; N := 3; end
  else
  begin
    Inc(I);
    Exit($FFFD);
  end;
  Inc(I);
  for K := 1 to N do
  begin
    if (I > Length(S)) or ((Ord(S[I]) and $C0) <> $80) then
      Exit($FFFD);
    Result := (Result shl 6) or (Ord(S[I]) and $3F);
    Inc(I);
  end;
end;

function PrevCharStart(const S: string; I: Integer): Integer;
begin
  Result := I - 1;
  while (Result > 1) and ((Ord(S[Result]) and $C0) = $80) do
    Dec(Result);
  if Result < 1 then
    Result := 1;
end;

{ ---- fonts ---- }

constructor TPastelFont.Create(const FileName: string; ASize: Integer; AEmbolden: Boolean);
begin
  inherited Create;
  FSize := ASize;
  if UsePascalFonts then
  begin
    FTT := LoadedFontFile(FileName);
    FTTScale := ASize / FTT.UnitsPerEm;
    FEmbolden := AEmbolden;
    { rounded like FreeType does }
    FAscent := Ceil(FTT.Ascender * FTTScale);
    FDescent := Ceil(-FTT.Descender * FTTScale);
    FLineHeight := Max(Round((FTT.Ascender - FTT.Descender + FTT.LineGap) * FTTScale), FAscent + FDescent);
    FHasKerning := FTT.HasKerning;
    Exit;
  end;
  if FT_New_Face(FTLib, PChar(FileName), 0, FFace) <> 0 then
    raise EPastelGraphics.Create('cannot open font ' + FileName);
  FT_Set_Pixel_Sizes(FFace, 0, ASize);
  FAscent := (FFace^.size^.metrics.ascender + 63) div 64;
  FDescent := -(FFace^.size^.metrics.descender div 64);
  FLineHeight := Max((FFace^.size^.metrics.height + 63) div 64, FAscent + FDescent);
  FHasKerning := (FFace^.face_flags and FT_FACE_FLAG_KERNING) <> 0;
end;

destructor TPastelFont.Destroy;
var
  P, I: Integer;
begin
  for P := Low(FPages) to High(FPages) do
    if FPages[P] <> nil then
    begin
      for I := 0 to 255 do
        if FPages[P]^[I] <> nil then
          Dispose(FPages[P]^[I]);
      Dispose(FPages[P]);
    end;
  if FFace <> nil then
    FT_Done_Face(FFace);
  inherited Destroy;
end;

function TPastelFont.Glyph(CodePoint: Cardinal): PGlyph;
var
  TT: TTrueTypeBitmap;
  Slot: PFT_GlyphSlot;
  Row: Integer;
  Src: PByte;
begin
  if CodePoint > $10FFFF then
    CodePoint := $FFFD;
  if FPages[CodePoint shr 8] = nil then
  begin
    New(FPages[CodePoint shr 8]);
    FillChar(FPages[CodePoint shr 8]^, SizeOf(TGlyphPage), 0);
  end;
  Result := FPages[CodePoint shr 8]^[CodePoint and $FF];
  if Result <> nil then
    Exit;
  New(Result);
  if FTT <> nil then
  begin
    Result^.Index := FTT.GlyphIndex(CodePoint);
    FTT.Render(Result^.Index, FTTScale, FEmbolden, TT);
    Result^.Width := TT.Width;
    Result^.Height := TT.Height;
    Result^.Left := TT.Left;
    Result^.Top := TT.Top;
    Result^.Advance := TT.Advance;
    Result^.Bits := TT.Bits;
    FPages[CodePoint shr 8]^[CodePoint and $FF] := Result;
    Exit;
  end;
  Result^.Index := FT_Get_Char_Index(FFace, CodePoint);
  Result^.Width := 0;
  Result^.Height := 0;
  Result^.Left := 0;
  Result^.Top := 0;
  Result^.Advance := FSize div 3;
  if FT_Load_Glyph(FFace, Result^.Index, FT_LOAD_RENDER or FT_LOAD_TARGET_LIGHT) = 0 then
  begin
    Slot := FFace^.glyph;
    Result^.Width := Slot^.bitmap.width;
    Result^.Height := Slot^.bitmap.rows;
    Result^.Left := Slot^.bitmap_left;
    Result^.Top := Slot^.bitmap_top;
    Result^.Advance := (Slot^.advance.x + 32) div 64;
    SetLength(Result^.Bits, Result^.Width * Result^.Height);
    for Row := 0 to Result^.Height - 1 do
    begin
      Src := Slot^.bitmap.buffer + Row * Slot^.bitmap.pitch;
      if Result^.Width > 0 then
        Move(Src^, Result^.Bits[Row * Result^.Width], Result^.Width);
    end;
  end;
  FPages[CodePoint shr 8]^[CodePoint and $FF] := Result;
end;

function TPastelFont.Kerning(Left, Right: FT_UInt): Integer;
var
  V: FT_Vector;
begin
  Result := 0;
  if (FTT <> nil) and FHasKerning and (Left <> 0) and (Right <> 0) then
    Exit(Round(FTT.Kerning(Left, Right) * FTTScale));
  if FHasKerning and (Left <> 0) and (Right <> 0) and
     (FT_Get_Kerning(FFace, Left, Right, FT_KERNING_DEFAULT, V) = 0) then
    Result := V.x div 64;
end;

function TPastelFont.TextWidth(const S: string): Integer;
var
  I: Integer;
  G: PGlyph;
  Prev: FT_UInt;
begin
  Result := 0;
  Prev := 0;
  I := 1;
  while I <= Length(S) do
  begin
    G := Glyph(NextCodePoint(S, I));
    Inc(Result, Kerning(Prev, G^.Index) + G^.Advance);
    Prev := G^.Index;
  end;
end;

function TPastelFont.HitTest(const S: string; X: Integer): Integer;
var
  I, Start, Pos, Step: Integer;
  G: PGlyph;
  Prev: FT_UInt;
begin
  Pos := 0;
  Prev := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Start := I;
    G := Glyph(NextCodePoint(S, I));
    Step := Kerning(Prev, G^.Index) + G^.Advance;
    if X < Pos + Step div 2 then
      Exit(Start);
    Inc(Pos, Step);
    Prev := G^.Index;
  end;
  Result := Length(S) + 1;
end;

function FirstExisting(const Candidates: array of string): string;
var
  C: string;
begin
  for C in Candidates do
    if (C <> '') and FileExists(C) then
      Exit(C);
  Result := '';
end;

procedure FindSystemFonts;
{$IFDEF WINDOWS}
var
  Dir: string;
  SR: TSearchRec;
{$ENDIF}
begin
  RegularFontFile := GetEnv('PASTEL_FONT');
  BoldFontFile := GetEnv('PASTEL_FONT_BOLD');
  {$IF defined(WINDOWS)}
  Dir := IncludeTrailingPathDelimiter(GetEnv('WINDIR')) + 'Fonts\';
  if RegularFontFile = '' then
    RegularFontFile := FirstExisting([Dir + 'segoeui.ttf', Dir + 'arial.ttf', Dir + 'tahoma.ttf']);
  if BoldFontFile = '' then
    BoldFontFile := FirstExisting([Dir + 'segoeuib.ttf', Dir + 'arialbd.ttf', Dir + 'tahomabd.ttf']);
  { a Windows without those (Server Core, N editions, Wine): any TrueType font there }
  if (RegularFontFile = '') and (FindFirst(Dir + '*.ttf', faAnyFile, SR) = 0) then
  begin
    RegularFontFile := Dir + SR.Name;
    FindClose(SR);
  end;
  {$ELSEIF defined(DARWIN)}
  if RegularFontFile = '' then
    RegularFontFile := FirstExisting(['/System/Library/Fonts/Supplemental/Arial.ttf',
      '/Library/Fonts/Arial.ttf']);
  if BoldFontFile = '' then
    BoldFontFile := FirstExisting(['/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      '/Library/Fonts/Arial Bold.ttf']);
  {$ELSE}
  if RegularFontFile = '' then
    RegularFontFile := FirstExisting([
      '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/noto/NotoSans-Regular.ttf',
      '/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/TTF/DejaVuSans.ttf',
      '/usr/share/fonts/dejavu/DejaVuSans.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      '/system/fonts/Roboto-Regular.ttf', '/system/fonts/DroidSans.ttf']);
  if BoldFontFile = '' then
    BoldFontFile := FirstExisting([
      '/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf',
      '/usr/share/fonts/noto/NotoSans-Bold.ttf',
      '/usr/share/fonts/truetype/ubuntu/Ubuntu-B.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf',
      '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
      '/system/fonts/Roboto-Bold.ttf', '/system/fonts/DroidSans-Bold.ttf']);
  {$ENDIF}
  if BoldFontFile = '' then
    BoldFontFile := RegularFontFile;
end;

function InitFonts: string;
begin
  if (FTLib <> nil) or (FontCache <> nil) then
    Exit('');
  { FreeType when it is there; else Pastel's own TrueType reader (always on Android) }
  {$IFDEF ANDROID}
  UsePascalFonts := True;
  {$ELSE}
  UsePascalFonts := SameText(GetEnv('PASTEL_FONT_ENGINE'), 'pascal') or (LoadFreeType <> '');
  if not UsePascalFonts and (FT_Init_FreeType(FTLib) <> 0) then
    Exit('FreeType could not be initialized');
  {$ENDIF}
  Result := '';
  FindSystemFonts;
  if RegularFontFile = '' then
    Exit('no usable font was found (set PASTEL_FONT to a .ttf file)');
  FontCache := TStringList.Create;
  FontCache.Sorted := True;
  FontCache.OwnsObjects := True;
end;

procedure SetFontFiles(const Regular, Bold: string);
begin
  RegularFontFile := Regular;
  if Bold <> '' then
    BoldFontFile := Bold
  else
    BoldFontFile := Regular;
  if FontCache <> nil then
    FontCache.Clear;
end;

procedure DoneFonts;
begin
  FreeAndNil(FontCache);
  FreeAndNil(FontFiles);
end;

function GetFont(Size: Integer; Bold: Boolean): TPastelFont;
var
  Key: string;
  I: Integer;
begin
  if FontCache = nil then
    raise EPastelGraphics.Create('fonts are not initialized');
  if TextScale <> 1 then
    Size := Round(Size * TextScale);
  Key := BoolToStr(Bold, 'b', 'r') + IntToStr(Size);
  I := FontCache.IndexOf(Key);
  if I >= 0 then
    Exit(TPastelFont(FontCache.Objects[I]));
  if Bold then
    { without a bold font file the regular one is drawn thicker }
    Result := TPastelFont.Create(BoldFontFile, Size, UsePascalFonts and (BoldFontFile = RegularFontFile))
  else
    Result := TPastelFont.Create(RegularFontFile, Size);
  Result.FBold := Bold;
  FontCache.AddObject(Key, Result);
end;

{ ---- canvas ---- }

{ ---- TBitmap32 ---- }

procedure TBitmap32.SetSize(AWidth, AHeight: Integer);
begin
  FWidth := Max(0, AWidth);
  FHeight := Max(0, AHeight);
  SetLength(Pixels, FWidth * FHeight);
end;

function TBitmap32.Empty: Boolean;
begin
  Result := (FWidth = 0) or (FHeight = 0);
end;

procedure TBitmap32.LoadFromStream(Stream: TStream);
var
  Img: TFPMemoryImage;
  Reader: TFPCustomImageReader;
  Head: array[0..3] of Byte;
  X, Y: Integer;
  C: TFPColor;
  Start: Int64;
begin
  Start := Stream.Position;
  FillChar(Head, SizeOf(Head), 0);
  Stream.Read(Head, 4);
  Stream.Position := Start;
  if (Head[0] = $89) and (Head[1] = Ord('P')) then
    Reader := TFPReaderPNG.Create
  else if (Head[0] = $FF) and (Head[1] = $D8) then
    Reader := TFPReaderJPEG.Create
  else if (Head[0] = Ord('B')) and (Head[1] = Ord('M')) then
    Reader := TFPReaderBMP.Create
  else
    raise EPastelGraphics.Create('not a PNG, JPEG or BMP picture');
  Img := TFPMemoryImage.Create(0, 0);
  try
    try
      Img.LoadFromStream(Stream, Reader);
    except
      on E: Exception do
        raise EPastelGraphics.Create('cannot read the picture: ' + E.Message);
    end;
    SetSize(Img.Width, Img.Height);
    for Y := 0 to FHeight - 1 do
      for X := 0 to FWidth - 1 do
      begin
        C := Img.Colors[X, Y];
        Pixels[Y * FWidth + X] := (Cardinal(C.Alpha shr 8) shl 24) or (Cardinal(C.Red shr 8) shl 16) or
          (Cardinal(C.Green shr 8) shl 8) or Cardinal(C.Blue shr 8);
      end;
  finally
    Img.Free;
    Reader.Free;
  end;
end;

procedure TBitmap32.LoadFromFile(const FileName: string);
var
  F: TFileStream;
begin
  try
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    raise EPastelGraphics.CreateFmt('cannot open the picture %s', [FileName]);
  end;
  try
    LoadFromStream(F);
  finally
    F.Free;
  end;
end;

{ ---- TCanvas32 ---- }

function TCanvas32.Sc: Single;
begin
  if FScale <= 0 then
    Result := 1
  else
    Result := FScale;
end;

procedure TCanvas32.SetScale(AValue: Single);
begin
  if AValue <= 0 then
    AValue := 1;
  if AValue = FScale then
    Exit;
  FScale := AValue;
  if FLogW > 0 then
  begin
    FWidth := 0;      { make SetSize allocate again }
    SetSize(FLogW, FLogH);
  end;
end;

function TCanvas32.ToPixels(const R: TRectI): TRectI;
var
  X2, Y2: Integer;
begin
  if Sc = 1 then
    Exit(R);
  X2 := Round((R.X + R.W) * Sc);
  Y2 := Round((R.Y + R.H) * Sc);
  Result.X := Round(R.X * Sc);
  Result.Y := Round(R.Y * Sc);
  Result.W := X2 - Result.X;
  Result.H := Y2 - Result.Y;
end;

procedure TCanvas32.SetSize(AWidth, AHeight: Integer);
begin
  AWidth := Max(1, AWidth);
  AHeight := Max(1, AHeight);
  FLogW := AWidth;
  FLogH := AHeight;
  AWidth := Max(1, Ceil(AWidth * Sc));
  AHeight := Max(1, Ceil(AHeight * Sc));
  if (AWidth = FWidth) and (AHeight = FHeight) then
    Exit;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FPixels, FWidth * FHeight);
  FClip := RectI(0, 0, FWidth, FHeight);
  FClipStack := nil;
end;

function TCanvas32.PixelRect(const R: TRectI): TRectI;
begin
  Result := ToPixels(R);
end;

function TCanvas32.Data: Pointer;
begin
  Result := @FPixels[0];
end;

{ The drawing loops run without range checks, in debug builds too: the
  rectangles are cut to the clip (which is inside the canvas) first. }
{$PUSH}{$R-}{$Q-}

procedure TCanvas32.Clear(C: TColor32);
var
  Y: Integer;
begin
  if (FClip.X = 0) and (FClip.Y = 0) and (FClip.W = FWidth) and (FClip.H = FHeight) then
  begin
    FillDWord(FPixels[0], Length(FPixels), Cardinal(C));
    Exit;
  end;
  { only inside the clip rectangle (a partial repaint) }
  if (FClip.W <= 0) or (FClip.H <= 0) then
    Exit;
  for Y := FClip.Y to FClip.Y + FClip.H - 1 do
    FillDWord(FPixels[Y * FWidth + FClip.X], FClip.W, Cardinal(C));
end;

{$POP}

procedure TCanvas32.PushClip(const R: TRectI);
begin
  SetLength(FClipStack, Length(FClipStack) + 1);
  FClipStack[High(FClipStack)] := FClip;
  FClip := FClip.Intersect(ToPixels(R));
end;

{ ---- drawing in layout units ---- }

procedure TCanvas32.FillRect(X, Y, W, H: Integer; C: TColor32);
var
  R: TRectI;
begin
  R := ToPixels(RectI(X, Y, W, H));
  FillRectRaw(R.X, R.Y, R.W, R.H, C);
end;

procedure TCanvas32.FillRoundRect(X, Y, W, H: Integer; Radius: Single; C: TColor32);
var
  R: TRectI;
begin
  R := ToPixels(RectI(X, Y, W, H));
  FillRoundRectRaw(R.X, R.Y, R.W, R.H, Radius * Sc, C);
end;

procedure TCanvas32.StrokeRoundRect(X, Y, W, H: Integer; Radius, Thickness: Single; C: TColor32);
var
  R: TRectI;
begin
  R := ToPixels(RectI(X, Y, W, H));
  StrokeRoundRectRaw(R.X, R.Y, R.W, R.H, Radius * Sc, Thickness * Sc, C);
end;

procedure TCanvas32.DrawText(Font: TPastelFont; X, Y: Integer; const S: string; C: TColor32);
var
  K: Single;
begin
  K := Sc;
  if K = 1 then
    DrawTextRaw(Font, X, Y, S, C)
  else
    DrawTextRaw(GetFont(Max(1, Round(Font.Size * K)), Font.Bold), Round(X * K), Round(Y * K), S, C);
end;

procedure TCanvas32.DrawLine(X1, Y1, X2, Y2, Thickness: Single; C: TColor32);
begin
  DrawLineRaw(X1 * Sc, Y1 * Sc, X2 * Sc, Y2 * Sc, Thickness * Sc, C);
end;

procedure TCanvas32.FillCircle(CX, CY, Radius: Single; C: TColor32);
begin
  FillCircleRaw(CX * Sc, CY * Sc, Radius * Sc, C);
end;

procedure TCanvas32.DrawBitmap(B: TBitmap32; X, Y, W, H: Integer; Smooth: Boolean; Opacity: Byte);
var
  R: TRectI;
begin
  R := ToPixels(RectI(X, Y, W, H));
  DrawBitmapRaw(B, R.X, R.Y, R.W, R.H, Smooth, Opacity);
end;

procedure TCanvas32.PopClip;
begin
  if Length(FClipStack) = 0 then
    Exit;
  FClip := FClipStack[High(FClipStack)];
  SetLength(FClipStack, Length(FClipStack) - 1);
end;

{$PUSH}{$R-}{$Q-}

{ X div 255 for X up to 255 * 255, without dividing (the same result). }
function Div255(X: Cardinal): Cardinal; inline;
begin
  Result := (X + 1 + (X shr 8)) shr 8;
end;

{ C over the pixel at P with A (0..255) of its strength. }
procedure BlendAt(P: PCardinal; C: Cardinal; A: Cardinal); inline;
var
  IA, D: Cardinal;
begin
  if A = 0 then
    Exit;
  if A >= 255 then
  begin
    P^ := C or $FF000000;
    Exit;
  end;
  IA := 255 - A;
  D := P^;
  P^ := $FF000000 or
    (Div255(((C shr 16) and $FF) * A + ((D shr 16) and $FF) * IA) shl 16) or
    (Div255(((C shr 8) and $FF) * A + ((D shr 8) and $FF) * IA) shl 8) or
    Div255((C and $FF) * A + (D and $FF) * IA);
end;

{ N pixels from P, all with the same coverage: copied when opaque, else blended
  (the same result as blending them one by one). }
procedure BlendSpan(P: PCardinal; N: Integer; C: Cardinal; Coverage: Integer);
var
  A, IA, CRB, CG, D, Last, Res, RB, G: Cardinal;
  I: Integer;
begin
  if N <= 0 then
    Exit;
  A := ((C shr 24) * Cardinal(Coverage) + 127) div 255;
  if A = 0 then
    Exit;
  if A >= 255 then
  begin
    FillDWord(P^, N, C or $FF000000);
    Exit;
  end;
  IA := 255 - A;
  { red and blue side by side in one number (each stays below 65536, so the
    division by 255 of both at once is exact); a run of the same background
    is worked out once }
  CRB := (C and $00FF00FF) * A;
  CG := ((C shr 8) and $FF) * A;
  Last := not P[0];
  Res := 0;
  for I := 0 to N - 1 do
  begin
    D := P[I];
    if D <> Last then
    begin
      Last := D;
      RB := CRB + (D and $00FF00FF) * IA;
      RB := ((RB + $00010001 + ((RB shr 8) and $00FF00FF)) shr 8) and $00FF00FF;
      G := Div255(CG + ((D shr 8) and $FF) * IA);
      Res := $FF000000 or RB or (G shl 8);
    end;
    P[I] := Res;
  end;
end;

procedure TCanvas32.Blend(Index: Integer; C: TColor32; Coverage: Integer);
begin
  BlendAt(@FPixels[Index], Cardinal(C), ((Cardinal(C) shr 24) * Cardinal(Coverage) + 127) div 255);
end;

procedure TCanvas32.FillRectRaw(X, Y, W, H: Integer; C: TColor32);
var
  R: TRectI;
  PY: Integer;
begin
  R := RectI(X, Y, W, H).Intersect(FClip);
  if (R.W <= 0) or (R.H <= 0) then
    Exit;
  for PY := R.Y to R.Y + R.H - 1 do
    BlendSpan(@FPixels[PY * FWidth + R.X], R.W, Cardinal(C), 255);
end;

{ Signed distance from a pixel center to a rounded rectangle; negative inside. }
function RoundRectDistance(PX, PY: Single; X, Y, W, H, R: Single): Single;
var
  QX, QY: Single;
begin
  QX := Abs(PX - (X + W / 2)) - (W / 2 - R);
  QY := Abs(PY - (Y + H / 2)) - (H / 2 - R);
  if (QX > 0) and (QY > 0) then
    Result := Sqrt(QX * QX + QY * QY) - R
  else
    Result := Max(QX, QY) - R;
end;

function CoverageOf(D: Single): Integer; inline;
begin
  if D <= -0.5 then
    Result := 255
  else if D >= 0.5 then
    Result := 0
  else
    Result := Round((0.5 - D) * 255);
end;

procedure TCanvas32.FillPie(CX, CY, Radius, InnerRadius, Start, Sweep: Single; C: TColor32);
var
  R: TRectI;
  PX, PY, Cov: Integer;
  DX, DY, D, A, Rel, Edge: Single;
  Whole: Boolean;
begin
  CX := CX * Sc;
  CY := CY * Sc;
  Radius := Radius * Sc;
  InnerRadius := InnerRadius * Sc;
  if (Radius <= 0) or (Sweep <= 0) then
    Exit;
  Whole := Sweep >= 2 * Pi - 1E-6;
  Start := Start - Floor(Start / (2 * Pi)) * 2 * Pi;
  R := RectI(Floor(CX - Radius - 1), Floor(CY - Radius - 1), Ceil(2 * Radius + 3), Ceil(2 * Radius + 3)).Intersect(FClip);
  for PY := R.Y to R.Y + R.H - 1 do
    for PX := R.X to R.X + R.W - 1 do
    begin
      DX := PX + 0.5 - CX;
      DY := PY + 0.5 - CY;
      D := Sqrt(DX * DX + DY * DY);
      Cov := CoverageOf(D - Radius);
      if InnerRadius > 0 then
        Cov := Cov * CoverageOf(InnerRadius - D) div 255;
      if (Cov > 0) and not Whole then
      begin
        { the angle from the top, clockwise; how far (in pixels) from the slice's edges }
        A := ArcTan2(DX, -DY);
        if A < 0 then
          A := A + 2 * Pi;
        Rel := A - Start;
        if Rel < 0 then
          Rel := Rel + 2 * Pi;
        if Rel <= Sweep then
          Edge := -Min(Rel, Sweep - Rel) * D
        else
          Edge := Min(Rel - Sweep, 2 * Pi - Rel) * D;
        Cov := Cov * CoverageOf(Edge) div 255;
      end;
      if Cov > 0 then
        Blend(PY * FWidth + PX, C, Cov);
    end;
end;

{ Rounded rectangles: the distance is measured pixel by pixel only near the
  left and right edges (where the corners and the sides are); in between, a
  row has the same coverage everywhere (the distance there is the row's, or
  deep inside), so it is filled as one span. The same pixels as measuring all. }
procedure TCanvas32.FillRoundRectRaw(X, Y, W, H: Integer; Radius: Single; C: TColor32);
var
  R: TRectI;
  PX, PY, Edge, MidL, MidR, Cov: Integer;
  Row: PCardinal;
begin
  if (W <= 0) or (H <= 0) then
    Exit;
  Radius := Min(Radius, Min(W, H) / 2);
  if Radius <= 0 then
  begin
    FillRectRaw(X, Y, W, H, C);
    Exit;
  end;
  R := RectI(X, Y, W, H).Intersect(FClip);
  if (R.W <= 0) or (R.H <= 0) then
    Exit;
  Edge := Ceil(Radius) + 2;
  MidL := Max(R.X, X + Edge);
  MidR := Min(R.X + R.W, X + W - Edge);     { the span [MidL, MidR) }
  for PY := R.Y to R.Y + R.H - 1 do
  begin
    Row := @FPixels[PY * FWidth];
    if MidL < MidR then
    begin
      for PX := R.X to MidL - 1 do
        BlendAt(@Row[PX], Cardinal(C), ((Cardinal(C) shr 24) *
          Cardinal(CoverageOf(RoundRectDistance(PX + 0.5, PY + 0.5, X, Y, W, H, Radius))) + 127) div 255);
      Cov := CoverageOf(RoundRectDistance(X + W / 2, PY + 0.5, X, Y, W, H, Radius));
      BlendSpan(@Row[MidL], MidR - MidL, Cardinal(C), Cov);
      for PX := MidR to R.X + R.W - 1 do
        BlendAt(@Row[PX], Cardinal(C), ((Cardinal(C) shr 24) *
          Cardinal(CoverageOf(RoundRectDistance(PX + 0.5, PY + 0.5, X, Y, W, H, Radius))) + 127) div 255);
    end
    else
      for PX := R.X to R.X + R.W - 1 do
        BlendAt(@Row[PX], Cardinal(C), ((Cardinal(C) shr 24) *
          Cardinal(CoverageOf(RoundRectDistance(PX + 0.5, PY + 0.5, X, Y, W, H, Radius))) + 127) div 255);
  end;
end;

procedure TCanvas32.StrokeRoundRectRaw(X, Y, W, H: Integer; Radius, Thickness: Single; C: TColor32);
var
  R: TRectI;
  PX, PY, Edge, MidL, MidR: Integer;
  OR_, IR: Single;
  Row: PCardinal;

  function CoverAt(FX, FY: Single): Integer; inline;
  var
    Outer, Inner: Integer;
  begin
    Outer := CoverageOf(RoundRectDistance(FX, FY, X, Y, W, H, OR_));
    Inner := CoverageOf(RoundRectDistance(FX, FY, X + Thickness, Y + Thickness,
      W - 2 * Thickness, H - 2 * Thickness, IR));
    if Outer > Inner then
      Result := Outer - Inner
    else
      Result := 0;
  end;

begin
  if (W <= 0) or (H <= 0) then
    Exit;
  Radius := Min(Radius, Min(W, H) / 2);
  OR_ := Max(Radius, 0.01);
  IR := Max(Max(0, Radius - Thickness), 0.01);
  R := RectI(X, Y, W, H).Intersect(FClip);
  if (R.W <= 0) or (R.H <= 0) then
    Exit;
  Edge := Ceil(Radius) + Ceil(Max(Thickness, 0)) + 2;
  MidL := Max(R.X, X + Edge);
  MidR := Min(R.X + R.W, X + W - Edge);
  for PY := R.Y to R.Y + R.H - 1 do
  begin
    Row := @FPixels[PY * FWidth];
    if MidL < MidR then
    begin
      for PX := R.X to MidL - 1 do
        BlendAt(@Row[PX], Cardinal(C), ((Cardinal(C) shr 24) * Cardinal(CoverAt(PX + 0.5, PY + 0.5)) + 127) div 255);
      BlendSpan(@Row[MidL], MidR - MidL, Cardinal(C), CoverAt(X + W / 2, PY + 0.5));
      for PX := MidR to R.X + R.W - 1 do
        BlendAt(@Row[PX], Cardinal(C), ((Cardinal(C) shr 24) * Cardinal(CoverAt(PX + 0.5, PY + 0.5)) + 127) div 255);
    end
    else
      for PX := R.X to R.X + R.W - 1 do
        BlendAt(@Row[PX], Cardinal(C), ((Cardinal(C) shr 24) * Cardinal(CoverAt(PX + 0.5, PY + 0.5)) + 127) div 255);
  end;
end;

procedure TCanvas32.DrawLineRaw(X1, Y1, X2, Y2, Thickness: Single; C: TColor32);
var
  R: TRectI;
  PX, PY: Integer;
  DX, DY, Len2, T, QX, QY, D, HalfT: Single;
begin
  HalfT := Thickness / 2;
  R := RectI(Floor(Min(X1, X2) - HalfT - 1), Floor(Min(Y1, Y2) - HalfT - 1),
    Ceil(Abs(X2 - X1) + Thickness + 3), Ceil(Abs(Y2 - Y1) + Thickness + 3)).Intersect(FClip);
  DX := X2 - X1;
  DY := Y2 - Y1;
  Len2 := DX * DX + DY * DY;
  for PY := R.Y to R.Y + R.H - 1 do
    for PX := R.X to R.X + R.W - 1 do
    begin
      { distance from the pixel center to the segment }
      if Len2 = 0 then
        T := 0
      else
        T := EnsureRange(((PX + 0.5 - X1) * DX + (PY + 0.5 - Y1) * DY) / Len2, 0, 1);
      QX := X1 + T * DX - (PX + 0.5);
      QY := Y1 + T * DY - (PY + 0.5);
      D := Sqrt(QX * QX + QY * QY) - HalfT;
      if D < 0.5 then
        Blend(PY * FWidth + PX, C, CoverageOf(D));
    end;
end;

procedure TCanvas32.FillCircleRaw(CX, CY, Radius: Single; C: TColor32);
var
  R: TRectI;
  PX, PY: Integer;
  DX, DY: Single;
begin
  R := RectI(Floor(CX - Radius - 1), Floor(CY - Radius - 1), Ceil(2 * Radius + 3), Ceil(2 * Radius + 3)).Intersect(FClip);
  for PY := R.Y to R.Y + R.H - 1 do
    for PX := R.X to R.X + R.W - 1 do
    begin
      DX := PX + 0.5 - CX;
      DY := PY + 0.5 - CY;
      Blend(PY * FWidth + PX, C, CoverageOf(Sqrt(DX * DX + DY * DY) - Radius));
    end;
end;

procedure TCanvas32.DrawBitmapRaw(B: TBitmap32; X, Y, W, H: Integer; Smooth: Boolean; Opacity: Byte);
var
  R: TRectI;
  PY, I, A, SY0, SY1, WY, IWY: Integer;
  F: Single;
  Col, C00, C10, C01, C11: Cardinal;
  XS0, XS1, XW: array of Integer;   { per column of R: the source columns and the weight of the second (0..256) }
  Src0, Src1: PCardinal;
  Dst: PCardinal;

  function Lerp2(Shift: Integer): Cardinal; inline;
  var
    Top, Bottom: Cardinal;
  begin
    Top := ((C00 shr Shift) and $FF) * Cardinal(256 - XW[I]) + ((C10 shr Shift) and $FF) * Cardinal(XW[I]);
    Bottom := ((C01 shr Shift) and $FF) * Cardinal(256 - XW[I]) + ((C11 shr Shift) and $FF) * Cardinal(XW[I]);
    Result := (Top * Cardinal(IWY) + Bottom * Cardinal(WY) + 32768) shr 16;
  end;

  { the source position of a destination pixel center (bilinear: between
    which two pixels, and how far); clamped at the picture's edges }
  procedure SourceOf(P, Dest, Size: Integer; out S0, S1, Wt: Integer);
  begin
    F := (P + 0.5) * Size / Dest - 0.5;
    if F <= 0 then
    begin
      S0 := 0;
      S1 := 0;
      Wt := 0;
    end
    else if F >= Size - 1 then
    begin
      S0 := Size - 1;
      S1 := Size - 1;
      Wt := 0;
    end
    else
    begin
      S0 := Trunc(F);
      S1 := S0 + 1;
      Wt := Round((F - S0) * 256);
    end;
  end;

begin
  if (B = nil) or B.Empty or (W <= 0) or (H <= 0) then
    Exit;
  R := RectI(X, Y, W, H).Intersect(FClip);
  if (R.W <= 0) or (R.H <= 0) then
    Exit;
  { the picture's own size (a video frame): pixel for pixel, opaque ones copied }
  if (B.Width = W) and (B.Height = H) and (Opacity = 255) then
  begin
    for PY := R.Y to R.Y + R.H - 1 do
    begin
      Src0 := @B.Pixels[(PY - Y) * W + (R.X - X)];
      Dst := @FPixels[PY * FWidth + R.X];
      for I := 0 to R.W - 1 do
      begin
        Col := Src0[I];
        A := Col shr 24;
        if A = 255 then
          Dst[I] := Col
        else if A > 0 then
          BlendAt(@Dst[I], Col, A);
      end;
    end;
    Exit;
  end;
  Smooth := Smooth and ((B.Width <> W) or (B.Height <> H));
  SetLength(XS0, R.W);
  SetLength(XS1, R.W);
  SetLength(XW, R.W);
  for I := 0 to R.W - 1 do
    if Smooth then
      SourceOf(R.X + I - X, W, B.Width, XS0[I], XS1[I], XW[I])
    else
    begin
      XS0[I] := Min(Max(Trunc((R.X + I - X + 0.5) * B.Width / W), 0), B.Width - 1);
      XS1[I] := XS0[I];
      XW[I] := 0;
    end;
  for PY := R.Y to R.Y + R.H - 1 do
  begin
    if Smooth then
      SourceOf(PY - Y, H, B.Height, SY0, SY1, WY)
    else
    begin
      SY0 := Min(Max(Trunc((PY - Y + 0.5) * B.Height / H), 0), B.Height - 1);
      SY1 := SY0;
      WY := 0;
    end;
    IWY := 256 - WY;
    Src0 := @B.Pixels[SY0 * B.Width];
    Src1 := @B.Pixels[SY1 * B.Width];
    Dst := @FPixels[PY * FWidth + R.X];
    for I := 0 to R.W - 1 do
    begin
      if Smooth then
      begin
        C00 := Src0[XS0[I]];
        C10 := Src0[XS1[I]];
        C01 := Src1[XS0[I]];
        C11 := Src1[XS1[I]];
        if (C00 = C10) and (C00 = C01) and (C00 = C11) then
          Col := C00
        else
          Col := (Lerp2(24) shl 24) or (Lerp2(16) shl 16) or (Lerp2(8) shl 8) or Lerp2(0);
      end
      else
        Col := Src0[XS0[I]];
      A := Col shr 24;
      if Opacity <> 255 then
        A := A * Opacity div 255;
      if A >= 255 then
        Dst[I] := Col
      else if A > 0 then
        BlendAt(@Dst[I], Col, A);
    end;
  end;
end;

procedure TCanvas32.DrawTextRaw(Font: TPastelFont; X, Y: Integer; const S: string; C: TColor32);
var
  I, PenX, Baseline, GX, GY, Row, Col, R0, R1, C0, C1, CA: Integer;
  G: PGlyph;
  Prev: FT_UInt;
  Src: PByte;
  Dst: PCardinal;
begin
  PenX := X;
  Baseline := Y + Font.Ascent;
  Prev := 0;
  CA := Cardinal(C) shr 24;
  if CA = 0 then
    Exit;
  I := 1;
  while I <= Length(S) do
  begin
    G := Font.Glyph(NextCodePoint(S, I));
    Inc(PenX, Font.Kerning(Prev, G^.Index));
    Prev := G^.Index;
    GX := PenX + G^.Left;
    GY := Baseline - G^.Top;
    { the glyph's rows and columns inside the clip }
    R0 := Max(0, FClip.Y - GY);
    R1 := Min(G^.Height, FClip.Y + FClip.H - GY);
    C0 := Max(0, FClip.X - GX);
    C1 := Min(G^.Width, FClip.X + FClip.W - GX);
    if (R0 < R1) and (C0 < C1) then
      for Row := R0 to R1 - 1 do
      begin
        Src := @G^.Bits[Row * G^.Width];
        Dst := @FPixels[(GY + Row) * FWidth + GX];
        for Col := C0 to C1 - 1 do
          if Src[Col] > 0 then
            BlendAt(@Dst[Col], Cardinal(C), (Cardinal(CA) * Src[Col] + 127) div 255);
      end;
    Inc(PenX, G^.Advance);
  end;
end;

{$POP}

function TCanvas32.GetPixel(X, Y: Integer): TColor32;
begin
  X := Round(X * Sc);
  Y := Round(Y * Sc);
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit(0);
  Result := TColor32(FPixels[Y * FWidth + X]);
end;

{ A small PNG writer with no dependencies: the image data is stored in
  uncompressed deflate blocks. Good enough for screenshots and tests. }
var
  CrcTable: array[0..255] of Cardinal;
  CrcReady: Boolean = False;

procedure MakeCrcTable;
var
  N, K: Integer;
  C: Cardinal;
begin
  for N := 0 to 255 do
  begin
    C := N;
    for K := 0 to 7 do
      if (C and 1) <> 0 then
        C := $EDB88320 xor (C shr 1)
      else
        C := C shr 1;
    CrcTable[N] := C;
  end;
  CrcReady := True;
end;

function Crc32(const Buf: array of Byte; Start, Len: Integer): Cardinal;
var
  I: Integer;
begin
  if not CrcReady then
    MakeCrcTable;
  Result := $FFFFFFFF;
  for I := Start to Start + Len - 1 do
    Result := CrcTable[(Result xor Buf[I]) and $FF] xor (Result shr 8);
  Result := Result xor $FFFFFFFF;
end;

procedure TCanvas32.SaveToPNG(const FileName: string);
var
  Raw, Z, Chunk: array of Byte;
  Stream: TFileStream;
  RowLen, I, X, Y, Pos, Left, BlockLen, ZPos: Integer;
  P, A, B: Cardinal;

  procedure PutBE(var Buf: array of Byte; At: Integer; V: Cardinal);
  begin
    Buf[At] := (V shr 24) and $FF;
    Buf[At + 1] := (V shr 16) and $FF;
    Buf[At + 2] := (V shr 8) and $FF;
    Buf[At + 3] := V and $FF;
  end;

  procedure WriteChunk(const Kind: string; const Data: array of Byte; Len: Integer);
  var
    Head: array[0..7] of Byte;
    Tail: array[0..3] of Byte;
    I: Integer;
  begin
    SetLength(Chunk, Len + 4);
    for I := 0 to 3 do
      Chunk[I] := Ord(Kind[I + 1]);
    if Len > 0 then
      Move(Data[0], Chunk[4], Len);
    PutBE(Head, 0, Len);
    for I := 0 to 3 do
      Head[4 + I] := Ord(Kind[I + 1]);
    Stream.WriteBuffer(Head, 8);
    if Len > 0 then
      Stream.WriteBuffer(Data[0], Len);
    PutBE(Tail, 0, Crc32(Chunk, 0, Len + 4));
    Stream.WriteBuffer(Tail, 4);
  end;

const
  Signature: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
var
  Header: array[0..12] of Byte;
begin
  { raw scanlines: filter byte 0 + RGB }
  RowLen := 1 + FWidth * 3;
  SetLength(Raw, RowLen * FHeight);
  Pos := 0;
  for Y := 0 to FHeight - 1 do
  begin
    Raw[Pos] := 0;
    Inc(Pos);
    for X := 0 to FWidth - 1 do
    begin
      P := FPixels[Y * FWidth + X];
      Raw[Pos] := (P shr 16) and $FF;
      Raw[Pos + 1] := (P shr 8) and $FF;
      Raw[Pos + 2] := P and $FF;
      Inc(Pos, 3);
    end;
  end;

  { zlib stream with stored blocks }
  SetLength(Z, 2 + Length(Raw) + 5 * (Length(Raw) div 65535 + 1) + 4);
  Z[0] := $78;
  Z[1] := $01;
  ZPos := 2;
  Pos := 0;
  Left := Length(Raw);
  repeat
    BlockLen := Min(Left, 65535);
    if BlockLen = Left then Z[ZPos] := 1 else Z[ZPos] := 0;
    Z[ZPos + 1] := BlockLen and $FF;
    Z[ZPos + 2] := (BlockLen shr 8) and $FF;
    Z[ZPos + 3] := (not BlockLen) and $FF;
    Z[ZPos + 4] := ((not BlockLen) shr 8) and $FF;
    Inc(ZPos, 5);
    if BlockLen > 0 then
      Move(Raw[Pos], Z[ZPos], BlockLen);
    Inc(ZPos, BlockLen);
    Inc(Pos, BlockLen);
    Dec(Left, BlockLen);
  until Left = 0;
  A := 1;
  B := 0;
  for I := 0 to High(Raw) do
  begin
    A := (A + Raw[I]) mod 65521;
    B := (B + A) mod 65521;
  end;
  PutBE(Z, ZPos, (B shl 16) or A);
  Inc(ZPos, 4);

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Signature, 8);
    PutBE(Header, 0, FWidth);
    PutBE(Header, 4, FHeight);
    Header[8] := 8;    { bit depth }
    Header[9] := 2;    { RGB }
    Header[10] := 0;
    Header[11] := 0;
    Header[12] := 0;
    WriteChunk('IHDR', Header, 13);
    WriteChunk('IDAT', Z, ZPos);
    WriteChunk('IEND', Header, 0);
  finally
    Stream.Free;
  end;
end;

{ S cut to fit Width, with '…'. A cell shows one line, so a line break ends
  it; and only as many letters as could ever fit are measured (no letter is
  narrower than 2 pixels): a cell of 100 KB of text costs what a short one does.
  The cut is found by halving (a few measurements, not one per letter). }
function FitText(Font: TPastelFont; const S: string; Width: Integer): string;
var
  Starts: array of Integer;     { where each letter begins (bytes) }
  N, I, Lo, Hi, Mid, MaxLetters: Integer;
  Cut: Boolean;
  T: string;
begin
  if Width <= 0 then
    Exit('');
  MaxLetters := Width div 2 + 2;
  Starts := nil;
  SetLength(Starts, MaxLetters + 2);
  N := 0;
  I := 1;
  Cut := False;
  while I <= Length(S) do
  begin
    if S[I] in [#10, #13] then
    begin
      Cut := True;
      Break;
    end;
    if N > MaxLetters then
    begin
      Cut := True;
      Break;
    end;
    Starts[N] := I;
    Inc(N);
    { the next letter: past the UTF-8 continuation bytes }
    Inc(I);
    while (I <= Length(S)) and ((Ord(S[I]) and $C0) = $80) do
      Inc(I);
  end;
  { the letters kept: Starts[0..N-1]; they end before I }
  T := Copy(S, 1, I - 1);
  if not Cut and (Font.TextWidth(T) <= Width) then
    Exit(T);
  if Cut and (Font.TextWidth(T + '…') <= Width) then
    Exit(T + '…');
  { the most letters with '…' that fit }
  Lo := 0;
  Hi := N - 1;
  while Lo < Hi do
  begin
    Mid := (Lo + Hi + 1) div 2;
    if Font.TextWidth(Copy(S, 1, Starts[Mid] - 1) + '…') <= Width then
      Lo := Mid
    else
      Hi := Mid - 1;
  end;
  if Lo = 0 then
    Exit('…');
  Result := Copy(S, 1, Starts[Lo] - 1) + '…';
end;

end.
