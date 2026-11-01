{ The HTTP side of the salon server: the routes and their answers. The data
  and its checks are in SalonStore (examples/salon-core), the same unit the
  desktop app uses. }
unit SalonController;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Web, SalonStore;

type
  TSalonController = class
  private
    FStore: TSalonStore;
    FShop: string;
    procedure Customers(Req: TWebRequest; Res: TWebResponse);
    procedure Appointments(Req: TWebRequest; Res: TWebResponse);
    procedure Invoices(Req: TWebRequest; Res: TWebResponse);
    procedure InvoicePdf(Req: TWebRequest; Res: TWebResponse);
    procedure InvoicesXlsx(Req: TWebRequest; Res: TWebResponse);
  public
    { Shop: the salon's name and address lines, for invoices }
    constructor Create(AStore: TSalonStore; const Shop: string = 'Salon');
    procedure Routes(Web: TWebServer);
  end;

implementation

uses
  Pastel.Json, Pastel.Log, Pastel.Report, Pastel.Sheets, Pastel.SyncWeb, SalonPrint;

constructor TSalonController.Create(AStore: TSalonStore; const Shop: string);
begin
  inherited Create;
  FStore := AStore;
  FShop := Shop;
end;

procedure TSalonController.Routes(Web: TWebServer);
begin
  { POST /api/sync: the desktops' synchronization, all of it Pastel.Sync's }
  FStore.Sync.IsServer := True;
  AddSyncRoute(Web, FStore.Sync);
  Web.Get('/api/customers', @Customers);
  Web.Get('/api/appointments', @Appointments);
  Web.Get('/api/invoices', @Invoices);
  Web.Get('/api/invoices.xlsx', @InvoicesXlsx);
  Web.Get('/api/invoices/:id/pdf', @InvoicePdf);
end;

{ the rows without what only the sync needs }
function Public(Rows: TJSONArray): TJSONArray;
var
  I: Integer;
begin
  for I := 0 to Rows.Count - 1 do
  begin
    Rows.Objects[I].Delete('dirty');
    Rows.Objects[I].Delete('synced_at');
    Rows.Objects[I].Delete('deleted');
  end;
  Result := Rows;
end;

{ GET /api/customers?q=ayşe }
procedure TSalonController.Customers(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Json(Public(FStore.List(skCustomer, Req.Query('q'))));
end;

{ GET /api/appointments?date=2026-11-03 }
procedure TSalonController.Appointments(Req: TWebRequest; Res: TWebResponse);
var
  D: string;
begin
  D := Req.Query('date');
  if D = '' then
    D := FormatDateTime('yyyy-mm-dd', Date);
  if (Length(D) <> 10) or (D[5] <> '-') then
    raise EWebError.Create(400, 'date is a day like 2026-11-03');
  Res.Json(Public(FStore.Day(D)));
end;

{ GET /api/invoices }
procedure TSalonController.Invoices(Req: TWebRequest; Res: TWebResponse);
begin
  Res.Json(Public(FStore.List(skInvoice)));
end;

{ GET /api/invoices/:id/pdf: the invoice as PDF (for a web page, an e-mail, a phone) }
procedure TSalonController.InvoicePdf(Req: TWebRequest; Res: TWebResponse);
var
  R: TReport;
begin
  try
    R := InvoiceReport(FStore, Req.Param('id'), FShop);
  except
    on E: ESalonInvalid do
      raise EWebError.Create(404, E.Message);
  end;
  try
    Res.Bytes(R.ToBytes, 'application/pdf');
  finally
    R.Free;
  end;
end;

{ GET /api/invoices.xlsx: every invoice as an Excel file, to download }
procedure TSalonController.InvoicesXlsx(Req: TWebRequest; Res: TWebResponse);
var
  Rows: TJSONArray;
  S: TSpreadsheet;
begin
  Rows := FStore.List(skInvoice);
  S := InvoicesSheet(Rows);
  try
    Res.Bytes(S.ToBytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'invoices.xlsx');
  finally
    S.Free;
    Rows.Free;
  end;
end;

end.
