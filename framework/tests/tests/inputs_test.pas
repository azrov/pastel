{ Tests for Pastel.Inputs: money, dates, numbers and times. }
unit Inputs_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, Pastel.Testing, Pastel.Lang, Pastel.Inputs;

type
  TInputsTests = class(TTestSuite)
  public
    procedure TearDown; override;
  published
    procedure ReadsWhatPeopleType;
    procedure RefusesWhatIsNotMoney;
    procedure WritesItTheLanguagesWay;
    procedure MonthStartsOnMonday;
    procedure IsoDates;
    procedure TimesOfDay;
    procedure NumberEditStaysInRange;
    procedure TimeEditSteps;
  end;

implementation

procedure TInputsTests.TearDown;
begin
  UseLanguage('en');
end;

procedure TInputsTests.ReadsWhatPeopleType;
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

procedure TInputsTests.RefusesWhatIsNotMoney;
var
  V: Currency;
begin
  AssertFalse(TryParseMoney('', V));
  AssertFalse(TryParseMoney('abc', V));
  AssertFalse(TryParseMoney('12a', V));
end;

procedure TInputsTests.WritesItTheLanguagesWay;
begin
  UseLanguage('tr');
  AssertEquals('1.234,50 ₺', FormatMoney(1234.5, 2, '₺'));
  UseLanguage('en');
  AssertEquals('1,234.50', FormatMoney(1234.5));
end;

procedure TInputsTests.MonthStartsOnMonday;
var
  Cells: TMonthCells;
begin
  Cells := MonthCells(2026, 11);          { 1 November 2026 is a Sunday }
  AssertEquals(DateToIso(EncodeDate(2026, 10, 26)), DateToIso(Cells[0]), 'the Monday before');
  AssertEquals(DateToIso(EncodeDate(2026, 11, 1)), DateToIso(Cells[6]));
  AssertEquals(1, DayOfTheWeek(Cells[7]), 'every row starts on Monday');
end;

procedure TInputsTests.IsoDates;
var
  D: TDateTime;
begin
  AssertTrue(TryIsoToDate('2026-11-01', D));
  AssertEquals('2026-11-01', DateToIso(D));
  AssertFalse(TryIsoToDate('2026-13-01', D));
  AssertFalse(TryIsoToDate('01.11.2026', D));
end;

procedure TInputsTests.TimesOfDay;
begin
  AssertEquals(570, ParseTimeOfDay('9:30'));
  AssertEquals(570, ParseTimeOfDay('930'));
  AssertEquals(570, ParseTimeOfDay('09.30'));
  AssertEquals(540, ParseTimeOfDay('9'));
  AssertEquals(-1, ParseTimeOfDay('25:00'));
  AssertEquals(-1, ParseTimeOfDay('abc'));
end;

procedure TInputsTests.NumberEditStaysInRange;
var
  E: TNumberEdit;
begin
  E := TNumberEdit.Create(nil);
  try
    E.Min := 1;
    E.Max := 10;
    E.Value := 50;
    AssertEquals(10, E.Value);
    E.StepBy(-3);
    AssertEquals(7, E.Value);
    E.Text := '';
    AssertEquals(1, E.Value);
  finally
    E.Free;
  end;
end;

procedure TInputsTests.TimeEditSteps;
var
  E: TTimeEdit;
begin
  E := TTimeEdit.Create(nil);
  try
    E.Text := '9:10';
    AssertEquals(550, E.Minutes);
    E.Minutes := 23 * 60 + 50;
    AssertEquals('23:50', E.Text);
    E.Text := '';
    AssertFalse(E.HasTime);
  finally
    E.Free;
  end;
end;

initialization
  RegisterTests(TInputsTests);

end.
