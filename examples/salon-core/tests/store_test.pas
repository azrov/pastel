{ Tests for the store and the synchronization: two stores (a desktop and the
  server) in SQLite files, the sync run by hand without HTTP. }
unit Store_Test;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, Pastel.Testing, Pastel.Json, Pastel.Db, Pastel.Files, Pastel.Lang, SalonStore, SalonMoney, SalonPrint, Pastel.Report, Pastel.Pdf;

type
  TStoreTests = class(TTestSuite)
  private
    Dir: string;
    Desk, Desk2, Server: TSalonStore;
    function NewStore(const Name: string): TSalonStore;
    procedure Sync(Client: TSalonStore);
    function Customer(const Name: string): string;
    procedure SaveNameless;
    procedure SaveBadTime;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Money;
    procedure SavesAndFinds;
    procedure Checks;
    procedure ADayOfAppointments;
    procedure InvoicesDoneAppointments;
    procedure AnInvoiceAsPdfAndHtml;
    procedure SyncBringsRecordsToTheOtherComputer;
    procedure TheNewerChangeWins;
    procedure DeletionsAreSynced;
    procedure SyncingTwiceChangesNothing;
  end;

implementation

var
  ServerClock: string = '';

function TStoreTests.NewStore(const Name: string): TSalonStore;
begin
  Result := TSalonStore.Create(TDatabase.Open('sqlite:' + Dir + Name + '.db', 1), True);
  Result.CreateTables;
end;

procedure TStoreTests.SetUp;
begin
  Dir := MakeTempDir('salon-test');
  Desk := NewStore('desk');
  Desk2 := NewStore('desk2');
  Server := NewStore('server');
  UseLanguage('en');
end;

procedure TStoreTests.TearDown;
begin
  Desk.Free;
  Desk2.Free;
  Server.Free;
  DeleteDir(Dir);
end;

{ what POST /api/sync does, and what SyncWithServer does with its answer;
  each desktop keeps its own "last sync" (here: one shared for simplicity) }
procedure TStoreTests.Sync(Client: TSalonStore);
var
  Mine, Theirs: TJSONObject;
  Since: string;
begin
  Mine := Client.Changes('', True);
  try
    Since := ServerClock;
    ServerClock := NowStamp;
    Server.Apply(Mine, True);
    Theirs := Server.Changes(Since, False);
    try
      Client.Apply(Theirs, False);
      Client.MarkSent(Mine);
    finally
      Theirs.Free;
    end;
  finally
    Mine.Free;
  end;
end;

function TStoreTests.Customer(const Name: string): string;
var
  C: TJSONObject;
begin
  C := JObject(['name', Name, 'phone', '0532 000 00 00']);
  try
    Result := Desk.Save(skCustomer, C);
  finally
    C.Free;
  end;
end;

procedure TStoreTests.Money;
var
  C: Int64;
begin
  AssertTrue(TryTextToCents('1.234,50', C));
  AssertEquals(123450, C);
  AssertTrue(TryTextToCents('45', C));
  AssertEquals(4500, C);
  AssertTrue(TryTextToCents('0,1', C));
  AssertEquals(10, C);
  AssertFalse(TryTextToCents('abc', C));
  AssertEquals(2000, VatOf(10000, 20));
  AssertEquals(1, VatOf(3, 20), 'half a cent up');
  AssertEquals('1,234.50', CentsToText(123450));
end;

procedure TStoreTests.SavesAndFinds;
var
  Id: string;
  C: TJSONObject;
  L: TJSONArray;
begin
  Id := Customer('Ayşe Yılmaz');
  Customer('Ali Can');
  AssertEquals(16, Length(Id));
  C := Desk.Get(skCustomer, Id);
  try
    AssertEquals('Ayşe Yılmaz', JStr(C, 'name'));
    AssertEquals(1, JInt(C, 'dirty'), 'not synced yet');
  finally
    C.Free;
  end;
  L := Desk.List(skCustomer, 'ali');
  try
    AssertEquals(1, L.Count);
  finally
    L.Free;
  end;
  { a change keeps the other values }
  C := JObject(['id', Id, 'notes', 'prefers mornings']);
  try
    Desk.Save(skCustomer, C);
  finally
    C.Free;
  end;
  C := Desk.Get(skCustomer, Id);
  try
    AssertEquals('Ayşe Yılmaz', JStr(C, 'name'));
    AssertEquals('prefers mornings', JStr(C, 'notes'));
  finally
    C.Free;
  end;
  Desk.Delete(skCustomer, Id);
  AssertEquals(1, Desk.Count(skCustomer));
  AssertNil(Desk.Get(skCustomer, Id));
end;

procedure TStoreTests.SaveNameless;
var
  C: TJSONObject;
begin
  C := JObject(['name', '  ']);
  try
    Desk.Save(skCustomer, C);
  finally
    C.Free;
  end;
end;

procedure TStoreTests.SaveBadTime;
var
  A: TJSONObject;
begin
  A := JObject(['customer_id', 'x', 'starts_at', '2026-11-03 25:00']);
  try
    Desk.Save(skAppointment, A);
  finally
    A.Free;
  end;
end;

procedure TStoreTests.Checks;
begin
  AssertRaises(ESalonInvalid, @SaveNameless);
  AssertRaises(ESalonInvalid, @SaveBadTime);
end;

procedure TStoreTests.ADayOfAppointments;
var
  C: string;
  A: TJSONObject;
  L: TJSONArray;
begin
  C := Customer('Ayşe');
  A := JObject(['customer_id', C, 'starts_at', '2026-11-03 14:30', 'service', 'Haircut', 'price_cents', 45000]);
  Desk.Save(skAppointment, A);
  A.Free;
  A := JObject(['customer_id', C, 'starts_at', '2026-11-03 09:00', 'service', 'Color', 'price_cents', 90000]);
  Desk.Save(skAppointment, A);
  A.Free;
  A := JObject(['customer_id', C, 'starts_at', '2026-11-04 10:00', 'service', 'Haircut', 'price_cents', 45000]);
  Desk.Save(skAppointment, A);
  A.Free;
  L := Desk.Day('2026-11-03');
  try
    AssertEquals(2, L.Count);
    AssertEquals('Color', JStr(L, '[0].service'), 'by time');
    AssertEquals('Ayşe', JStr(L, '[0].customer_name'));
    AssertEquals('booked', JStr(L, '[0].status'));
  finally
    L.Free;
  end;
end;

procedure TStoreTests.InvoicesDoneAppointments;
var
  C, A1, A2, InvId: string;
  A, Inv: TJSONObject;
  Open: TJSONArray;
begin
  C := Customer('Ayşe');
  A := JObject(['customer_id', C, 'starts_at', '2026-11-03 09:00', 'service', 'Color', 'price_cents', 90000,
    'status', 'done']);
  A1 := Desk.Save(skAppointment, A);
  A.Free;
  A := JObject(['customer_id', C, 'starts_at', '2026-11-03 10:00', 'service', 'Haircut', 'price_cents', 45050,
    'status', 'done']);
  A2 := Desk.Save(skAppointment, A);
  A.Free;
  Open := Desk.Uninvoiced(C);
  AssertEquals(2, Open.Count);
  Open.Free;
  InvId := Desk.Invoice(C, [A1, A2], 20);
  Inv := Desk.Get(skInvoice, InvId);
  try
    AssertEquals(135050, JInt(Inv, 'net_cents'));
    AssertEquals(27010, JInt(Inv, 'vat_cents'));
    AssertEquals(162060, JInt(Inv, 'total_cents'));
    AssertEquals(FormatDateTime('yyyy', Date) + '-0001', JStr(Inv, 'number'));
  finally
    Inv.Free;
  end;
  Open := Desk.Uninvoiced(C);
  AssertEquals(0, Open.Count, 'invoiced once');
  Open.Free;
end;

procedure TStoreTests.AnInvoiceAsPdfAndHtml;
var
  C, A1, InvId, Html: string;
  A: TJSONObject;
  R: TReport;
  Pdf: TBytes;
  Font, Bold: string;
begin
  C := Customer('Ayşe');
  A := JObject(['customer_id', C, 'starts_at', '2026-11-03 09:00', 'service', 'Color', 'price_cents', 90050,
    'status', 'done']);
  A1 := Desk.Save(skAppointment, A);
  A.Free;
  InvId := Desk.Invoice(C, [A1], 20);
  R := InvoiceReport(Desk, InvId, 'Salon Ayşe'#10'Kadıköy');
  try
    Html := R.ToHtml;
    FindPdfFonts(Font, Bold);
    if Font <> '' then
      Pdf := R.ToBytes;
  finally
    R.Free;
  end;
  AssertContains('<td>Ayşe</td>', Html);
  AssertContains('Color', Html);
  AssertContains('<span>1,080.60</span>', Html, 'the total');
  if Font <> '' then
    AssertEquals('%PDF-', Chr(Pdf[0]) + Chr(Pdf[1]) + Chr(Pdf[2]) + Chr(Pdf[3]) + Chr(Pdf[4]));
end;

procedure TStoreTests.SyncBringsRecordsToTheOtherComputer;
var
  Id: string;
  C: TJSONObject;
begin
  Id := Customer('Ayşe');
  Sync(Desk);
  Sync(Desk2);
  C := Desk2.Get(skCustomer, Id);
  try
    AssertNotNil(C, 'the other computer has it');
    AssertEquals('Ayşe', JStr(C, 'name'));
    AssertEquals(0, JInt(C, 'dirty'), 'it came from the server');
  finally
    C.Free;
  end;
  C := Desk.Get(skCustomer, Id);
  try
    AssertEquals(0, JInt(C, 'dirty'), 'sent');
  finally
    C.Free;
  end;
end;

procedure TStoreTests.TheNewerChangeWins;
var
  Id: string;
  C: TJSONObject;
begin
  Id := Customer('Ayşe');
  Sync(Desk);
  Sync(Desk2);
  { both computers change the phone; the second change is newer }
  C := JObject(['id', Id, 'phone', '111']);
  Desk.Save(skCustomer, C);
  C.Free;
  Sleep(5);
  C := JObject(['id', Id, 'phone', '222']);
  Desk2.Save(skCustomer, C);
  C.Free;
  Sync(Desk2);
  Sync(Desk);         { sends 111 (older): the server keeps 222 and sends it back }
  C := Desk.Get(skCustomer, Id);
  try
    AssertEquals('222', JStr(C, 'phone'));
  finally
    C.Free;
  end;
end;

procedure TStoreTests.DeletionsAreSynced;
var
  Id: string;
begin
  Id := Customer('Ayşe');
  Sync(Desk);
  Sync(Desk2);
  Desk2.Delete(skCustomer, Id);
  Sync(Desk2);
  Sync(Desk);
  AssertNil(Desk.Get(skCustomer, Id));
  AssertEquals(0, Server.Count(skCustomer));
end;

procedure TStoreTests.SyncingTwiceChangesNothing;
var
  Mine: TJSONObject;
begin
  Customer('Ayşe');
  Mine := Desk.Changes('', True);
  try
    AssertEquals(1, Server.Apply(Mine, True));
    AssertEquals(0, Server.Apply(Mine, True), 'the same version again');
  finally
    Mine.Free;
  end;
end;

initialization
  RegisterTests(TStoreTests);
end.
