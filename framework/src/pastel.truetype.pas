{ Pastel - TrueType fonts in plain Pascal: reads a .ttf (or the first font of a
  .ttc) and draws its glyphs with anti-aliasing, without FreeType.

  Pastel uses FreeType when it is there (it also hints small text); this unit
  is used where it is not: always on Android, and on a desktop without the
  FreeType library. Outlines with straight lines and quadratic curves (the
  "glyf" table) are supported, simple and composite glyphs, the cmap formats 4
  and 12 and kerning pairs of the "kern" table. Fonts with CFF outlines (.otf)
  are not.

  Part of the Pastel project, MIT License. }
unit Pastel.TrueType;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Classes, SysUtils;

type
  ETrueType = class(Exception);

  { A drawn glyph: Width x Height coverage bytes (0..255), row by row; Left is
    the distance from the pen to the first column, Top from the baseline up to
    the first row; Advance moves the pen. }
  TTrueTypeBitmap = record
    Width, Height, Left, Top, Advance: Integer;
    Bits: array of Byte;
  end;

  TTrueTypeFont = class
  private
    FData: array of Byte;
    FBase: Integer;                      { the font's offset (in a .ttc) }
    FUnitsPerEm, FNumGlyphs, FLocFormat, FNumHMetrics: Integer;
    FAscender, FDescender, FLineGap: Integer;
    FLoca, FGlyf, FHmtx, FCmapSub, FCmapFormat: Integer;
    FKernPairs: array of Cardinal;       { left shl 16 or right, sorted }
    FKernValues: array of SmallInt;
    function U8(P: Integer): Integer; inline;
    function U16(P: Integer): Integer; inline;
    function S16(P: Integer): Integer; inline;
    function U32(P: Integer): Cardinal; inline;
    function FindTable(const Tag: string): Integer;
    procedure ReadCmap;
    procedure ReadKern;
    function GlyphOffset(Glyph: Integer; out Len: Integer): Integer;
  public
    constructor Create(const FileName: string);
    constructor CreateFromStream(Stream: TStream);
    procedure Load;
    { 0 when the font has no glyph for the code point. }
    function GlyphIndex(CodePoint: Cardinal): Integer;
    { In font units. }
    function AdvanceWidth(Glyph: Integer): Integer;
    function Kerning(Left, Right: Integer): Integer;
    { Draws a glyph at Scale (pixels per font unit). Embolden thickens the
      strokes (a bold look from a regular font). }
    procedure Render(Glyph: Integer; Scale: Double; Embolden: Boolean; out Bitmap: TTrueTypeBitmap);
    property UnitsPerEm: Integer read FUnitsPerEm;
    property Ascender: Integer read FAscender;
    property Descender: Integer read FDescender;
    property LineGap: Integer read FLineGap;
    property NumGlyphs: Integer read FNumGlyphs;
    function HasKerning: Boolean;
  end;

implementation

uses
  Math;

type
  TPt = record
    X, Y: Double;
    OnCurve: Boolean;
  end;
  TPtArray = array of TPt;
  TContours = array of TPtArray;
  TMatrix = record
    A, B, C, D, E, F: Double;   { x' = A x + C y + E; y' = B x + D y + F }
  end;

function TTrueTypeFont.U8(P: Integer): Integer;
begin
  Result := FData[P];
end;

function TTrueTypeFont.U16(P: Integer): Integer;
begin
  Result := (FData[P] shl 8) or FData[P + 1];
end;

function TTrueTypeFont.S16(P: Integer): Integer;
begin
  Result := SmallInt((FData[P] shl 8) or FData[P + 1]);
end;

function TTrueTypeFont.U32(P: Integer): Cardinal;
begin
  Result := (Cardinal(FData[P]) shl 24) or (Cardinal(FData[P + 1]) shl 16) or
    (Cardinal(FData[P + 2]) shl 8) or FData[P + 3];
end;

constructor TTrueTypeFont.Create(const FileName: string);
var
  S: TFileStream;
begin
  inherited Create;
  try
    S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do
      raise ETrueType.Create('cannot open font ' + FileName);
  end;
  try
    SetLength(FData, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(FData[0], S.Size);
  finally
    S.Free;
  end;
  Load;
end;

constructor TTrueTypeFont.CreateFromStream(Stream: TStream);
begin
  inherited Create;
  SetLength(FData, Stream.Size - Stream.Position);
  if Length(FData) > 0 then
    Stream.ReadBuffer(FData[0], Length(FData));
  Load;
end;

function TTrueTypeFont.FindTable(const Tag: string): Integer;
var
  I, N, P: Integer;
begin
  N := U16(FBase + 4);
  for I := 0 to N - 1 do
  begin
    P := FBase + 12 + I * 16;
    if (Chr(FData[P]) = Tag[1]) and (Chr(FData[P + 1]) = Tag[2]) and (Chr(FData[P + 2]) = Tag[3]) and
       (Chr(FData[P + 3]) = Tag[4]) then
    begin
      Result := Integer(U32(P + 8));
      if Result >= Length(FData) then
        Result := -1;
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TTrueTypeFont.Load;
var
  Head, Hhea, Maxp: Integer;
begin
  if Length(FData) < 12 then
    raise ETrueType.Create('not a font file');
  FBase := 0;
  { a collection (.ttc): the first font }
  if U32(0) = $74746366 then
    FBase := Integer(U32(12));
  if U32(FBase) = $4F54544F then
    raise ETrueType.Create('fonts with CFF outlines (.otf) are not supported here');
  Head := FindTable('head');
  Hhea := FindTable('hhea');
  Maxp := FindTable('maxp');
  FLoca := FindTable('loca');
  FGlyf := FindTable('glyf');
  FHmtx := FindTable('hmtx');
  if (Head < 0) or (Hhea < 0) or (Maxp < 0) or (FLoca < 0) or (FGlyf < 0) or (FHmtx < 0) then
    raise ETrueType.Create('not a TrueType font (a table is missing)');
  FUnitsPerEm := U16(Head + 18);
  if FUnitsPerEm = 0 then
    FUnitsPerEm := 1000;
  FLocFormat := S16(Head + 50);
  FAscender := S16(Hhea + 4);
  FDescender := S16(Hhea + 6);
  FLineGap := S16(Hhea + 8);
  FNumHMetrics := U16(Hhea + 34);
  FNumGlyphs := U16(Maxp + 4);
  ReadCmap;
  ReadKern;
end;

procedure TTrueTypeFont.ReadCmap;
var
  Cmap, N, I, P, PlatformID, EncodingID, Sub, Fmt, Best, BestRank, Rank: Integer;
begin
  FCmapSub := -1;
  Cmap := FindTable('cmap');
  if Cmap < 0 then
    Exit;
  N := U16(Cmap + 2);
  Best := -1;
  BestRank := -1;
  for I := 0 to N - 1 do
  begin
    P := Cmap + 4 + I * 8;
    PlatformID := U16(P);
    EncodingID := U16(P + 2);
    Sub := Cmap + Integer(U32(P + 4));
    Fmt := U16(Sub);
    { Unicode tables; the full repertoire (format 12) is preferred }
    Rank := -1;
    if (Fmt = 12) and ((PlatformID = 0) or ((PlatformID = 3) and (EncodingID = 10))) then
      Rank := 2
    else if (Fmt = 4) and ((PlatformID = 0) or ((PlatformID = 3) and (EncodingID = 1))) then
      Rank := 1;
    if Rank > BestRank then
    begin
      Best := Sub;
      BestRank := Rank;
    end;
  end;
  if Best >= 0 then
  begin
    FCmapSub := Best;
    FCmapFormat := U16(Best);
  end;
end;

procedure TTrueTypeFont.ReadKern;
var
  Kern, NTables, T, P, Coverage, Len, NPairs, I: Integer;
begin
  Kern := FindTable('kern');
  if Kern < 0 then
    Exit;
  NTables := U16(Kern + 2);
  P := Kern + 4;
  for T := 0 to NTables - 1 do
  begin
    Len := U16(P + 2);
    Coverage := U16(P + 4);
    { format 0, horizontal kerning }
    if ((Coverage shr 8) = 0) and ((Coverage and 1) = 1) then
    begin
      NPairs := U16(P + 6);
      SetLength(FKernPairs, NPairs);
      SetLength(FKernValues, NPairs);
      for I := 0 to NPairs - 1 do
      begin
        FKernPairs[I] := (Cardinal(U16(P + 14 + I * 6)) shl 16) or Cardinal(U16(P + 16 + I * 6));
        FKernValues[I] := S16(P + 18 + I * 6);
      end;
      Exit;
    end;
    Inc(P, Len);
  end;
end;

function TTrueTypeFont.GlyphIndex(CodePoint: Cardinal): Integer;
var
  SegX2, I, EndCode, StartCode, Delta, RangeOffset, P, Lo, Hi, Mid, N: Integer;
  S, E: Cardinal;
begin
  Result := 0;
  if FCmapSub < 0 then
    Exit;
  if FCmapFormat = 4 then
  begin
    if CodePoint > $FFFF then
      Exit;
    SegX2 := U16(FCmapSub + 6);
    for I := 0 to SegX2 div 2 - 1 do
    begin
      EndCode := U16(FCmapSub + 14 + I * 2);
      if Integer(CodePoint) > EndCode then
        Continue;
      StartCode := U16(FCmapSub + 16 + SegX2 + I * 2);
      if Integer(CodePoint) < StartCode then
        Exit;
      Delta := S16(FCmapSub + 16 + SegX2 * 2 + I * 2);
      P := FCmapSub + 16 + SegX2 * 3 + I * 2;
      RangeOffset := U16(P);
      if RangeOffset = 0 then
        Result := (Integer(CodePoint) + Delta) and $FFFF
      else
      begin
        P := P + RangeOffset + (Integer(CodePoint) - StartCode) * 2;
        if P + 1 >= Length(FData) then
          Exit;
        Result := U16(P);
        if Result <> 0 then
          Result := (Result + Delta) and $FFFF;
      end;
      Exit;
    end;
  end
  else if FCmapFormat = 12 then
  begin
    N := Integer(U32(FCmapSub + 12));
    Lo := 0;
    Hi := N - 1;
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      P := FCmapSub + 16 + Mid * 12;
      S := U32(P);
      E := U32(P + 4);
      if CodePoint < S then
        Hi := Mid - 1
      else if CodePoint > E then
        Lo := Mid + 1
      else
        Exit(Integer(U32(P + 8) + (CodePoint - S)));
    end;
  end;
  if Result >= FNumGlyphs then
    Result := 0;
end;

function TTrueTypeFont.AdvanceWidth(Glyph: Integer): Integer;
begin
  if FNumHMetrics = 0 then
    Exit(FUnitsPerEm div 2);
  if Glyph >= FNumHMetrics then
    Glyph := FNumHMetrics - 1;
  Result := U16(FHmtx + Glyph * 4);
end;

function TTrueTypeFont.HasKerning: Boolean;
begin
  Result := Length(FKernPairs) > 0;
end;

function TTrueTypeFont.Kerning(Left, Right: Integer): Integer;
var
  Key: Cardinal;
  Lo, Hi, Mid: Integer;
begin
  Result := 0;
  if Length(FKernPairs) = 0 then
    Exit;
  Key := (Cardinal(Left) shl 16) or Cardinal(Right);
  Lo := 0;
  Hi := High(FKernPairs);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if FKernPairs[Mid] < Key then
      Lo := Mid + 1
    else if FKernPairs[Mid] > Key then
      Hi := Mid - 1
    else
      Exit(FKernValues[Mid]);
  end;
end;

function TTrueTypeFont.GlyphOffset(Glyph: Integer; out Len: Integer): Integer;
var
  A, B: Integer;
begin
  Len := 0;
  if (Glyph < 0) or (Glyph >= FNumGlyphs) then
    Exit(-1);
  if FLocFormat = 0 then
  begin
    A := U16(FLoca + Glyph * 2) * 2;
    B := U16(FLoca + Glyph * 2 + 2) * 2;
  end
  else
  begin
    A := Integer(U32(FLoca + Glyph * 4));
    B := Integer(U32(FLoca + Glyph * 4 + 4));
  end;
  Len := B - A;
  if Len <= 0 then
    Exit(-1);
  Result := FGlyf + A;
  if Result + Len > Length(FData) then
    Exit(-1);
end;

{ ---- outlines ---- }

function Apply(const M: TMatrix; X, Y: Double): TPt;
begin
  Result.X := M.A * X + M.C * Y + M.E;
  Result.Y := M.B * X + M.D * Y + M.F;
  Result.OnCurve := True;
end;

procedure GetOutline(Font: TTrueTypeFont; Glyph: Integer; const M: TMatrix; var Contours: TContours; Depth: Integer);
var
  P, Len, NContours, NPoints, I, J, Flag, Rep, InstrLen, X, Y, Start, Flags, Comp: Integer;
  Ends: array of Integer;
  FlagList: array of Byte;
  Xs, Ys: array of Integer;
  Contour: TPtArray;
  Sub: TMatrix;
  DX, DY, SA, SB, SC, SD: Double;
begin
  if Depth > 8 then
    Exit;
  P := Font.GlyphOffset(Glyph, Len);
  if P < 0 then
    Exit;
  NContours := Font.S16(P);
  if NContours >= 0 then
  begin
    SetLength(Ends, NContours);
    for I := 0 to NContours - 1 do
      Ends[I] := Font.U16(P + 10 + I * 2);
    if NContours = 0 then
      Exit;
    NPoints := Ends[NContours - 1] + 1;
    InstrLen := Font.U16(P + 10 + NContours * 2);
    J := P + 12 + NContours * 2 + InstrLen;
    SetLength(FlagList, NPoints);
    I := 0;
    while I < NPoints do
    begin
      Flag := Font.U8(J);
      Inc(J);
      FlagList[I] := Flag;
      Inc(I);
      if (Flag and 8) <> 0 then
      begin
        Rep := Font.U8(J);
        Inc(J);
        while (Rep > 0) and (I < NPoints) do
        begin
          FlagList[I] := Flag;
          Inc(I);
          Dec(Rep);
        end;
      end;
    end;
    SetLength(Xs, NPoints);
    SetLength(Ys, NPoints);
    X := 0;
    for I := 0 to NPoints - 1 do
    begin
      Flag := FlagList[I];
      if (Flag and 2) <> 0 then
      begin
        if (Flag and 16) <> 0 then Inc(X, Font.U8(J)) else Dec(X, Font.U8(J));
        Inc(J);
      end
      else if (Flag and 16) = 0 then
      begin
        Inc(X, Font.S16(J));
        Inc(J, 2);
      end;
      Xs[I] := X;
    end;
    Y := 0;
    for I := 0 to NPoints - 1 do
    begin
      Flag := FlagList[I];
      if (Flag and 4) <> 0 then
      begin
        if (Flag and 32) <> 0 then Inc(Y, Font.U8(J)) else Dec(Y, Font.U8(J));
        Inc(J);
      end
      else if (Flag and 32) = 0 then
      begin
        Inc(Y, Font.S16(J));
        Inc(J, 2);
      end;
      Ys[I] := Y;
    end;
    Start := 0;
    for I := 0 to NContours - 1 do
    begin
      SetLength(Contour, Ends[I] - Start + 1);
      for J := Start to Ends[I] do
      begin
        Contour[J - Start] := Apply(M, Xs[J], Ys[J]);
        Contour[J - Start].OnCurve := (FlagList[J] and 1) <> 0;
      end;
      if Length(Contour) > 0 then
      begin
        SetLength(Contours, Length(Contours) + 1);
        Contours[High(Contours)] := Contour;
      end;
      Start := Ends[I] + 1;
    end;
  end
  else
  begin
    { a composite glyph: other glyphs, moved and scaled }
    J := P + 10;
    repeat
      Flags := Font.U16(J);
      Comp := Font.U16(J + 2);
      Inc(J, 4);
      if (Flags and 1) <> 0 then
      begin
        DX := Font.S16(J);
        DY := Font.S16(J + 2);
        Inc(J, 4);
      end
      else
      begin
        DX := ShortInt(Font.U8(J));
        DY := ShortInt(Font.U8(J + 1));
        Inc(J, 2);
      end;
      if (Flags and 2) = 0 then
      begin
        { points matched by number: not supported, placed at the origin }
        DX := 0;
        DY := 0;
      end;
      SA := 1; SB := 0; SC := 0; SD := 1;
      if (Flags and 8) <> 0 then
      begin
        SA := Font.S16(J) / 16384;
        SD := SA;
        Inc(J, 2);
      end
      else if (Flags and $40) <> 0 then
      begin
        SA := Font.S16(J) / 16384;
        SD := Font.S16(J + 2) / 16384;
        Inc(J, 4);
      end
      else if (Flags and $80) <> 0 then
      begin
        SA := Font.S16(J) / 16384;
        SB := Font.S16(J + 2) / 16384;
        SC := Font.S16(J + 4) / 16384;
        SD := Font.S16(J + 6) / 16384;
        Inc(J, 8);
      end;
      { Sub = M * (component transform) }
      Sub.A := M.A * SA + M.C * SB;
      Sub.B := M.B * SA + M.D * SB;
      Sub.C := M.A * SC + M.C * SD;
      Sub.D := M.B * SC + M.D * SD;
      Sub.E := M.A * DX + M.C * DY + M.E;
      Sub.F := M.B * DX + M.D * DY + M.F;
      GetOutline(Font, Comp, Sub, Contours, Depth + 1);
    until (Flags and $20) = 0;
  end;
end;

{ ---- the rasterizer: signed area per pixel, summed along each row ---- }

type
  TRaster = record
    W, H: Integer;
    Acc: array of Single;
  end;

procedure RasterLine(var R: TRaster; X0, Y0, X1, Y1: Double);
var
  Dir, DXDY, X, XNext, DY, D, XA, XB, X0F, X1F, A0, A1, A2, AM, S: Double;
  Y, YStart, YEnd, Line, XI0, XI1, XI: Integer;

  procedure Add(Index: Integer; V: Double); inline;
  begin
    if (Index >= 0) and (Index < Length(R.Acc)) then
      R.Acc[Index] := R.Acc[Index] + V;
  end;

begin
  if Y0 = Y1 then
    Exit;
  if Y0 < Y1 then
    Dir := 1
  else
  begin
    Dir := -1;
    X := X0; X0 := X1; X1 := X;
    X := Y0; Y0 := Y1; Y1 := X;
  end;
  DXDY := (X1 - X0) / (Y1 - Y0);
  X := X0;
  if Y0 < 0 then
  begin
    X := X - Y0 * DXDY;
    YStart := 0;
  end
  else
    YStart := Trunc(Y0);
  YEnd := Min(R.H, Ceil(Y1));
  for Y := YStart to YEnd - 1 do
  begin
    Line := Y * R.W;
    DY := Min(Y + 1, Y1) - Max(Y, Y0);
    XNext := X + DXDY * DY;
    D := DY * Dir;
    if X < XNext then begin XA := X; XB := XNext; end else begin XA := XNext; XB := X; end;
    XA := EnsureRange(XA, 0, R.W - 2);
    XB := EnsureRange(XB, 0, R.W - 2);
    XI0 := Floor(XA);
    XI1 := Ceil(XB);
    if XI1 <= XI0 + 1 then
    begin
      AM := 0.5 * (EnsureRange(X, 0, R.W - 2) + EnsureRange(XNext, 0, R.W - 2)) - XI0;
      Add(Line + XI0, D - D * AM);
      Add(Line + XI0 + 1, D * AM);
    end
    else
    begin
      S := 1 / (XB - XA);
      X0F := XA - XI0;
      A0 := 0.5 * S * Sqr(1 - X0F);
      X1F := XB - XI1 + 1;
      AM := 0.5 * S * Sqr(X1F);
      Add(Line + XI0, D * A0);
      if XI1 = XI0 + 2 then
        Add(Line + XI0 + 1, D * (1 - A0 - AM))
      else
      begin
        A1 := S * (1.5 - X0F);
        Add(Line + XI0 + 1, D * (A1 - A0));
        for XI := XI0 + 2 to XI1 - 2 do
          Add(Line + XI, D * S);
        A2 := A1 + (XI1 - XI0 - 3) * S;
        Add(Line + XI1 - 1, D * (1 - A2 - AM));
      end;
      Add(Line + XI1, D * AM);
    end;
    X := XNext;
  end;
end;

procedure TTrueTypeFont.Render(Glyph: Integer; Scale: Double; Embolden: Boolean; out Bitmap: TTrueTypeBitmap);
var
  Contours: TContours;
  M: TMatrix;
  I, J, K, N, X0, Y0, X1, Y1, Grow, Row, Col: Integer;
  MinX, MinY, MaxX, MaxY, PX, PY, Len, Sum: Double;
  R: TRaster;
  Pts, E: TPtArray;
  M2: Integer;
  Cov, Wide: array of Byte;
  V: Integer;

  procedure LineTo(X, Y: Double);
  begin
    RasterLine(R, PX - X0, Y0 - PY, X - X0, Y0 - Y);
    PX := X;
    PY := Y;
  end;

  procedure QuadTo(QX, QY, X, Y: Double);
  var
    S, Count: Integer;
    TT, A, B: Double;
  begin
    Len := Hypot(QX - PX, QY - PY) + Hypot(X - QX, Y - QY);
    Count := EnsureRange(Round(Sqrt(Len) * 1.5), 2, 32);
    A := PX;
    B := PY;
    for S := 1 to Count do
    begin
      TT := S / Count;
      LineTo(Sqr(1 - TT) * A + 2 * (1 - TT) * TT * QX + TT * TT * X,
        Sqr(1 - TT) * B + 2 * (1 - TT) * TT * QY + TT * TT * Y);
    end;
  end;

begin
  Bitmap.Width := 0;
  Bitmap.Height := 0;
  Bitmap.Left := 0;
  Bitmap.Top := 0;
  Bitmap.Bits := nil;
  Grow := 0;
  if Embolden then
    Grow := Max(1, Round(FUnitsPerEm * Scale / 24));
  Bitmap.Advance := Round(AdvanceWidth(Glyph) * Scale) + Grow;
  M.A := Scale; M.B := 0; M.C := 0; M.D := Scale; M.E := 0; M.F := 0;
  Contours := nil;
  GetOutline(Self, Glyph, M, Contours, 0);
  if Length(Contours) = 0 then
    Exit;
  MinX := MaxDouble; MinY := MaxDouble; MaxX := -MaxDouble; MaxY := -MaxDouble;
  for I := 0 to High(Contours) do
    for J := 0 to High(Contours[I]) do
    begin
      MinX := Min(MinX, Contours[I][J].X);
      MaxX := Max(MaxX, Contours[I][J].X);
      MinY := Min(MinY, Contours[I][J].Y);
      MaxY := Max(MaxY, Contours[I][J].Y);
    end;
  X0 := Floor(MinX);
  X1 := Ceil(MaxX);
  Y0 := Ceil(MaxY);       { the top row, in y-up units }
  Y1 := Floor(MinY);
  if (X1 <= X0) or (Y0 <= Y1) then
    Exit;
  R.W := X1 - X0 + 2;
  R.H := Y0 - Y1;
  SetLength(R.Acc, R.W * R.H + 2);
  for I := 0 to High(Contours) do
  begin
    Pts := Contours[I];
    N := Length(Pts);
    if N < 2 then
      Continue;
    { between two control points there is a point on the curve halfway }
    SetLength(E, 0);
    for J := 0 to N - 1 do
    begin
      SetLength(E, Length(E) + 1);
      E[High(E)] := Pts[J];
      if not Pts[J].OnCurve and not Pts[(J + 1) mod N].OnCurve then
      begin
        SetLength(E, Length(E) + 1);
        E[High(E)].X := (Pts[J].X + Pts[(J + 1) mod N].X) / 2;
        E[High(E)].Y := (Pts[J].Y + Pts[(J + 1) mod N].Y) / 2;
        E[High(E)].OnCurve := True;
      end;
    end;
    { start on a point on the curve }
    M2 := Length(E);
    K := 0;
    while (K < M2) and not E[K].OnCurve do
      Inc(K);
    if K >= M2 then
      Continue;
    PX := E[K].X;
    PY := E[K].Y;
    J := 1;
    while J <= M2 do
    begin
      if E[(K + J) mod M2].OnCurve then
      begin
        LineTo(E[(K + J) mod M2].X, E[(K + J) mod M2].Y);
        Inc(J);
      end
      else
      begin
        QuadTo(E[(K + J) mod M2].X, E[(K + J) mod M2].Y, E[(K + J + 1) mod M2].X, E[(K + J + 1) mod M2].Y);
        Inc(J, 2);
      end;
    end;
  end;
  { the coverage: the running sum of each row }
  SetLength(Cov, (R.W - 1) * R.H);
  for Row := 0 to R.H - 1 do
  begin
    Sum := 0;
    for Col := 0 to R.W - 2 do
    begin
      Sum := Sum + R.Acc[Row * R.W + Col];
      V := Round(Min(1, Abs(Sum)) * 255);
      Cov[Row * (R.W - 1) + Col] := V;
    end;
  end;
  Bitmap.Width := R.W - 1;
  Bitmap.Height := R.H;
  Bitmap.Left := X0;
  Bitmap.Top := Y0;
  if Grow > 0 then
  begin
    { thicker strokes: each pixel takes the strongest of its row neighbours to the left }
    SetLength(Wide, (Bitmap.Width + Grow) * Bitmap.Height);
    for Row := 0 to Bitmap.Height - 1 do
      for Col := 0 to Bitmap.Width + Grow - 1 do
      begin
        V := 0;
        for K := Max(0, Col - Grow) to Min(Bitmap.Width - 1, Col) do
          V := Max(V, Cov[Row * Bitmap.Width + K]);
        Wide[Row * (Bitmap.Width + Grow) + Col] := V;
      end;
    Cov := Wide;
    Inc(Bitmap.Width, Grow);
  end;
  Bitmap.Bits := Cov;
end;

end.
