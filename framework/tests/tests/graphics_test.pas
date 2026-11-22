{ Tests of the canvas (Pastel.Graphics): the quick ways of drawing give the
  same pixels as working out every pixel, and a full window is quick. }
unit graphics_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Grids;

type
  TGraphicsTests = class(TTestSuite)
  published
    procedure RoundedRectanglesAreExact;
    procedure SeeThroughFillsAreExact;
    procedure TextIsClipped;
    procedure ScaledPicturesKeepTheirColors;
    procedure AFullWindowIsQuick;
  end;

implementation

{ ---- the plain way: every pixel on its own (what the canvas did before) ---- }

function Dist(PX, PY, X, Y, W, H, R: Single): Single;
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

function Cover(D: Single): Integer;
begin
  if D <= -0.5 then
    Result := 255
  else if D >= 0.5 then
    Result := 0
  else
    Result := Round((0.5 - D) * 255);
end;

function BlendOne(D, C: Cardinal; Coverage: Integer): Cardinal;
var
  A, IA: Cardinal;
begin
  A := ((C shr 24) * Cardinal(Coverage) + 127) div 255;
  if A = 0 then
    Exit(D);
  if A >= 255 then
    Exit(C or $FF000000);
  IA := 255 - A;
  Result := $FF000000 or
    (((((C shr 16) and $FF) * A + ((D shr 16) and $FF) * IA) div 255) shl 16) or
    (((((C shr 8) and $FF) * A + ((D shr 8) and $FF) * IA) div 255) shl 8) or
    ((((C and $FF) * A + (D and $FF) * IA) div 255));
end;

type
  TPixels = array of Cardinal;

{ a background with something different in every pixel }
procedure Stripes(C: TCanvas32; W, H: Integer; out Ref: TPixels);
var
  X, Y: Integer;
  P: Cardinal;
begin
  C.SetSize(W, H);
  SetLength(Ref, W * H);
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
    begin
      P := $FF000000 or Cardinal((X * 37 + Y * 11) and $FF) shl 16 or Cardinal((X * 5) and $FF) shl 8 or
        Cardinal((Y * 3) and $FF);
      if (X div 7) mod 2 = 0 then
        P := $FF336699;      { runs of one color too }
      Ref[Y * W + X] := P;
      C.FillRect(X, Y, 1, 1, TColor32(P));
    end;
end;

procedure Same(C: TCanvas32; const Ref: TPixels; W, H: Integer; const What: string);
var
  X, Y: Integer;
begin
  for Y := 0 to H - 1 do
    for X := 0 to W - 1 do
      if Cardinal(C.GetPixel(X, Y)) <> Ref[Y * W + X] then
        raise EAssertionFailed.CreateFmt('%s: pixel %d,%d is %.8x, not %.8x',
          [What, X, Y, Cardinal(C.GetPixel(X, Y)), Ref[Y * W + X]]);
end;

procedure TGraphicsTests.RoundedRectanglesAreExact;
const
  W = 160;
  H = 120;
  Colors: array[0..2] of Cardinal = ($FFE04040, $80208020, $1A0000FF);
var
  C: TCanvas32;
  Ref: TPixels;
  RX, RY, RW, RH, X, Y, Outer, Inner, K: Integer;
  Radius, T, IR: Single;
  Col: Cardinal;
begin
  C := TCanvas32.Create;
  try
    for K := 0 to 11 do
    begin
      Stripes(C, W, H, Ref);
      RX := 3 + K * 2;
      RY := 2 + K;
      RW := 40 + K * 9;
      RH := 12 + K * 8;
      Radius := K * 1.7;
      T := 1 + (K mod 4) * 1.5;
      Col := Colors[K mod 3];
      if K mod 2 = 0 then
        C.FillRoundRect(RX, RY, RW, RH, Radius, TColor32(Col))
      else
        C.StrokeRoundRect(RX, RY, RW, RH, Radius, T, TColor32(Col));
      Radius := Min(Radius, Min(RW, RH) / 2);
      for Y := 0 to H - 1 do
        for X := 0 to W - 1 do
          if (X >= RX) and (Y >= RY) and (X < RX + RW) and (Y < RY + RH) then
            if K mod 2 = 0 then
            begin
              if Radius <= 0 then
                Ref[Y * W + X] := BlendOne(Ref[Y * W + X], Col, 255)
              else
                Ref[Y * W + X] := BlendOne(Ref[Y * W + X], Col, Cover(Dist(X + 0.5, Y + 0.5, RX, RY, RW, RH, Radius)));
            end
            else
            begin
              IR := Max(Max(0, Radius - T), 0.01);
              Outer := Cover(Dist(X + 0.5, Y + 0.5, RX, RY, RW, RH, Max(Radius, 0.01)));
              Inner := Cover(Dist(X + 0.5, Y + 0.5, RX + T, RY + T, RW - 2 * T, RH - 2 * T, IR));
              if Outer > Inner then
                Ref[Y * W + X] := BlendOne(Ref[Y * W + X], Col, Outer - Inner);
            end;
      Same(C, Ref, W, H, Format('shape %d', [K]));
    end;
  finally
    C.Free;
  end;
end;

procedure TGraphicsTests.SeeThroughFillsAreExact;
const
  W = 90;
  H = 40;
var
  C: TCanvas32;
  Ref: TPixels;
  A, X, Y: Integer;
  Col: Cardinal;
begin
  C := TCanvas32.Create;
  try
    A := 0;
    while A <= 255 do
    begin
      Stripes(C, W, H, Ref);
      Col := (Cardinal(A) shl 24) or $00C08040;
      C.FillRect(5, 3, 70, 30, TColor32(Col));
      for Y := 3 to 32 do
        for X := 5 to 74 do
          Ref[Y * W + X] := BlendOne(Ref[Y * W + X], Col, 255);
      Same(C, Ref, W, H, Format('alpha %d', [A]));
      Inc(A, 17);
    end;
    { inside a clip: only there }
    Stripes(C, W, H, Ref);
    C.PushClip(RectI(10, 10, 20, 5));
    C.Clear(TColor32($FF010203));
    C.FillRect(0, 0, W, H, TColor32($80FFFFFF));
    C.PopClip;
    for Y := 10 to 14 do
      for X := 10 to 29 do
        Ref[Y * W + X] := BlendOne($FF010203, $80FFFFFF, 255);
    Same(C, Ref, W, H, 'clipped');
  finally
    C.Free;
  end;
end;

procedure TGraphicsTests.TextIsClipped;
var
  C, Whole: TCanvas32;
  F: TPastelFont;
  X, Y: Integer;
begin
  InitFonts;
  F := GetFont(16, False);
  C := TCanvas32.Create;
  Whole := TCanvas32.Create;
  try
    C.SetSize(120, 40);
    Whole.SetSize(120, 40);
    C.Clear(TColor32($FFFFFFFF));
    Whole.Clear(TColor32($FFFFFFFF));
    Whole.DrawText(F, -4, 8, 'Wgyj Ünlü', TColor32($C0102030));
    C.PushClip(RectI(10, 12, 40, 9));
    C.DrawText(F, -4, 8, 'Wgyj Ünlü', TColor32($C0102030));
    C.PopClip;
    for Y := 0 to 39 do
      for X := 0 to 119 do
        if (X >= 10) and (X < 50) and (Y >= 12) and (Y < 21) then
          AssertEquals(Integer(Whole.GetPixel(X, Y)), Integer(C.GetPixel(X, Y)), Format('inside %d,%d', [X, Y]))
        else
          AssertEquals(Integer($FFFFFFFF), Integer(C.GetPixel(X, Y)), Format('outside %d,%d', [X, Y]));
    { and text past the canvas edges does no harm }
    C.DrawText(F, 100, 30, 'past the edge', TColor32($FF000000));
    C.DrawText(F, -50, -10, 'past the edge', TColor32($FF000000));
  finally
    C.Free;
    Whole.Free;
  end;
end;

procedure TGraphicsTests.ScaledPicturesKeepTheirColors;
var
  C: TCanvas32;
  B: TBitmap32;
  I, X, Y: Integer;
  P: Cardinal;
begin
  C := TCanvas32.Create;
  B := TBitmap32.Create;
  try
    C.SetSize(200, 100);
    { one color: the same color at any size, edges included }
    B.SetSize(7, 5);
    for I := 0 to High(B.Pixels) do
      B.Pixels[I] := $FF2080C0;
    C.Clear(TColor32($FF000000));
    C.DrawBitmap(B, 3, 4, 150, 61);
    for Y := 4 to 64 do
      for X := 3 to 152 do
        AssertEquals(Integer($FF2080C0), Integer(C.GetPixel(X, Y)), Format('bigger %d,%d', [X, Y]));
    AssertEquals(Integer($FF000000), Integer(C.GetPixel(153, 30)), 'only inside');
    C.DrawBitmap(B, 160, 70, 3, 2);
    AssertEquals(Integer($FF2080C0), Integer(C.GetPixel(161, 71)), 'smaller');
    { left half black, right half white: a gradient only in the middle }
    B.SetSize(2, 1);
    B.Pixels[0] := $FF000000;
    B.Pixels[1] := $FFFFFFFF;
    C.DrawBitmap(B, 0, 80, 100, 10);
    AssertEquals(Integer($FF000000), Integer(C.GetPixel(2, 85)), 'the left edge');
    AssertEquals(Integer($FFFFFFFF), Integer(C.GetPixel(97, 85)), 'the right edge');
    P := Cardinal(C.GetPixel(50, 85)) and $FF;
    AssertTrue((P > 100) and (P < 155), Format('the middle is grey: %d', [P]));
    { not smooth: the nearest pixel }
    C.DrawBitmap(B, 0, 92, 100, 4, False);
    AssertEquals(Integer($FF000000), Integer(C.GetPixel(49, 93)), 'nearest left');
    AssertEquals(Integer($FFFFFFFF), Integer(C.GetPixel(50, 93)), 'nearest right');
    { half see-through }
    B.SetSize(1, 1);
    B.Pixels[0] := $FFFFFFFF;
    C.FillRect(110, 80, 20, 10, TColor32($FF000000));
    C.DrawBitmap(B, 110, 80, 20, 10, True, 128);
    AssertEquals(Integer(BlendOne($FF000000, $FFFFFFFF, 128)), Integer(C.GetPixel(115, 85)), 'opacity');
  finally
    B.Free;
    C.Free;
  end;
end;

procedure TGraphicsTests.AFullWindowIsQuick;
var
  F: TForm;
  G: TGrid;
  C: TCanvas32;
  I, R: Integer;
  T0, Best: QWord;
begin
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    G := TGrid.Create(F);
    G.Parent := F;
    G.Grow := 1;
    for I := 0 to 7 do
      G.AddColumn('Column ' + IntToStr(I));
    for R := 0 to 999 do
      G.AddRow(['a' + IntToStr(R), 'bbbb', 'cccccc', 'd', 'eeeee', 'ffff', 'gg', 'hhhhhh']);
    F.Layout(1920, 1080);
    C.SetSize(1920, 1080);
    F.Render(C);
    { the best of a few (the machine may be busy): it was 75 ms, now a few }
    Best := High(QWord);
    for I := 1 to 5 do
    begin
      T0 := GetTickCount64;
      F.Render(C);
      Best := Min(Best, GetTickCount64 - T0);
    end;
    AssertTrue(Best < 25, Format('a full-screen grid in %d ms', [Best]));
  finally
    C.Free;
    F.Free;
  end;
end;

initialization
  RegisterTests(TGraphicsTests);

end.
