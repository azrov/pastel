{ Money in cents (kuruş): whole numbers, so 0.10 + 0.20 is exactly 0.30. }
unit SalonMoney;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ 123450 -> '1.234,50' (in the language's way, Pastel.Lang) }
function CentsToText(Cents: Int64): string;
{ '1.234,50', '1234.5', '1 234' -> cents; False when it is not an amount }
function TryTextToCents(const S: string; out Cents: Int64): Boolean;
{ the VAT of a net amount, rounded to the cent: VatOf(10000, 20) = 2000 }
function VatOf(NetCents: Int64; RatePercent: Integer): Int64;

implementation

uses
  Pastel.Lang;

function CentsToText(Cents: Int64): string;
begin
  Result := FormatNumber(Cents / 100, 2);
end;

function TryTextToCents(const S: string; out Cents: Int64): Boolean;
var
  T, Whole, Frac: string;
  I, Dec: Integer;
  Neg: Boolean;
  W: Int64;
begin
  Cents := 0;
  T := '';
  Neg := False;
  for I := 1 to Length(S) do
    case S[I] of
      '0'..'9', '.', ',': T := T + S[I];
      '-': Neg := True;
      ' ', #9: ;
    else
      if Ord(S[I]) < 128 then
        Exit(False);     { letters; bytes of a currency sign (₺) are skipped }
    end;
  if T = '' then
    Exit(False);
  { the decimal separator: the last . or , with one or two digits after it }
  Dec := 0;
  for I := Length(T) downto 1 do
    if T[I] in ['.', ','] then
    begin
      if Length(T) - I <= 2 then
        Dec := I;
      Break;
    end;
  Whole := '';
  Frac := '';
  for I := 1 to Length(T) do
    if T[I] in ['0'..'9'] then
    begin
      if (Dec > 0) and (I > Dec) then
        Frac := Frac + T[I]
      else
        Whole := Whole + T[I];
    end;
  if Whole = '' then
    Whole := '0';
  while Length(Frac) < 2 do
    Frac := Frac + '0';
  Result := TryStrToInt64(Whole, W) and (Length(Whole) <= 15);
  if not Result then
    Exit;
  Cents := W * 100 + StrToInt(Frac);
  if Neg then
    Cents := -Cents;
end;

function VatOf(NetCents: Int64; RatePercent: Integer): Int64;
begin
  { half a cent up, like on a receipt }
  Result := (NetCents * RatePercent + 50) div 100;
end;

end.
