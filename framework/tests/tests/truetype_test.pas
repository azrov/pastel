{ Tests for Pastel.TrueType: fonts without FreeType (as on Android). }
unit TrueType_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.TrueType, Pastel.Graphics;

type
  TTrueTypeTests = class(TTestSuite)
  private
    function FontFile: string;
  published
    procedure ReadsTheTables;
    procedure DrawsGlyphs;
    procedure KernsPairs;
    procedure DrawsLikeFreeType;
  end;

implementation

function TTrueTypeTests.FontFile: string;
begin
  for Result in TStringArray.Create('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/TTF/DejaVuSans.ttf',
    'C:\Windows\Fonts\arial.ttf') do
    if FileExists(Result) then
      Exit;
  Result := '';
end;

procedure TTrueTypeTests.ReadsTheTables;
var
  F: TTrueTypeFont;
begin
  if FontFile = '' then
    Skip('no DejaVu Sans or Arial on this computer');
  F := TTrueTypeFont.Create(FontFile);
  try
    AssertTrue(F.UnitsPerEm >= 1000);
    AssertTrue(F.Ascender > 0);
    AssertTrue(F.Descender < 0);
    AssertTrue(F.GlyphIndex(Ord('A')) > 0, 'A is in the font');
    AssertTrue(F.GlyphIndex($11E) > 0, 'Ğ too (cmap beyond ASCII)');
    AssertEquals(0, F.GlyphIndex($10FFFD), 'not every code point');
    AssertTrue(F.AdvanceWidth(F.GlyphIndex(Ord('W'))) > F.AdvanceWidth(F.GlyphIndex(Ord('i'))));
  finally
    F.Free;
  end;
  try
    TTrueTypeFont.Create(ParamStr(0)).Free;
    Fail('a program is not a font');
  except
    on E: ETrueType do ;
  end;
end;

procedure TTrueTypeTests.DrawsGlyphs;
var
  F: TTrueTypeFont;
  B, Bold: TTrueTypeBitmap;
  I, Ink, BoldInk: Integer;
begin
  if FontFile = '' then
    Skip('no DejaVu Sans or Arial on this computer');
  F := TTrueTypeFont.Create(FontFile);
  try
    F.Render(F.GlyphIndex(Ord('H')), 20 / F.UnitsPerEm, False, B);
    AssertTrue((B.Width >= 10) and (B.Width <= 16), 'H is about 13 pixels wide at 20 pixels: ' + IntToStr(B.Width));
    AssertTrue((B.Top >= 13) and (B.Top <= 16), 'and as high as a capital');
    AssertEquals(B.Width * B.Height, Length(B.Bits));
    Ink := 0;
    for I := 0 to High(B.Bits) do
      Inc(Ink, B.Bits[I]);
    AssertTrue(Ink > 255 * 20, 'something is drawn');
    AssertEquals(255, B.Bits[(B.Height div 4) * B.Width + B.Left], 'the left stem is solid');
    F.Render(F.GlyphIndex(Ord('H')), 20 / F.UnitsPerEm, True, Bold);
    BoldInk := 0;
    for I := 0 to High(Bold.Bits) do
      Inc(BoldInk, Bold.Bits[I]);
    AssertTrue(BoldInk > Ink, 'bold has more ink');
    AssertTrue(Bold.Advance > B.Advance);
    F.Render(F.GlyphIndex(Ord(' ')), 20 / F.UnitsPerEm, False, B);
    AssertEquals(0, B.Width, 'a space has no pixels');
    AssertTrue(B.Advance > 0, 'but it moves the pen');
  finally
    F.Free;
  end;
end;

procedure TTrueTypeTests.KernsPairs;
var
  F: TTrueTypeFont;
begin
  if FontFile = '' then
    Skip('no DejaVu Sans or Arial on this computer');
  F := TTrueTypeFont.Create(FontFile);
  try
    if not F.HasKerning then
      Skip('the font has no kern table');
    AssertTrue(F.Kerning(F.GlyphIndex(Ord('A')), F.GlyphIndex(Ord('V'))) < 0, 'AV comes closer');
    AssertEquals(0, F.Kerning(F.GlyphIndex(Ord('H')), F.GlyphIndex(Ord('H'))));
  finally
    F.Free;
  end;
end;

procedure TTrueTypeTests.DrawsLikeFreeType;
var
  F: TTrueTypeFont;
  Fnt: TPastelFont;
  B: TTrueTypeBitmap;
  S: string;
  W1, W2: Integer;
begin
  if (FontFile = '') or PascalFonts or (InitFonts <> '') then
    Skip('FreeType is not here to compare with');
  SetFontFiles(FontFile, FontFile);
  Fnt := GetFont(16);
  F := TTrueTypeFont.Create(FontFile);
  try
    S := 'Hello, Pastel!';
    W1 := Fnt.TextWidth(S);
    W2 := 0;
    for S in ['H', 'e', 'l', 'l', 'o', ',', ' ', 'P', 'a', 's', 't', 'e', 'l', '!'] do
    begin
      F.Render(F.GlyphIndex(Ord(S[1])), 16 / F.UnitsPerEm, False, B);
      Inc(W2, B.Advance);
    end;
    AssertTrue(Abs(W1 - W2) <= 3, Format('the same width as FreeType: %d and %d', [W1, W2]));
  finally
    F.Free;
  end;
end;

initialization
  RegisterTests(TTrueTypeTests);

end.
