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
    procedure Sync(Req: TWebRequest; Res: TWebResponse);
    procedure Customers(Req: TWebRequest; Res: TWebResponse);
    procedure Appointments(Req: TWebRequest; Res: TWebResponse);
    procedure Invoices(Req: TWebRequest; Res: TWebResponse);
  public
    constructor Create(AStore: TSalonStore);
    procedure Routes(Web: TWebServer);
  end;

implementation

uses
  Pastel.Json, Pastel.Log;

constructor TSalonController.Create(AStore: TSalonStore);
begin
  inherited Create;
  FStore := AStore;
end;

procedure TSalonController.Routes(Web: TWebServer);
begin
  Web.Post('/api/sync', @Sync);
  Web.Get('/api/customers', @Customers);
  Web.Get('/api/appointments', @Appointments);
  Web.Get('/api/invoices', @Invoices);
end;

(* POST /api/sync  {"since": "<the server's time of the last sync>", "changes": {...}}
   -> {"now": "...", "applied": 3, "changes": {what changed here since "since"}} *)
procedure TSalonController.Sync(Req: TWebRequest; Res: TWebResponse);
var
  Body, Answer, Theirs: TJSONObject;
  Now_, Since: string;
  Applied: Integer;
begin
  Body := Req.JsonObject;
  if not (Body.Find('changes') is TJSONObject) then
    raise EWebError.Create(422, 'changes is required (an object with customers, appointments, invoices)');
  Since := JStr(Body, 'since');
  { the time before taking anything: what other computers send meanwhile
    comes with the next sync }
  Now_ := NowStamp;
  try
    Applied := FStore.Apply(TJSONObject(Body.Find('changes')), True);
  except
    on E: ESalonInvalid do
      raise EWebError.Create(422, E.Message);
  end;
  Theirs := FStore.Changes(Since, False);
  Answer := TJSONObject.Create;
  Answer.Strings['now'] := Now_;
  Answer.Integers['applied'] := Applied;
  Answer.Add('changes', Theirs);
  Log.Info('sync from %s: %d record(s) taken, %d sent back', [Req.ClientIP, Applied,
    Theirs.Arrays['customers'].Count + Theirs.Arrays['appointments'].Count + Theirs.Arrays['invoices'].Count]);
  Res.Json(Answer);
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

end.
