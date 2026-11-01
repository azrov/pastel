{ Tests for Pastel.Lang. }
unit Lang_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.Testing, Pastel.Assets, Pastel.Lang;

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

initialization
  RegisterTests(TLangTests);
end.
