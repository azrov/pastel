{ Tests for src/services/money.pas and calendar.pas. Run them with: pastel test }
unit Money_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, Pastel.Testing, Pastel.Lang, Money, Calendar;

type
  TMoneyTests = class(TTestSuite)
  public
    procedure TearDown; override;
  published
    procedure ReadsWhatPeopleType;
    procedure RefusesWhatIsNotMoney;
    procedure WritesItTheLanguagesWay;
    procedure MonthStartsOnMonday;
    procedure IsoDates;
  end;

implementation

procedure TMoneyTests.TearDown;
begin
  UseLanguage('en');
end;

procedure TMoneyTests.ReadsWhatPeopleType;
var
  V: Currency;
begin
  AssertTrue(TryParseMoney('1234,5', V));
  AssertEquals(1234.5, Double(V), 1e-9);
  AssertTrue(TryParseMoney('1.234,50', V));
  AssertEquals(1234.5, Double(V), 1e-9);
  AssertTrue(TryParseMoney('1,234.50', V));
  AssertEquals(1234.5, Double(V), 1e-9);
  AssertTrue(TryParseMoney('1 234 ₺', V));
  AssertEquals(1234, Double(V), 1e-9);
  AssertTrue(TryParseMoney('-7.5', V));
  AssertEquals(-7.5, Double(V), 1e-9);
  AssertTrue(TryParseMoney('1.000', V), 'three digits after the dot: thousands');
  AssertEquals(1000, Double(V), 1e-9);
end;

procedure TMoneyTests.RefusesWhatIsNotMoney;
var
  V: Currency;
begin
  AssertFalse(TryParseMoney('', V));
  AssertFalse(TryParseMoney('abc', V));
  AssertFalse(TryParseMoney('12a', V));
end;

procedure TMoneyTests.WritesItTheLanguagesWay;
begin
  UseLanguage('tr');
  AssertEquals('1.234,50 ₺', FormatMoney(1234.5, 2, '₺'));
  UseLanguage('en');
  AssertEquals('1,234.50', FormatMoney(1234.5));
end;

procedure TMoneyTests.MonthStartsOnMonday;
var
  Cells: TMonthCells;
begin
  Cells := MonthCells(2026, 11);          { 1 November 2026 is a Sunday }
  AssertEquals(DateToIso(EncodeDate(2026, 10, 26)), DateToIso(Cells[0]), 'the Monday before');
  AssertEquals(DateToIso(EncodeDate(2026, 11, 1)), DateToIso(Cells[6]));
  AssertEquals(1, DayOfTheWeek(Cells[7]), 'every row starts on Monday');
end;

procedure TMoneyTests.IsoDates;
var
  D: TDateTime;
begin
  AssertTrue(TryIsoToDate('2026-11-01', D));
  AssertEquals('2026-11-01', DateToIso(D));
  AssertFalse(TryIsoToDate('2026-13-01', D));
  AssertFalse(TryIsoToDate('01.11.2026', D));
end;

initialization
  RegisterTests(TMoneyTests);
end.
