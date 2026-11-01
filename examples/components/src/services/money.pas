{ Money as text: parsing what people type, writing it the way their language does. }
unit Money;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ '1.234,50', '1234.5', '1 234,50 ₺' -> 1234.5; False when it is not an amount. The
  last . or , followed by one or two digits is the decimal separator. }
function TryParseMoney(const S: string; out Value: Currency): Boolean;
{ 1234.5 -> '1.234,50' with Pastel.Lang's separators, the symbol after it when given. }
function FormatMoney(Value: Currency; Decimals: Integer = 2; const Symbol: string = ''): string;

implementation

uses
  Pastel.Lang;

function TryParseMoney(const S: string; out Value: Currency): Boolean;
var
  T, Digits: string;
  I, Dec: Integer;
  Neg: Boolean;
begin
  Value := 0;
  T := '';
  Neg := False;
  { keep digits and separators; a - anywhere makes it negative }
  for I := 1 to Length(S) do
    case S[I] of
      '0'..'9', '.', ',': T := T + S[I];
      '-': Neg := True;
      ' ', #9: ;
    else
      if Ord(S[I]) < 128 then
        Exit(False);    { letters are not money; UTF-8 bytes (₺, €) are a symbol }
    end;
  if T = '' then
    Exit(False);
  { the decimal separator: the last . or , with at most two digits after it }
  Dec := 0;
  for I := Length(T) downto 1 do
    if T[I] in ['.', ','] then
    begin
      if Length(T) - I <= 2 then
        Dec := I;
      Break;
    end;
  Digits := '';
  for I := 1 to Length(T) do
    if T[I] in ['0'..'9'] then
      Digits := Digits + T[I]
    else if I = Dec then
      Digits := Digits + '.';
  Result := TryStrToCurr(Digits, Value, DefaultFormatSettings) or
    TryStrToCurr(StringReplace(Digits, '.', DefaultFormatSettings.DecimalSeparator, []), Value);
  if Result and Neg then
    Value := -Value;
end;

function FormatMoney(Value: Currency; Decimals: Integer; const Symbol: string): string;
begin
  Result := FormatNumber(Value, Decimals);
  if Symbol <> '' then
    Result := Result + ' ' + Symbol;
end;

end.
