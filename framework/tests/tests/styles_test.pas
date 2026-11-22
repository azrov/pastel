{ Tests of the styles (Pastel.UI): Pastel, Fluent, Material, 'auto' and
  .pstyle files with looks for StyleLookup. }
unit styles_test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.Testing, Pastel.Graphics, Pastel.UI, Pastel.Controls, Pastel.Dialogs;

type
  TStylesTests = class(TTestSuite)
  private
    FDone: Integer;
    procedure Answered(Sender: TObject; AResult: Integer);
  public
    procedure TearDown; override;
  published
    procedure EachStyleHasItsSizes;
    procedure AutoIsThePlatformsOwn;
    procedure AnUnknownStyleChangesNothing;
    procedure TheThemeStaysLightOrDark;
    procedure AStyleFileStartsFromItsBase;
    procedure LooksChangeAControl;
    procedure ADarkLookTakesTheRestFromTheLightOne;
    procedure BadStyleFilesSayWhy;
    procedure DialogButtonsAreInThePlatformsOrder;
    procedure TheFocusIsDrawnInTheStyle;
  end;

implementation

const
  Company = 'base = "material"' + LineEnding +
    'radius = 6' + LineEnding +
    '[colors]' + LineEnding +
    'accent = "#0A7D5A"' + LineEnding +
    '[colors.dark]' + LineEnding +
    'accent = "#5EE0B0"' + LineEnding +
    '[button]' + LineEnding +
    'padding_y = 16' + LineEnding +
    'radius = 6' + LineEnding +
    '[field]' + LineEnding +
    'look = "box"' + LineEnding +
    '[look.Big]' + LineEnding +
    'color = "#16A34A"' + LineEnding +
    'text_color = "#FFFFFF"' + LineEnding +
    'padding_y = 30' + LineEnding +
    'radius = 0' + LineEnding +
    '[look.Big.dark]' + LineEnding +
    'color = "#22C55E"' + LineEnding +
    '[look.Note]' + LineEnding +
    'text_color = "#FF0000"' + LineEnding +
    'font_size = 20' + LineEnding;

procedure TStylesTests.TearDown;
begin
  UseStyle('pastel');
  UseDarkTheme(False);
end;

procedure TStylesTests.Answered(Sender: TObject; AResult: Integer);
begin
  FDone := AResult;
end;

function ButtonHeight(Style: TButtonStyle = bsPrimary; const Lookup: string = ''): Integer;
var
  F: TForm;
  B: TButton;
begin
  InitFonts;
  F := TForm.Create(nil);
  try
    B := TButton.Create(F);
    B.Text := 'Save';
    B.Style := Style;
    B.StyleLookup := Lookup;
    B.Parent := F;
    F.Layout(400, 300);
    Result := B.Bounds.H;
  finally
    F.Free;
  end;
end;

procedure TStylesTests.EachStyleHasItsSizes;
var
  Pastel, Fluent, Material: Integer;
begin
  InitFonts;
  Pastel := ButtonHeight;
  AssertTrue(UseStyle('fluent'));
  Fluent := ButtonHeight;
  AssertEquals('fluent', UIStyle.Name);
  AssertEquals(4, Theme.Radius, 'small corners');
  AssertEquals(Integer(RGB($00, $5F, $B8)), Integer(Theme.Accent), 'Windows blue');
  AssertTrue(UIStyle.DefaultButtonFirst, 'OK Cancel');
  AssertTrue(UseStyle('Material'), 'names in any case');
  Material := ButtonHeight;
  AssertEquals(Integer(RGB($67, $50, $A4)), Integer(Theme.Accent), 'Material purple');
  AssertEquals(999, UIStyle.ButtonRadius, 'round ends');
  AssertTrue(UIStyle.FieldLook = flOutline);
  AssertTrue((Fluent < Pastel) and (Pastel < Material),
    Format('buttons: Fluent %d, Pastel %d, Material %d pixels high', [Fluent, Pastel, Material]));
  AssertTrue(FieldHeight(20) > 20 + 25, 'Material edits are tall');
  UseStyle('pastel');
  AssertEquals(Pastel, ButtonHeight, 'back to the same');
  AssertEquals(8, Theme.Radius);
  AssertEquals(3, Length(StyleNames));
end;

procedure TStylesTests.AutoIsThePlatformsOwn;
begin
  AssertTrue(UseStyle('auto'));
  AssertEquals(PlatformStyle, UIStyle.Name);
  {$IFDEF LINUX}
  AssertEquals('pastel', PlatformStyle);
  {$ENDIF}
  {$IFDEF WINDOWS}
  AssertEquals('fluent', PlatformStyle);
  {$ENDIF}
  AssertTrue(UseStyle(''), 'nothing is auto too');
end;

procedure TStylesTests.AnUnknownStyleChangesNothing;
begin
  UseStyle('fluent');
  AssertFalse(UseStyle('nope'));
  AssertEquals('fluent', UIStyle.Name);
end;

procedure TStylesTests.TheThemeStaysLightOrDark;
begin
  UseDarkTheme(True);
  UseStyle('fluent');
  AssertTrue(Theme.Dark, 'still dark');
  AssertEquals(Integer(RGB($60, $CD, $FF)), Integer(Theme.Accent), 'the dark Fluent blue');
  UseDarkTheme(False);
  AssertEquals(Integer(RGB($00, $5F, $B8)), Integer(Theme.Accent));
  AssertEquals('fluent', UIStyle.Name, 'the style stays');
end;

procedure TStylesTests.AStyleFileStartsFromItsBase;
begin
  AssertEquals('', LoadStyle('company', Company));
  AssertTrue(UseStyle('company'));
  AssertEquals('company', UIStyle.Name);
  AssertEquals(16, UIStyle.ButtonPadY, 'its own');
  AssertEquals(6, UIStyle.ButtonRadius);
  AssertEquals(48, UIStyle.ButtonPadX, 'from Material');
  AssertTrue(UIStyle.FieldLook = flBox, 'its own field look');
  AssertTrue(UIStyle.SwitchLook = swMaterial, 'Material''s switches');
  AssertEquals(6, Theme.Radius);
  AssertEquals(Integer(RGB($0A, $7D, $5A)), Integer(Theme.Accent), 'its accent');
  AssertEquals(Integer(RGB($FE, $F7, $FF)), Integer(Theme.Background), 'Material''s background');
  AssertTrue(Theme.AccentHover <> Theme.Accent, 'hover worked out');
  UseDarkTheme(True);
  AssertEquals(Integer(RGB($5E, $E0, $B0)), Integer(Theme.Accent), 'its dark accent');
  { a style on a style }
  AssertEquals('', LoadStyle('company-compact', 'base = "company"' + LineEnding + '[button]' + LineEnding +
    'padding_y = 8'));
  AssertTrue(UseStyle('company-compact'));
  AssertEquals(8, UIStyle.ButtonPadY);
  AssertEquals(6, UIStyle.ButtonRadius, 'from company');
  AssertEquals(Integer(RGB($5E, $E0, $B0)), Integer(Theme.Accent), 'company''s colors');
  AssertTrue(FindLook('Big') <> nil, 'company''s looks');
  { loaded again: changed }
  AssertEquals('', LoadStyle('company', 'base = "fluent"'));
  AssertTrue(UseStyle('company'));
  AssertEquals(24, UIStyle.ButtonPadX);
  AssertTrue(FindLook('Big') = nil);
end;

procedure TStylesTests.LooksChangeAControl;
var
  F: TForm;
  B: TButton;
  L: TLabel;
  C: TCanvas32;
  Plain: Integer;
begin
  InitFonts;
  AssertEquals('', LoadStyle('company', Company));
  UseStyle('company');
  Plain := ButtonHeight;
  AssertTrue(ButtonHeight(bsPrimary, 'Big') - Plain = 30 - 16, 'its padding');
  AssertEquals(Plain, ButtonHeight(bsPrimary, 'NoSuchLook'), 'an unknown look is nothing');
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  try
    B := TButton.Create(F);
    B.Text := 'Go';
    B.StyleLookup := 'Big';
    B.Parent := F;
    L := TLabel.Create(F);
    L.Text := 'Hello';
    L.StyleLookup := 'Note';
    L.Parent := F;
    F.Layout(300, 200);
    C.SetSize(300, 200);
    F.Render(C);
    AssertEquals(Integer(RGB($16, $A3, $4A)), Integer(C.GetPixel(B.Bounds.X + 2, B.Bounds.Y + 2)),
      'its color, square corners');
    AssertTrue(L.Font.Size = 20, 'its font size');
    UseDarkTheme(True);
    F.Render(C);
    AssertEquals(Integer(RGB($22, $C5, $5E)), Integer(C.GetPixel(B.Bounds.X + 2, B.Bounds.Y + 2)), 'dark');
  finally
    C.Free;
    F.Free;
  end;
end;

procedure TStylesTests.ADarkLookTakesTheRestFromTheLightOne;
var
  L: TStyleLook;
begin
  AssertEquals('', LoadStyle('company', Company));
  UseStyle('company');
  UseDarkTheme(True);
  L := FindLook('big');
  AssertTrue(L <> nil, 'any case');
  AssertEquals(Integer(RGB($22, $C5, $5E)), Integer(L.Color));
  AssertEquals(Integer(RGB($FF, $FF, $FF)), Integer(L.TextColor), 'from the light one');
  AssertEquals(30, L.PaddingY);
  AssertEquals(-1, L.BorderWidth, 'not set');
end;

procedure TStylesTests.BadStyleFilesSayWhy;

  procedure Bad(const Text, Says: string);
  var
    E: string;
  begin
    E := LoadStyle('bad', Text);
    AssertTrue(Pos(Says, E) > 0, Format('"%s" says "%s"', [Text, E]));
  end;

begin
  Bad('base = "windows"', 'base = windows');
  Bad('[button]' + LineEnding + 'height = 40', '"button.height" is not a style value');
  Bad('[button]' + LineEnding + 'radius = "big"', 'whole number');
  Bad('[field]' + LineEnding + 'look = "round"', 'box, underline or outline');
  Bad('[colors]' + LineEnding + 'accent = "blue"', 'colors.accent = blue is not a theme value');
  Bad('[colors]' + LineEnding + 'sky = "#0000FF"', 'is not a theme value');
  Bad('[look.X]' + LineEnding + 'color = "red"', 'a color');
  Bad('[look.X]' + LineEnding + 'shadow = 2', '"look.X.shadow" is not a look value');
  Bad('[button' + LineEnding, 'expected');
  AssertEquals('"auto" is not a name for a style', LoadStyle('auto', ''));
  AssertTrue(LoadStyle('self', 'base = "self"') <> '', 'its own base');
  AssertFalse(UseStyle('bad'), 'not kept');
end;

procedure TStylesTests.DialogButtonsAreInThePlatformsOrder;
var
  F: TForm;
  C: TCanvas32;

  function Order: string;
  var
    Yes, No: TControl;
  begin
    MessageDlg('Save?', 'Notes', [mrYes, mrNo], @Answered);
    F.Layout(500, 400);
    F.Render(C);
    Yes := TControl(F.TopPopup.FindComponent('YesButton'));
    No := TControl(F.TopPopup.FindComponent('NoButton'));
    if Yes.Bounds.X < No.Bounds.X then Result := 'Yes No' else Result := 'No Yes';
    if TButton(No).Style = bsFlat then
      Result := Result + ' flat';
    F.TopPopup.Close(mrCancel);
    ProcessReleases;
  end;

begin
  InitFonts;
  F := TForm.Create(nil);
  C := TCanvas32.Create;
  C.SetSize(500, 400);
  MainForm := F;
  try
    AssertEquals('No Yes', Order, 'Pastel: the default on the right');
    UseStyle('fluent');
    AssertEquals('Yes No', Order, 'Windows: the default first');
    UseStyle('material');
    AssertEquals('No Yes flat', Order, 'Material: text buttons, the default on the right');
    AssertEquals(28, UIStyle.DialogRadius);
  finally
    MainForm := nil;
    C.Free;
    F.Free;
  end;
end;

procedure TStylesTests.TheFocusIsDrawnInTheStyle;
var
  C: TCanvas32;
begin
  C := TCanvas32.Create;
  try
    C.SetSize(60, 40);
    C.Clear(Theme.Background);
    DrawFocus(C, RectI(10, 10, 40, 20), 4);
    AssertTrue(C.GetPixel(10, 8) <> Theme.Background, 'Pastel: a ring (under the control)');
    UseStyle('fluent');
    C.Clear(Theme.Background);
    DrawFocus(C, RectI(10, 10, 40, 20), 4);
    AssertEquals(Integer(Theme.Text), Integer(C.GetPixel(30, 7)), 'Fluent: a line in the text color');
    AssertEquals(Integer(Theme.Background), Integer(C.GetPixel(30, 20)));
  finally
    C.Free;
  end;
end;

initialization
  RegisterTests(TStylesTests);

end.
