{ Calendar arithmetic for a month view: which day is in which cell. }
unit Calendar;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils;

type
  { 6 weeks x 7 days, Monday first: the month with the end of the one before and
    the start of the one after }
  TMonthCells = array[0..41] of TDateTime;

function MonthCells(Year, Month: Word): TMonthCells;
{ 'November 2026' in the language of the program }
function MonthTitle(Year, Month: Word): string;
{ 'Mo'..'Su' }
function WeekdayShort(Index: Integer): string;
{ '2026-11-01' <-> date; False for anything else }
function TryIsoToDate(const S: string; out D: TDateTime): Boolean;
function DateToIso(D: TDateTime): string;

implementation

uses
  Pastel.Lang;

function MonthCells(Year, Month: Word): TMonthCells;
var
  First: TDateTime;
  I: Integer;
begin
  First := EncodeDate(Year, Month, 1);
  { ISO day of week: Monday 1 .. Sunday 7 }
  First := First - (DayOfTheWeek(First) - 1);
  for I := 0 to 41 do
    Result[I] := First + I;
end;

function MonthTitle(Year, Month: Word): string;
begin
  Result := MonthName(Month) + ' ' + IntToStr(Year);      { Pastel.Lang knows the names }
end;

function WeekdayShort(Index: Integer): string;
begin
  Result := DayNameShort(Index mod 7 + 1);
end;

function TryIsoToDate(const S: string; out D: TDateTime): Boolean;
var
  Y, M, Day: Integer;
begin
  Result := (Length(S) = 10) and (S[5] = '-') and (S[8] = '-') and
    TryStrToInt(Copy(S, 1, 4), Y) and TryStrToInt(Copy(S, 6, 2), M) and TryStrToInt(Copy(S, 9, 2), Day) and
    TryEncodeDate(Y, M, Day, D);
end;

function DateToIso(D: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd', D);
end;

end.
