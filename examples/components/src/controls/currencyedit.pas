{ TCurrencyEdit - an edit for amounts of money.

    object PriceEdit: TCurrencyEdit
      Symbol = '₺'
      Decimals = 2
      OnChange = PriceChange
    end

    Total := PriceEdit.Value * Quantity;     // a Currency, not text
    PriceEdit.Value := 1234.5;              // shows 1.234,50 ₺ (in Turkish)

  People may type '1234,5', '1.234,50' or '1234.50'; when they leave the edit
  it shows the amount the way their language writes it. An example of a
  control made from an existing one: everything of TEdit, plus Value. }
unit CurrencyEdit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pastel.UI;

type
  TCurrencyEdit = class(TEdit)
  private
    FSymbol: string;
    FDecimals: Integer;
    function GetValue: Currency;
    procedure SetValue(AValue: Currency);
    function GetValid: Boolean;
    procedure SetSymbol(const AValue: string);
    procedure SetDecimals(AValue: Integer);
  protected
    procedure TextInput(const S: string); override;
    procedure FocusLost; override;
  public
    constructor Create(AOwner: TComponent); override;
    { The amount; 0 when the text is empty or not an amount (see Valid). }
    property Value: Currency read GetValue write SetValue;
    { The text is empty or an amount. }
    property Valid: Boolean read GetValid;
    { Writes the text again in the language's way (done when the focus leaves). }
    procedure Reformat;
  published
    { Shown after the amount: '₺', '€', 'USD' }
    property Symbol: string read FSymbol write SetSymbol;
    { Digits after the decimal separator. }
    property Decimals: Integer read FDecimals write SetDecimals default 2;
  end;

implementation

uses
  Money;

constructor TCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDecimals := 2;
end;

function TCurrencyEdit.GetValue: Currency;
begin
  if not TryParseMoney(Text, Result) then
    Result := 0;
end;

procedure TCurrencyEdit.SetValue(AValue: Currency);
begin
  Text := FormatMoney(AValue, FDecimals, FSymbol);
end;

function TCurrencyEdit.GetValid: Boolean;
var
  V: Currency;
begin
  Result := (Trim(Text) = '') or TryParseMoney(Text, V);
end;

procedure TCurrencyEdit.SetSymbol(const AValue: string);
begin
  FSymbol := AValue;
  Reformat;
end;

procedure TCurrencyEdit.SetDecimals(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > 4 then AValue := 4;
  FDecimals := AValue;
  Reformat;
end;

procedure TCurrencyEdit.Reformat;
var
  V: Currency;
begin
  if (Trim(Text) <> '') and TryParseMoney(Text, V) then
    Value := V;
end;

{ only what can be part of an amount gets in }
procedure TCurrencyEdit.TextInput(const S: string);
var
  I: Integer;
  Clean: string;
begin
  Clean := '';
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9', '.', ',', '-', ' '] then
      Clean := Clean + S[I];
  if Clean <> '' then
    inherited TextInput(Clean);
end;

procedure TCurrencyEdit.FocusLost;
begin
  inherited FocusLost;
  Reformat;
end;

initialization
  RegisterControl(TCurrencyEdit);
end.
