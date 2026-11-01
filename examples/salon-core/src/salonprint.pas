{ The salon's papers: an invoice as PDF (or HTML), the invoices as an Excel
  file. Shared by the desktop app (Print, PDF, Excel buttons) and the server
  (GET /api/invoices/:id/pdf). }
unit SalonPrint;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Report, Pastel.Sheets, SalonStore;

{ The invoice with this id; Shop: the salon's name, its address on the lines after. }
function InvoiceReport(Store: TSalonStore; const InvoiceId, Shop: string): TReport;
{ The invoices (rows of TSalonStore.List(skInvoice)) as a spreadsheet. }
function InvoicesSheet(Invoices: TJSONArray): TSpreadsheet;

implementation

uses
  Classes, Pastel.Json, Pastel.Lang, Pastel.Pdf, SalonMoney;

function IsoDate(const Iso: string): TDateTime;
begin
  if not TryStrToDate(Iso, Result, 'yyyy-mm-dd', '-') then
    Result := 0;
end;

function InvoiceReport(Store: TSalonStore; const InvoiceId, Shop: string): TReport;
var
  Inv, Customer: TJSONObject;
  Lines: TJSONData;
  I: Integer;
  ShopLines: TStringArray;
  Issued: TDateTime;
begin
  Inv := Store.Get(skInvoice, InvoiceId);
  if Inv = nil then
    raise ESalonInvalid.CreateFmt(_('There is no invoice %s.'), [InvoiceId]);
  Customer := Store.Get(skCustomer, JStr(Inv, 'customer_id'));
  Result := TReport.Create;
  try
    Result.Pdf.Title := Format(_('Invoice %s'), [JStr(Inv, 'number')]);
    ShopLines := Shop.Split([#10]);
    Result.Footer := ShopLines[0] + ' · ' + _('Page {page} of {pages}');
    Result.Title(Format(_('Invoice %s'), [JStr(Inv, 'number')]));
    for I := 0 to High(ShopLines) do
      if I = 0 then
        Result.Heading(ShopLines[0])
      else
        Result.Note(ShopLines[I]);
    Result.Space(2);
    Issued := IsoDate(JStr(Inv, 'issued_on'));
    Result.Fields([
      _('Customer'), JStr(Customer, 'name'),
      _('Phone'), JStr(Customer, 'phone'),
      _('Date'), FormatDateShort(Issued),
      _('Paid'), BoolToStr(JInt(Inv, 'paid') = 1, _('yes'), _('no'))]);
    Result.Table([_('Service'), _('Amount')], [0, 40], 'LR');
    Lines := GetJSON(JStr(Inv, 'lines', '[]'));
    try
      for I := 0 to Lines.Count - 1 do
        Result.Row([JStr(Lines.Items[I], 'description'), CentsToText(JInt(Lines.Items[I], 'cents'))]);
    finally
      Lines.Free;
    end;
    Result.EndTable;
    Result.Total(_('Net'), CentsToText(JInt(Inv, 'net_cents')));
    Result.Total(Format(_('VAT %d%%'), [JInt(Inv, 'vat_rate')]), CentsToText(JInt(Inv, 'vat_cents')));
    Result.Total(_('Total'), CentsToText(JInt(Inv, 'total_cents')), True);
    Result.Space(6);
    Result.Text(_('Thank you for your visit!'));
  except
    Result.Free;
    Inv.Free;
    Customer.Free;
    raise;
  end;
  Inv.Free;
  Customer.Free;
end;

function InvoicesSheet(Invoices: TJSONArray): TSpreadsheet;
var
  I: Integer;
  Inv: TJSONData;
begin
  Result := TSpreadsheet.Create(_('Invoices'));
  Result.Widths([14, 12, 30, 12, 12, 12, 8]);
  Result.Row([_('Number'), _('Date'), _('Customer'), _('Net'), _('VAT'), _('Total'), _('Paid')], True);
  for I := 0 to Invoices.Count - 1 do
  begin
    Inv := Invoices[I];
    Result.Row([JStr(Inv, 'number'), IsoDate(JStr(Inv, 'issued_on')), JStr(Inv, 'customer_name'),
      JInt(Inv, 'net_cents') / 100, JInt(Inv, 'vat_cents') / 100, JInt(Inv, 'total_cents') / 100,
      JInt(Inv, 'paid') = 1]);
  end;
end;

end.
