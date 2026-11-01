{ The server's routes, over real HTTP: a web server on a free port with a
  store in a temporary SQLite file. }
unit Sync_Api_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Testing, Pastel.Web, Pastel.Http, Pastel.Json, Pastel.Db, Pastel.Files, Pastel.Log,
  SalonStore, SalonSync, SalonController;

type
  TSyncApiTests = class(TTestSuite)
  private
    Dir, Base: string;
    Web: TWebServer;
    Server, Desk: TSalonStore;
    Controller: TSalonController;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ADesktopSyncs;
    procedure TheReadOnlyApi;
    procedure BadDataIs422;
  end;

implementation

procedure TSyncApiTests.SetUp;
var
  Port: Integer;
begin
  Log.Console := False;
  Dir := MakeTempDir('salon-api-test');
  Server := TSalonStore.Create(TDatabase.Open('sqlite:' + Dir + 'server.db', 2), True);
  Server.CreateTables;
  Desk := TSalonStore.Create(TDatabase.Open('sqlite:' + Dir + 'desk.db', 1), True);
  Desk.CreateTables;
  Controller := TSalonController.Create(Server);
  Port := 22000 + Random(20000);
  Base := Format('http://127.0.0.1:%d', [Port]);
  Web := TWebServer.Create(Port, '127.0.0.1');
  Web.AccessLog := False;
  Controller.Routes(Web);
  Web.Start;
end;

procedure TSyncApiTests.TearDown;
begin
  Web.Stop;
  Web.Free;
  Controller.Free;
  Server.Free;
  Desk.Free;
  DeleteDir(Dir);
  Log.Console := True;
end;

procedure TSyncApiTests.ADesktopSyncs;
var
  C: TJSONObject;
  Last: string;
  R: TSyncResult;
begin
  C := JObject(['name', 'Ayşe Yılmaz', 'phone', '0532 111 22 33']);
  Desk.Save(skCustomer, C);
  C.Free;
  Last := '';
  R := SyncWithServer(Desk, Base, '', Last);
  AssertEquals(1, R.Sent);
  AssertEquals(1, Server.Count(skCustomer), 'the server has it');
  AssertTrue(Last <> '', 'the server''s time is kept');
  R := SyncWithServer(Desk, Base, '', Last);
  AssertEquals(0, R.Sent, 'nothing new');
end;

procedure TSyncApiTests.TheReadOnlyApi;
var
  C, A: TJSONObject;
  Id: string;
  D: TJSONData;
begin
  C := JObject(['name', 'Ali Can']);
  Id := Server.Save(skCustomer, C);
  C.Free;
  A := JObject(['customer_id', Id, 'starts_at', '2026-11-03 10:00', 'service', 'Haircut', 'price_cents', 45000]);
  Server.Save(skAppointment, A);
  A.Free;
  D := HttpGetJson(Base + '/api/customers?q=ali');
  try
    AssertEquals('Ali Can', JStr(D, '[0].name'));
  finally
    D.Free;
  end;
  D := HttpGetJson(Base + '/api/appointments?date=2026-11-03');
  try
    AssertEquals('Ali Can', JStr(D, '[0].customer_name'));
    AssertEquals(45000, JInt(D, '[0].price_cents'));
  finally
    D.Free;
  end;
  AssertEquals(400, HttpGet(Base + '/api/appointments?date=tomorrow').Status);
end;

procedure TSyncApiTests.BadDataIs422;
begin
  AssertEquals(422, HttpPostJson(Base + '/api/sync', '{"since": ""}').Status);
  AssertEquals(422, HttpPostJson(Base + '/api/sync',
    '{"changes": {"customers": [{"id": "x1", "updated_at": "2026-11-01T10:00:00.000000Z", "name": ""}]}}').Status,
    'a customer without a name');
end;

initialization
  RegisterTests(TSyncApiTests);
end.
