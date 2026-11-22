{ Pastel - QR codes and barcodes: made (drawn) by Pastel, for screens, labels and reports.

    object Code: TBarcode
      Kind = bkQR
      Text = 'https://pastel.dev/order/1042'
    end

    Q := QrEncode('WIFI:S:Salon;T:WPA;P:secret;;');      // the modules, Q.Size x Q.Size
    SaveBarcodePng('label.png', '8690000000001', bkEAN13, 4);
    B := BarcodeBitmap('ORD-1042', bkCode128, 3);        // TBitmap32, for a report or a TImage

  QR codes (ISO/IEC 18004: every version, the four error correction levels, the
  best mask), Code 128 (letters and digits; digits in pairs, shorter) and EAN-13
  (the check digit added or checked).
  Part of the Pastel project, MIT License. }
unit Pastel.Barcode;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Pastel.Graphics, Pastel.UI;

type
  TBarcodeKind = (bkQR, bkCode128, bkEAN13);
  { how much of a QR code may be damaged and still read: 7, 15, 25, 30 % }
  TQrLevel = (qlLow, qlMedium, qlQuartile, qlHigh);

  TQrCode = record
    Size: Integer;
    Version: Integer;
    Modules: array of Boolean;      { Size * Size, row by row; True: dark }
    function Dark(X, Y: Integer): Boolean;
  end;

  EBarcodeError = class(Exception);

{ The text as UTF-8 bytes, in the smallest version that holds it. }
function QrEncode(const Text: string; Level: TQrLevel = qlMedium): TQrCode;
{ Bars and spaces as widths in modules (starting with a bar), and the text shown under them. }
function Code128Widths(const Text: string): TBytes;
function Ean13Widths(const Digits: string; out Shown: string): TBytes;
{ The code as a picture: Scale pixels a module, a quiet zone around. }
function BarcodeBitmap(const Text: string; Kind: TBarcodeKind; Scale: Integer = 4; Level: TQrLevel = qlMedium): TBitmap32;
procedure SaveBarcodePng(const FileName, Text: string; Kind: TBarcodeKind; Scale: Integer = 4; Level: TQrLevel = qlMedium);

type
  TBarcode = class(TControl)
  private
    FText: string;
    FKind: TBarcodeKind;
    FLevel: TQrLevel;
    FColor, FBackColor: TColor32;
    FShowText: Boolean;
    FCacheKey: string;
    FQr: TQrCode;
    FBars: TBytes;
    FShown, FError: string;
    procedure SetText(const AValue: string);
    procedure SetKind(AValue: TBarcodeKind);
    procedure SetLevel(AValue: TQrLevel);
    procedure Prepare;
  protected
    procedure Measure(AvailWidth: Integer; out W, H: Integer); override;
    procedure Paint(C: TCanvas32); override;
  public
    constructor Create(AOwner: TComponent); override;
    { '' or why the text cannot be this kind of code }
    function Error: string;
  published
    property Text: string read FText write SetText;
    property Kind: TBarcodeKind read FKind write SetKind default bkQR;
    property Level: TQrLevel read FLevel write SetLevel default qlMedium;
    property Color: TColor32 read FColor write FColor default $FF000000;
    property BackColor: TColor32 read FBackColor write FBackColor default $FFFFFFFF;
    { the digits under a barcode }
    property ShowText: Boolean read FShowText write FShowText default True;
  end;

implementation

uses
  Math;

{ ---------------- QR ---------------- }

const
  { error correction codewords per block, [level, version] }
  EccPerBlock: array[TQrLevel, 1..40] of Byte = (
    (7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30),
    (10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28),
    (13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30),
    (17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30));
  { number of error correction blocks, [level, version] }
  EccBlocks: array[TQrLevel, 1..40] of Byte = (
    (1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25),
    (1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49),
    (1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68),
    (1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81));
  LevelBits: array[TQrLevel] of Integer = (1, 0, 3, 2);

type
  TInts = array of Integer;
  TGrid = record
    Size: Integer;
    M: array of Boolean;
    Fixed: array of Boolean;     { function patterns: masks leave them }
  end;

function TQrCode.Dark(X, Y: Integer): Boolean;
begin
  Result := (X >= 0) and (Y >= 0) and (X < Size) and (Y < Size) and Modules[Y * Size + X];
end;

function RawModules(Ver: Integer): Integer;
var
  N: Integer;
begin
  Result := (16 * Ver + 128) * Ver + 64;
  if Ver >= 2 then
  begin
    N := Ver div 7 + 2;
    Result := Result - (25 * N - 10) * N + 55;
    if Ver >= 7 then
      Result := Result - 36;
  end;
end;

function DataCodewords(Ver: Integer; L: TQrLevel): Integer;
begin
  Result := RawModules(Ver) div 8 - EccPerBlock[L, Ver] * EccBlocks[L, Ver];
end;

{ GF(256) with the polynomial 0x11D }
function GfMul(X, Y: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 7 downto 0 do
  begin
    Result := (Result shl 1) xor ((Result shr 7) * $11D);
    Result := Result xor (((Y shr I) and 1) * X);
  end;
end;

function RsDivisor(Degree: Integer): TBytes;
var
  Root, I, J: Integer;
begin
  Result := nil;
  SetLength(Result, Degree);
  FillChar(Result[0], Degree, 0);
  Result[Degree - 1] := 1;
  Root := 1;
  for I := 0 to Degree - 1 do
  begin
    for J := 0 to Degree - 1 do
    begin
      Result[J] := GfMul(Result[J], Root);
      if J + 1 < Degree then
        Result[J] := Result[J] xor Result[J + 1];
    end;
    Root := GfMul(Root, 2);
  end;
end;

function RsRemainder(const Data: TBytes; const Divisor: TBytes): TBytes;
var
  B, I: Integer;
  Factor: Integer;
begin
  Result := nil;
  SetLength(Result, Length(Divisor));
  FillChar(Result[0], Length(Result), 0);
  for B in Data do
  begin
    Factor := B xor Result[0];
    Move(Result[1], Result[0], Length(Result) - 1);
    Result[High(Result)] := 0;
    for I := 0 to High(Result) do
      Result[I] := Result[I] xor GfMul(Divisor[I], Factor);
  end;
end;

procedure SetM(var G: TGrid; X, Y: Integer; Dark: Boolean);
begin
  G.M[Y * G.Size + X] := Dark;
  G.Fixed[Y * G.Size + X] := True;
end;

procedure Finder(var G: TGrid; CX, CY: Integer);
var
  DX, DY, D, X, Y: Integer;
begin
  for DY := -4 to 4 do
    for DX := -4 to 4 do
    begin
      X := CX + DX;
      Y := CY + DY;
      if (X < 0) or (Y < 0) or (X >= G.Size) or (Y >= G.Size) then
        Continue;
      D := Max(Abs(DX), Abs(DY));
      SetM(G, X, Y, (D <> 2) and (D <> 4));
    end;
end;

procedure Alignment(var G: TGrid; CX, CY: Integer);
var
  DX, DY: Integer;
begin
  for DY := -2 to 2 do
    for DX := -2 to 2 do
      SetM(G, CX + DX, CY + DY, Max(Abs(DX), Abs(DY)) <> 1);
end;

function AlignmentPositions(Ver: Integer): TInts;
var
  N, Step, I, Pos_: Integer;
begin
  Result := nil;
  if Ver = 1 then
    Exit;
  N := Ver div 7 + 2;
  if Ver = 32 then
    Step := 26
  else
    Step := ((Ver * 4 + N * 2 + 1) div (N * 2 - 2)) * 2;
  SetLength(Result, N);
  Result[0] := 6;
  Pos_ := Ver * 4 + 10;
  for I := N - 1 downto 1 do
  begin
    Result[I] := Pos_;
    Dec(Pos_, Step);
  end;
end;

procedure FormatBits(var G: TGrid; L: TQrLevel; Mask: Integer);
var
  Data, Rem, Bits, I: Integer;
  function Bit(I: Integer): Boolean;
  begin
    Result := ((Bits shr I) and 1) <> 0;
  end;
begin
  Data := (LevelBits[L] shl 3) or Mask;
  Rem := Data;
  for I := 0 to 9 do
    Rem := (Rem shl 1) xor ((Rem shr 9) * $537);
  Bits := ((Data shl 10) or Rem) xor $5412;
  for I := 0 to 5 do
    SetM(G, 8, I, Bit(I));
  SetM(G, 8, 7, Bit(6));
  SetM(G, 8, 8, Bit(7));
  SetM(G, 7, 8, Bit(8));
  for I := 9 to 14 do
    SetM(G, 14 - I, 8, Bit(I));
  for I := 0 to 7 do
    SetM(G, G.Size - 1 - I, 8, Bit(I));
  for I := 8 to 14 do
    SetM(G, 8, G.Size - 15 + I, Bit(I));
  SetM(G, 8, G.Size - 8, True);
end;

procedure VersionBits(var G: TGrid; Ver: Integer);
var
  Rem, Bits, I, A, B: Integer;
begin
  if Ver < 7 then
    Exit;
  Rem := Ver;
  for I := 0 to 11 do
    Rem := (Rem shl 1) xor ((Rem shr 11) * $1F25);
  Bits := (Ver shl 12) or Rem;
  for I := 0 to 17 do
  begin
    A := G.Size - 11 + I mod 3;
    B := I div 3;
    SetM(G, A, B, ((Bits shr I) and 1) <> 0);
    SetM(G, B, A, ((Bits shr I) and 1) <> 0);
  end;
end;

procedure FunctionPatterns(var G: TGrid; Ver: Integer; L: TQrLevel);
var
  I, J: Integer;
  P: TInts;
begin
  for I := 0 to G.Size - 1 do
  begin
    SetM(G, 6, I, I mod 2 = 0);
    SetM(G, I, 6, I mod 2 = 0);
  end;
  Finder(G, 3, 3);
  Finder(G, G.Size - 4, 3);
  Finder(G, 3, G.Size - 4);
  P := AlignmentPositions(Ver);
  for I := 0 to High(P) do
    for J := 0 to High(P) do
      if not (((I = 0) and (J = 0)) or ((I = 0) and (J = High(P))) or ((I = High(P)) and (J = 0))) then
        Alignment(G, P[I], P[J]);
  FormatBits(G, L, 0);      { reserves the places; set again with the mask }
  VersionBits(G, Ver);
end;

procedure PlaceData(var G: TGrid; const Data: TBytes);
var
  I, Right, Vert, J, X, Y: Integer;
  Upward: Boolean;
begin
  I := 0;
  Right := G.Size - 1;
  while Right >= 1 do
  begin
    if Right = 6 then
      Right := 5;
    for Vert := 0 to G.Size - 1 do
      for J := 0 to 1 do
      begin
        X := Right - J;
        Upward := ((Right + 1) and 2) = 0;
        if Upward then
          Y := G.Size - 1 - Vert
        else
          Y := Vert;
        if not G.Fixed[Y * G.Size + X] and (I < Length(Data) * 8) then
        begin
          G.M[Y * G.Size + X] := ((Data[I shr 3] shr (7 - (I and 7))) and 1) <> 0;
          Inc(I);
        end;
      end;
    Dec(Right, 2);
  end;
end;

procedure ApplyMask(var G: TGrid; Mask: Integer);
var
  X, Y: Integer;
  Inv: Boolean;
begin
  for Y := 0 to G.Size - 1 do
    for X := 0 to G.Size - 1 do
    begin
      case Mask of
        0: Inv := (X + Y) mod 2 = 0;
        1: Inv := Y mod 2 = 0;
        2: Inv := X mod 3 = 0;
        3: Inv := (X + Y) mod 3 = 0;
        4: Inv := (X div 3 + Y div 2) mod 2 = 0;
        5: Inv := X * Y mod 2 + X * Y mod 3 = 0;
        6: Inv := (X * Y mod 2 + X * Y mod 3) mod 2 = 0;
      else
        Inv := ((X + Y) mod 2 + X * Y mod 3) mod 2 = 0;
      end;
      if Inv and not G.Fixed[Y * G.Size + X] then
        G.M[Y * G.Size + X] := not G.M[Y * G.Size + X];
    end;
end;

{ the standard's penalty: lower is easier to read }
function Penalty(const G: TGrid): Integer;
var
  X, Y, Run, Dark, I, K: Integer;
  Color: Boolean;

  function At(X, Y: Integer): Boolean; inline;
  begin
    Result := G.M[Y * G.Size + X];
  end;

  function FinderLike(Horizontal: Boolean; A, B: Integer): Boolean;
  const
    Pat: array[0..10] of Boolean = (True, False, True, True, True, False, True, False, False, False, False);
  var
    I: Integer;
    Fwd, Back: Boolean;
  begin
    Fwd := True;
    Back := True;
    for I := 0 to 10 do
    begin
      if Horizontal then
      begin
        if At(A + I, B) <> Pat[I] then Fwd := False;
        if At(A + I, B) <> Pat[10 - I] then Back := False;
      end
      else
      begin
        if At(B, A + I) <> Pat[I] then Fwd := False;
        if At(B, A + I) <> Pat[10 - I] then Back := False;
      end;
    end;
    Result := Fwd or Back;
  end;

begin
  Result := 0;
  { runs of five or more }
  for Y := 0 to G.Size - 1 do
  begin
    Run := 1;
    for X := 1 to G.Size do
      if (X < G.Size) and (At(X, Y) = At(X - 1, Y)) then
        Inc(Run)
      else
      begin
        if Run >= 5 then
          Inc(Result, Run - 2);
        Run := 1;
      end;
  end;
  for X := 0 to G.Size - 1 do
  begin
    Run := 1;
    for Y := 1 to G.Size do
      if (Y < G.Size) and (At(X, Y) = At(X, Y - 1)) then
        Inc(Run)
      else
      begin
        if Run >= 5 then
          Inc(Result, Run - 2);
        Run := 1;
      end;
  end;
  { 2 x 2 blocks }
  for Y := 0 to G.Size - 2 do
    for X := 0 to G.Size - 2 do
    begin
      Color := At(X, Y);
      if (At(X + 1, Y) = Color) and (At(X, Y + 1) = Color) and (At(X + 1, Y + 1) = Color) then
        Inc(Result, 3);
    end;
  { finder-like patterns }
  for Y := 0 to G.Size - 1 do
    for X := 0 to G.Size - 11 do
    begin
      if FinderLike(True, X, Y) then
        Inc(Result, 40);
      if FinderLike(False, X, Y) then
        Inc(Result, 40);
    end;
  { the balance of dark and light }
  Dark := 0;
  for I := 0 to High(G.M) do
    if G.M[I] then
      Inc(Dark);
  K := (Abs(Dark * 20 - Length(G.M) * 10) + Length(G.M) - 1) div Length(G.M) - 1;
  Inc(Result, Max(0, K) * 10);
end;

function QrEncode(const Text: string; Level: TQrLevel): TQrCode;
var
  Bytes: RawByteString;
  Ver, CapBits, CountBits, I, J, K, NBlocks, BlockEcc, Raw, ShortLen, NShort, Pos_, Best, BestMask, P: Integer;
  Bits: array of Boolean;
  Data, Ecc, Final: TBytes;
  Blocks: array of TBytes;
  Divisor: TBytes;
  G, Trial: TGrid;

  procedure AddBits(Value, Count: Integer);
  var
    I: Integer;
  begin
    for I := Count - 1 downto 0 do
    begin
      SetLength(Bits, Length(Bits) + 1);
      Bits[High(Bits)] := ((Value shr I) and 1) <> 0;
    end;
  end;

begin
  Bytes := UTF8Encode(UTF8Decode(Text));
  { the smallest version (byte mode) }
  Ver := 0;
  for I := 1 to 40 do
  begin
    if I < 10 then CountBits := 8 else CountBits := 16;
    if 4 + CountBits + Length(Bytes) * 8 <= DataCodewords(I, Level) * 8 then
    begin
      Ver := I;
      Break;
    end;
  end;
  if Ver = 0 then
    raise EBarcodeError.CreateFmt('the text is too long for a QR code (%d bytes)', [Length(Bytes)]);
  if Ver < 10 then CountBits := 8 else CountBits := 16;
  Bits := nil;
  AddBits(4, 4);
  AddBits(Length(Bytes), CountBits);
  for I := 1 to Length(Bytes) do
    AddBits(Ord(Bytes[I]), 8);
  CapBits := DataCodewords(Ver, Level) * 8;
  AddBits(0, Min(4, CapBits - Length(Bits)));
  AddBits(0, (8 - Length(Bits) mod 8) mod 8);
  I := 0;
  while Length(Bits) < CapBits do
  begin
    if I mod 2 = 0 then AddBits($EC, 8) else AddBits($11, 8);
    Inc(I);
  end;
  SetLength(Data, Length(Bits) div 8);
  for I := 0 to High(Data) do
  begin
    Data[I] := 0;
    for J := 0 to 7 do
      if Bits[I * 8 + J] then
        Data[I] := Data[I] or (1 shl (7 - J));
  end;
  { blocks with their error correction, interleaved }
  NBlocks := EccBlocks[Level, Ver];
  BlockEcc := EccPerBlock[Level, Ver];
  Raw := RawModules(Ver) div 8;
  NShort := NBlocks - Raw mod NBlocks;
  ShortLen := Raw div NBlocks;
  Divisor := RsDivisor(BlockEcc);
  SetLength(Blocks, NBlocks);
  Pos_ := 0;
  for I := 0 to NBlocks - 1 do
  begin
    K := ShortLen - BlockEcc + Ord(I >= NShort);
    Blocks[I] := Copy(Data, Pos_, K);
    Inc(Pos_, K);
    Ecc := RsRemainder(Blocks[I], Divisor);
    if I < NShort then
    begin
      { short blocks get a hole, so the columns line up }
      SetLength(Blocks[I], Length(Blocks[I]) + 1);
      Blocks[I][High(Blocks[I])] := 0;
    end;
    Blocks[I] := Concat(Blocks[I], Ecc);
  end;
  Final := nil;
  for J := 0 to ShortLen do
    for I := 0 to NBlocks - 1 do
      if (J <> ShortLen - BlockEcc) or (I >= NShort) then
      begin
        SetLength(Final, Length(Final) + 1);
        Final[High(Final)] := Blocks[I][J];
      end;
  { the grid, the best of the eight masks }
  G.Size := Ver * 4 + 17;
  SetLength(G.M, G.Size * G.Size);
  SetLength(G.Fixed, G.Size * G.Size);
  for I := 0 to High(G.M) do
  begin
    G.M[I] := False;
    G.Fixed[I] := False;
  end;
  FunctionPatterns(G, Ver, Level);
  PlaceData(G, Final);
  Best := MaxInt;
  BestMask := 0;
  for K := 0 to 7 do
  begin
    Trial := G;
    Trial.M := Copy(G.M);
    Trial.Fixed := Copy(G.Fixed);
    ApplyMask(Trial, K);
    FormatBits(Trial, Level, K);
    P := Penalty(Trial);
    if P < Best then
    begin
      Best := P;
      BestMask := K;
    end;
  end;
  ApplyMask(G, BestMask);
  FormatBits(G, Level, BestMask);
  Result.Size := G.Size;
  Result.Version := Ver;
  Result.Modules := G.M;
end;

{ ---------------- Code 128 ---------------- }

const
  Code128Patterns: array[0..106] of string[7] = (
    '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213',
    '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
    '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
    '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
    '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
    '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
    '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
    '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
    '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
    '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
    '114131', '311141', '411131', '211412', '211214', '211232', '2331112');

function Code128Widths(const Text: string): TBytes;
var
  Codes: array of Integer;
  I, Sum, C, N: Integer;
  InSetC: Boolean;
  S: string;

  procedure Add(V: Integer);
  begin
    SetLength(Codes, Length(Codes) + 1);
    Codes[High(Codes)] := V;
  end;

  function DigitRun(P: Integer): Integer;
  var
    K: Integer;
  begin
    K := 0;
    while (P + K <= Length(Text)) and (Text[P + K] in ['0'..'9']) do
      K := K + 1;
    Result := K;
  end;

begin
  if Text = '' then
    raise EBarcodeError.Create('a Code 128 barcode needs some text');
  for I := 1 to Length(Text) do
    if (Text[I] < ' ') or (Text[I] > '~') then
      raise EBarcodeError.CreateFmt('Code 128 here takes letters, digits and signs (ASCII), not "%s"', [Text[I]]);
  Codes := nil;
  { set C (two digits a code) for a run of digits worth it, else B }
  I := 1;
  N := DigitRun(1);
  InSetC := (N >= 4) and (N mod 2 = 0) or (N = Length(Text)) and (N >= 2) and (N mod 2 = 0);
  if InSetC then Add(105) else Add(104);
  while I <= Length(Text) do
  begin
    if InSetC then
    begin
      if DigitRun(I) >= 2 then
      begin
        Add(StrToInt(Copy(Text, I, 2)));
        Inc(I, 2);
        Continue;
      end;
      Add(100);       { to B }
      InSetC := False;
    end;
    N := DigitRun(I);
    if (N >= 6) or (N >= 4) and (I + N - 1 = Length(Text)) then
    begin
      if N mod 2 = 1 then
      begin
        Add(Ord(Text[I]) - 32);
        Inc(I);
      end;
      Add(99);        { to C }
      InSetC := True;
      Continue;
    end;
    Add(Ord(Text[I]) - 32);
    Inc(I);
  end;
  Sum := Codes[0];
  for I := 1 to High(Codes) do
    Inc(Sum, Codes[I] * I);
  Add(Sum mod 103);
  Add(106);
  Result := nil;
  for C in Codes do
  begin
    S := Code128Patterns[C];
    for I := 1 to Length(S) do
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Ord(S[I]) - Ord('0');
    end;
  end;
end;

{ ---------------- EAN-13 ---------------- }

const
  EanL: array[0..9] of string[4] = ('3211', '2221', '2122', '1411', '1132', '1231', '1114', '1312', '1213', '3112');
  EanParity: array[0..9] of string[6] = ('LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG',
    'LGLGGL', 'LGGLGL');

function Ean13Widths(const Digits: string; out Shown: string): TBytes;
var
  D: string;
  I, Sum, Check: Integer;
  P: string;

  procedure Add(const W: string; Reverse: Boolean);
  var
    K: Integer;
  begin
    for K := 1 to Length(W) do
    begin
      SetLength(Result, Length(Result) + 1);
      if Reverse then
        Result[High(Result)] := Ord(W[Length(W) - K + 1]) - Ord('0')
      else
        Result[High(Result)] := Ord(W[K]) - Ord('0');
    end;
  end;

begin
  D := Trim(Digits);
  for I := 1 to Length(D) do
    if not (D[I] in ['0'..'9']) then
      raise EBarcodeError.Create('an EAN-13 barcode is made of digits');
  if not (Length(D) in [12, 13]) then
    raise EBarcodeError.Create('an EAN-13 barcode has 12 digits (and the check digit)');
  Sum := 0;
  for I := 1 to 12 do
    if I mod 2 = 0 then Inc(Sum, 3 * (Ord(D[I]) - 48)) else Inc(Sum, Ord(D[I]) - 48);
  Check := (10 - Sum mod 10) mod 10;
  if Length(D) = 13 then
  begin
    if Ord(D[13]) - 48 <> Check then
      raise EBarcodeError.CreateFmt('the check digit of %s is wrong (it is %d)', [D, Check]);
  end
  else
    D := D + IntToStr(Check);
  Shown := D;
  Result := nil;
  { the first digit is in the parity of the left six; widths start with a bar }
  Add('111', False);
  P := EanParity[Ord(D[1]) - 48];
  for I := 2 to 7 do
  begin
    { L: space bar space bar; G: the R pattern backwards }
    if P[I - 1] = 'L' then
      Add(EanL[Ord(D[I]) - 48], False)
    else
      Add(EanL[Ord(D[I]) - 48], True);
  end;
  Add('11111', False);
  for I := 8 to 13 do
    Add(EanL[Ord(D[I]) - 48], False);
  Add('111', False);
end;

{ ---------------- pictures ---------------- }

function BarcodeBitmap(const Text: string; Kind: TBarcodeKind; Scale: Integer; Level: TQrLevel): TBitmap32;
var
  Q: TQrCode;
  W: TBytes;
  Shown: string;
  X, Y, I, J, Total, Pos_, H: Integer;
  Dark: Boolean;
begin
  Scale := Max(1, Scale);
  Result := TBitmap32.Create;
  try
    if Kind = bkQR then
    begin
      Q := QrEncode(Text, Level);
      Result.SetSize((Q.Size + 8) * Scale, (Q.Size + 8) * Scale);
      for Y := 0 to Result.Height - 1 do
        for X := 0 to Result.Width - 1 do
          if Q.Dark(X div Scale - 4, Y div Scale - 4) then
            Result.Pixels[Y * Result.Width + X] := $FF000000
          else
            Result.Pixels[Y * Result.Width + X] := $FFFFFFFF;
      Exit;
    end;
    if Kind = bkCode128 then
      W := Code128Widths(Text)
    else
      W := Ean13Widths(Text, Shown);
    Total := 20;
    for I := 0 to High(W) do
      Inc(Total, W[I]);
    H := 50 * Scale;
    Result.SetSize(Total * Scale, H);
    for I := 0 to High(Result.Pixels) do
      Result.Pixels[I] := $FFFFFFFF;
    Pos_ := 10;
    for I := 0 to High(W) do
    begin
      Dark := I mod 2 = 0;
      if Dark then
        for J := Pos_ * Scale to (Pos_ + W[I]) * Scale - 1 do
          for Y := 0 to H - 1 do
            Result.Pixels[Y * Result.Width + J] := $FF000000;
      Inc(Pos_, W[I]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure SaveBarcodePng(const FileName, Text: string; Kind: TBarcodeKind; Scale: Integer; Level: TQrLevel);
var
  B: TBitmap32;
  C: TCanvas32;
begin
  B := BarcodeBitmap(Text, Kind, Scale, Level);
  C := TCanvas32.Create;
  try
    C.SetSize(B.Width, B.Height);
    C.DrawBitmap(B, 0, 0, B.Width, B.Height, False);
    C.SaveToPNG(FileName);
  finally
    C.Free;
    B.Free;
  end;
end;

{ ---------------- TBarcode ---------------- }

constructor TBarcode.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := bkQR;
  FLevel := qlMedium;
  FColor := $FF000000;
  FBackColor := $FFFFFFFF;
  FShowText := True;
end;

procedure TBarcode.SetText(const AValue: string);
begin
  FText := AValue;
  Changed;
end;

procedure TBarcode.SetKind(AValue: TBarcodeKind);
begin
  FKind := AValue;
  Changed;
end;

procedure TBarcode.SetLevel(AValue: TQrLevel);
begin
  FLevel := AValue;
  Changed;
end;

procedure TBarcode.Prepare;
var
  Key: string;
begin
  Key := IntToStr(Ord(FKind)) + IntToStr(Ord(FLevel)) + FText;
  if Key = FCacheKey then
    Exit;
  FCacheKey := Key;
  FError := '';
  FBars := nil;
  FQr.Size := 0;
  FShown := FText;
  if FText = '' then
    Exit;
  try
    case FKind of
      bkQR: FQr := QrEncode(FText, FLevel);
      bkCode128: FBars := Code128Widths(FText);
      bkEAN13: FBars := Ean13Widths(FText, FShown);
    end;
  except
    on E: Exception do
      FError := E.Message;
  end;
end;

function TBarcode.Error: string;
begin
  Prepare;
  Result := FError;
end;

procedure TBarcode.Measure(AvailWidth: Integer; out W, H: Integer);
begin
  if FKind = bkQR then
  begin
    W := Min(AvailWidth, 160);
    H := W;
  end
  else
  begin
    W := Min(AvailWidth, 260);
    H := 90;
  end;
end;

procedure TBarcode.Paint(C: TCanvas32);
var
  F: TPastelFont;
  Total, I, X, Y, M, OX, OY, TextH, Pos_: Integer;
  Unit_: Single;
begin
  Prepare;
  C.FillRect(Bounds.X, Bounds.Y, Bounds.W, Bounds.H, FBackColor);
  F := GetFont(Theme.FontSize);
  if FError <> '' then
  begin
    C.PushClip(Bounds);
    C.DrawText(F, Bounds.X + 4, Bounds.Y + 4, FError, Theme.Danger);
    C.PopClip;
    Exit;
  end;
  if FKind = bkQR then
  begin
    if FQr.Size = 0 then
      Exit;
    { whole modules and a quiet zone of 2: sharp at any size }
    M := Max(1, Min(Bounds.W, Bounds.H) div (FQr.Size + 4));
    OX := Bounds.X + (Bounds.W - M * FQr.Size) div 2;
    OY := Bounds.Y + (Bounds.H - M * FQr.Size) div 2;
    for Y := 0 to FQr.Size - 1 do
      for X := 0 to FQr.Size - 1 do
        if FQr.Dark(X, Y) then
          C.FillRect(OX + X * M, OY + Y * M, M, M, FColor);
    Exit;
  end;
  if Length(FBars) = 0 then
    Exit;
  Total := 20;
  for I := 0 to High(FBars) do
    Inc(Total, FBars[I]);
  Unit_ := Bounds.W / Total;
  if FShowText then TextH := F.LineHeight else TextH := 0;
  Pos_ := 10;
  for I := 0 to High(FBars) do
  begin
    if I mod 2 = 0 then
      C.FillRect(Bounds.X + Round(Pos_ * Unit_), Bounds.Y + 4,
        Max(1, Round((Pos_ + FBars[I]) * Unit_) - Round(Pos_ * Unit_)), Bounds.H - 8 - TextH, FColor);
    Inc(Pos_, FBars[I]);
  end;
  if FShowText then
    C.DrawText(F, Bounds.X + (Bounds.W - F.TextWidth(FShown)) div 2, Bounds.Y + Bounds.H - TextH - 2, FShown, FColor);
end;

initialization
  RegisterControl(TBarcode);
end.
