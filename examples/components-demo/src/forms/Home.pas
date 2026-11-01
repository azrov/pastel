unit Home;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pastel.UI, Pastel.Dialogs, Pastel.Lang, Pastel.Inputs, Home.g;
{ Money comes from the components library like the controls; the controls'
  units (StarRating, CurrencyEdit, ...) are added by Pastel itself. }

type
  THomeForm = class(THomeFormBase)
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject);
    procedure AmountChange(Sender: TObject);
    procedure AddClick(Sender: TObject);
  private
    function Total: Currency;
  end;

var
  HomeForm: THomeForm;

implementation

procedure THomeForm.FormCreate(Sender: TObject);
begin
  Memory.Restore;              { the customer and price of the last run }
  DuePicker.Date := Date + 7;
  AmountChange(nil);
end;

procedure THomeForm.FormClose(Sender: TObject);
begin
  Memory.Store;
end;

function THomeForm.Total: Currency;
begin
  Result := PriceEdit.Value * QuantitySlider.Position;
end;

procedure THomeForm.AmountChange(Sender: TObject);
begin
  QuantityLabel.Text := Format(_('Quantity: %d'), [QuantitySlider.Position]);
  TotalLabel.Text := Format(_('Total: %s'), [FormatMoney(Total, 2, PriceEdit.Symbol)]);
end;

procedure THomeForm.AddClick(Sender: TObject);
begin
  if Trim(CustomerEdit.Text) = '' then
  begin
    ShowMessage(_('Who is the order for?'), _('Customer missing'));
    CustomerEdit.SetFocus;
    Exit;
  end;
  if not PriceEdit.Valid or (PriceEdit.Value <= 0) then
  begin
    ShowMessage(_('The price is not an amount.'), _('Price'));
    PriceEdit.SetFocus;
    Exit;
  end;
  Orders.AddRow([CustomerEdit.Text, FormatMoney(Total, 2, PriceEdit.Symbol),
    FormatDateShort(DuePicker.Date) + ' ' + DueTime.Text, StringOfChar('*', Rating.Value)]);
  Orders.Row := Orders.RowCount - 1;
end;

end.
