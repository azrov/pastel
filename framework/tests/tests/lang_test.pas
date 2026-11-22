{ Tests for Pastel.Lang. }
unit Lang_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Pastel.Testing, Pastel.Assets, Pastel.Lang, Pastel.Sheets, Pastel.Pdf, Pastel.Files,
  Pastel.Graphics, Pastel.Icons, Pastel.Env;

type
  TLangTests = class(TTestSuite)
  public
    procedure TearDown; override;
  published
    procedure UntranslatedTextStays;
    procedure DialogTextsAreBuiltIn;
    procedure FilesOverrideAndAdd;
    procedure RegionFallsBackToLanguage;
    procedure NumbersAndDates;
    procedure ReadsNumbersOfTheLanguage;
    procedure MonthAndDayNames;
    procedure FilesKeepDotsInEveryLanguage;
  end;

implementation

const
  TrJson: string = '{ "Save": "Kaydet!", "Delete %s?": "%s silinsin mi?", "Empty": "" }';
  PtJson: string = '{ "Color": "Cor" }';
  PtBrJson: string = '{ "Bus": "Ônibus" }';

procedure TLangTests.TearDown;
begin
  UseLanguage('en');
  FormatSettings := DefaultFormatSettings;
end;

procedure TLangTests.UntranslatedTextStays;
begin
  UseLanguage('en');
  AssertEquals('Save', _('Save'));
  AssertEquals('', _(''));
end;

procedure TLangTests.DialogTextsAreBuiltIn;
begin
  AssertFalse(UseLanguage('de'), 'no file for German');
  AssertEquals('Abbrechen', _('Cancel'));
  AssertEquals('de', Language);
  UseLanguage('az');
  AssertEquals('Bəli', _('Yes'));
end;

procedure TLangTests.FilesOverrideAndAdd;
begin
  RegisterAsset('lang/tr.json', PChar(TrJson), Length(TrJson));
  AssertTrue(UseLanguage('tr_TR'));
  AssertEquals('Kaydet!', _('Save'), 'the file wins over the built-in text');
  AssertEquals('Evet', _('Yes'), 'built in');
  AssertEquals('Ali silinsin mi?', Format(_('Delete %s?'), ['Ali']));
  AssertEquals('Empty', _('Empty'), 'an empty translation is no translation');
  AssertEquals('tr-TR', Language);
end;

procedure TLangTests.RegionFallsBackToLanguage;
begin
  RegisterAsset('lang/pt.json', PChar(PtJson), Length(PtJson));
  RegisterAsset('lang/pt-BR.json', PChar(PtBrJson), Length(PtBrJson));
  AssertTrue(UseLanguage('pt-BR'));
  AssertEquals('Cor', _('Color'));
  AssertEquals('Ônibus', _('Bus'));
  AssertEquals('Sim', _('Yes'));
end;

procedure TLangTests.NumbersAndDates;
var
  D: TDateTime;
begin
  D := EncodeDate(2026, 10, 31) + EncodeTime(9, 5, 0, 0);
  UseLanguage('en');
  AssertEquals('1,234.50', FormatNumber(1234.5, 2));
  AssertEquals('10/31/2026', FormatDateShort(D));
  UseLanguage('tr');
  AssertEquals('1.234,50', FormatNumber(1234.5, 2));
  AssertEquals('1.235', FormatNumber(1234.5));
  AssertEquals('31.10.2026', FormatDateShort(D));
  AssertEquals('31.10.2026 09:05', FormatDateTimeShort(D));
  UseLanguage('fr');
  AssertEquals('1 234,50', FormatNumber(1234.5, 2));
  AssertEquals('31/10/2026', FormatDateShort(D));
  UseLanguage('en-GB');
  AssertEquals('31/10/2026', FormatDateShort(D));
end;

procedure TLangTests.ReadsNumbersOfTheLanguage;
var
  V: Double;
begin
  UseLanguage('tr');
  AssertTrue(TryParseNumber('1.234,5', V));
  AssertEquals(1234.5, V, 0.0001);
  UseLanguage('en');
  AssertTrue(TryParseNumber('1,234.5', V));
  AssertEquals(1234.5, V, 0.0001);
  AssertFalse(TryParseNumber('abc', V));
end;

procedure TLangTests.MonthAndDayNames;
begin
  UseLanguage('en');
  AssertEquals('November', MonthName(11));
  AssertEquals('Mo', DayNameShort(1));
  UseLanguage('tr');
  AssertEquals('Kasım', MonthName(11));
  AssertEquals('Pz', DayNameShort(7));
  UseLanguage('de');
  AssertEquals('März', MonthName(3));
  AssertEquals('', MonthName(13));
  UseLanguage('en');
end;

{ the user's language writes 1,5: files, PDFs and pictures still need 1.5 }
procedure TLangTests.FilesKeepDotsInEveryLanguage;
var
  Old: TFormatSettings;
  Dir: string;
  S: TSpreadsheet;
  Rows: TSheetRows;
  C1, C2: TCanvas32;
  X, Y, Diff: Integer;
begin
  Old := DefaultFormatSettings;
  Dir := MakeTempDir('pastel-dots');
  C1 := TCanvas32.Create;
  C2 := TCanvas32.Create;
  try
    C1.SetSize(48, 48);
    C1.Clear(RGB(255, 255, 255));
    DrawIcon(C1, 'search', 0, 0, 48, RGB(0, 0, 0));
    FormatSettings.DecimalSeparator := ',';
    FormatSettings.ThousandSeparator := '.';
    AssertEquals('1.5', FloatToStr(1.5, InvariantFormat));
    S := TSpreadsheet.Create;
    try
      S.Row([1.5, 'x']);
      S.SaveToFile(Dir + 'n.xlsx');
    finally
      S.Free;
    end;
    Rows := ReadSpreadsheet(Dir + 'n.xlsx');
    AssertEquals('1.5', Rows[0][0], 'an Excel number');
    { the same icon in a comma language }
    C2.SetSize(48, 48);
    C2.Clear(RGB(255, 255, 255));
    DrawIcon(C2, 'search', 0, 0, 48, RGB(0, 0, 0));
    Diff := 0;
    for Y := 0 to 47 do
      for X := 0 to 47 do
        if C1.GetPixel(X, Y) <> C2.GetPixel(X, Y) then
          Inc(Diff);
    AssertEquals(0, Diff, 'the icon is drawn the same');
  finally
    DefaultFormatSettings := Old;
    C1.Free;
    C2.Free;
  end;
end;

initialization
  RegisterTests(TLangTests);
end.
