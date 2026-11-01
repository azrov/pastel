{ The salon's data in a database: customers, appointments and invoices.

    Store := TSalonStore.Create(TDatabase.Open('sqlite:salon.db'), True);
    Store.CreateTables;

    C := JObject(['name', 'Ayşe Yılmaz', 'phone', '0532 111 22 33']);
    Id := Store.Save(skCustomer, C);               // checks it; a new id
    Rows := Store.List(skCustomer, 'ayşe');        // name, phone or e-mail contain it

  The same unit runs in the desktop app (SQLite on the computer) and on the
  server (PostgreSQL, MySQL or SQLite), so both check and store the data the
  same way. Every record has a text id that is made where the record is
  made, so records from several computers never clash, and updated_at, the
  time of the last change; synchronization keeps the newer version
  (see Changes and Apply).
  Records are never deleted, only marked (deleted = 1), so a deletion
  reaches the other computers too. }
unit SalonStore;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.Db;

type
  TSalonKind = (skCustomer, skAppointment, skInvoice);

  ESalonInvalid = class(Exception);

  TSalonStore = class
  private
    FDb: TDatabase;
    FOwnsDb: Boolean;
    function Fields(Kind: TSalonKind): TStringArray;
    procedure Check(Kind: TSalonKind; Data: TJSONObject);
    procedure Write(Session: TDbSession; Kind: TSalonKind; Data: TJSONObject; const Id: string; Exists: Boolean);
  public
    constructor Create(ADb: TDatabase; OwnsDb: Boolean = False);
    destructor Destroy; override;
    { The tables, when they are missing (every database Pastel.Db knows). }
    procedure CreateTables;

    { Checks and stores a record: a new one without "id", else the one with
      this id. The values not given keep theirs. Returns the id.
      ESalonInvalid when a value is wrong. }
    function Save(Kind: TSalonKind; Data: TJSONObject): string;
    { One record; nil when there is none (or it is deleted). The caller frees it. }
    function Get(Kind: TSalonKind; const Id: string): TJSONObject;
    { Marks it deleted. }
    procedure Delete(Kind: TSalonKind; const Id: string);
    { The records that are not deleted; Filter: customers whose name, phone or
      e-mail contain it. Sorted by name / time / number. The caller frees it. }
    function List(Kind: TSalonKind; const Filter: string = ''): TJSONArray;
    { The appointments of one day ('2026-11-03'), with the customer's name. }
    function Day(const DateIso: string): TJSONArray;
    { The appointments of a customer that are done and not invoiced yet. }
    function Uninvoiced(const CustomerId: string): TJSONArray;
    { An invoice for these appointments: one line each, VAT on top, the next
      number of the year ('2026-0007'); the appointments are marked invoiced. }
    function Invoice(const CustomerId: string; const AppointmentIds: array of string;
      VatRate: Integer = 20): string;
    function Count(Kind: TSalonKind): Integer;

    { ---- synchronization ----
      The desktop sends its Changes (the records changed since its last sync,
      marked dirty) to the server, which Applies them and answers with what
      changed there since that client's last sync. Apply keeps whichever
      version of a record is newer (updated_at), so applying the same records
      twice changes nothing. }

    { The records changed here: on the desktop the dirty ones (Since ignored),
      on the server those stored after Since (synced_at, the server's clock).
      An object with the arrays customers, appointments and invoices. }
    function Changes(const Since: string; Dirty: Boolean): TJSONObject;
    { Takes records from the other side; returns how many were newer and
      stored. Server: stamps them with its clock (synced_at). Desktop: they
      are not dirty (they came from the server). }
    function Apply(Data: TJSONObject; Server: Boolean): Integer;
    { After the server took them: these records are not dirty any more
      (unless they changed again meanwhile: their updated_at is newer). }
    procedure MarkSent(Data: TJSONObject);
    property Db: TDatabase read FDb;
  end;

const
  KindTables: array[TSalonKind] of string = ('customers', 'appointments', 'invoices');
  AppointmentStatuses: array[0..3] of string = ('booked', 'done', 'cancelled', 'invoiced');

{ The current time as the store writes it: '2026-11-01T09:30:00.123000Z' (UTC, sortable as text). }
function NowStamp: string;
{ A new id: 16 random characters. }
function NewId: string;

implementation

uses
  DateUtils, Pastel.Json, Pastel.Crypto, SalonMoney;

var
  StampLock: TRTLCriticalSection;
  LastMs: string = '';
  StampCount: Integer = 0;

function NowStamp: string;
var
  Ms: string;
begin
  EnterCriticalSection(StampLock);
  try
    { milliseconds and a counter: two changes in the same millisecond still
      get different stamps, in the right order }
    Ms := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', LocalTimeToUniversal(Now));
    if Ms = LastMs then
      Inc(StampCount)
    else
    begin
      LastMs := Ms;
      StampCount := 0;
    end;
    Result := Format('%s%.3dZ', [Ms, StampCount mod 1000]);
  finally
    LeaveCriticalSection(StampLock);
  end;
end;

function NewId: string;
begin
  Result := Copy(RandomToken(16), 1, 16);
end;

constructor TSalonStore.Create(ADb: TDatabase; OwnsDb: Boolean);
begin
  inherited Create;
  FDb := ADb;
  FOwnsDb := OwnsDb;
end;

destructor TSalonStore.Destroy;
begin
  if FOwnsDb then
    FDb.Free;
  inherited Destroy;
end;

function TSalonStore.Fields(Kind: TSalonKind): TStringArray;
begin
  case Kind of
    skCustomer: Result := ['name', 'phone', 'email', 'notes'];
    skAppointment: Result := ['customer_id', 'starts_at', 'minutes', 'service', 'price_cents', 'status'];
    skInvoice: Result := ['customer_id', 'number', 'issued_on', 'lines', 'net_cents', 'vat_rate', 'vat_cents',
        'total_cents', 'paid'];
  end;
end;

procedure TSalonStore.CreateTables;
const
  Common = 'id varchar(32) primary key, updated_at varchar(32) not null, synced_at varchar(32) not null default '''', ' +
    'dirty integer not null default 0, deleted integer not null default 0';
begin
  FDb.Exec('create table if not exists customers (' + Common + ', name varchar(200) not null, ' +
    'phone varchar(50) not null default '''', email varchar(200) not null default '''', notes text)', []);
  FDb.Exec('create table if not exists appointments (' + Common + ', customer_id varchar(32) not null, ' +
    'starts_at varchar(16) not null, minutes integer not null default 30, service varchar(200) not null default '''', ' +
    'price_cents bigint not null default 0, status varchar(20) not null default ''booked'')', []);
  FDb.Exec('create table if not exists invoices (' + Common + ', customer_id varchar(32) not null, ' +
    'number varchar(20) not null, issued_on varchar(10) not null, lines text, net_cents bigint not null default 0, ' +
    'vat_rate integer not null default 20, vat_cents bigint not null default 0, ' +
    'total_cents bigint not null default 0, paid integer not null default 0)', []);
end;

procedure Invalid(const Msg: string; const Args: array of const);
begin
  raise ESalonInvalid.CreateFmt(Msg, Args);
end;

procedure TSalonStore.Check(Kind: TSalonKind; Data: TJSONObject);
var
  S: string;
  D: TDateTime;
  I: Integer;
  Ok: Boolean;
begin
  case Kind of
    skCustomer:
      begin
        if Trim(JStr(Data, 'name')) = '' then
          Invalid('a customer needs a name', []);
        S := Trim(JStr(Data, 'email'));
        if (S <> '') and ((Pos('@', S) < 2) or (Pos('.', Copy(S, Pos('@', S), MaxInt)) = 0)) then
          Invalid('"%s" is not an e-mail address', [S]);
      end;
    skAppointment:
      begin
        if JStr(Data, 'customer_id') = '' then
          Invalid('an appointment needs a customer', []);
        S := JStr(Data, 'starts_at');
        if not ((Length(S) = 16) and (S[11] = ' ') and TryEncodeDateTime(StrToIntDef(Copy(S, 1, 4), 0),
          StrToIntDef(Copy(S, 6, 2), 0), StrToIntDef(Copy(S, 9, 2), 0), StrToIntDef(Copy(S, 12, 2), 99),
          StrToIntDef(Copy(S, 15, 2), 99), 0, 0, D)) then
          Invalid('"%s" is not a time like 2026-11-03 14:30', [S]);
        if (JInt(Data, 'minutes', 30) < 5) or (JInt(Data, 'minutes', 30) > 600) then
          Invalid('an appointment takes 5 to 600 minutes', []);
        if JInt(Data, 'price_cents') < 0 then
          Invalid('a price cannot be negative', []);
        S := JStr(Data, 'status', 'booked');
        Ok := False;
        for I := 0 to High(AppointmentStatuses) do
          Ok := Ok or (S = AppointmentStatuses[I]);
        if not Ok then
          Invalid('"%s" is not a status (booked, done, cancelled, invoiced)', [S]);
      end;
    skInvoice:
      if JStr(Data, 'customer_id') = '' then
        Invalid('an invoice needs a customer', []);
  end;
end;

{ every field of the kind from Data, in the order of Fields }
function Values(const Names: TStringArray; Data: TJSONObject): TJSONArray;
var
  N: string;
  V: TJSONData;
begin
  Result := TJSONArray.Create;
  for N in Names do
  begin
    V := Data.Find(N);
    if (V = nil) or (V.JSONType = jtNull) then
      Result.Add(TJSONNull.Create)
    else
      Result.Add(V.Clone);
  end;
end;

{ the values of a JSON array as an array of const for Pastel.Db }
procedure Exec(Session: TDbSession; const SQL: string; Params: TJSONArray);
var
  V: array of TVarRec;
  S: array of AnsiString;
  I64: array of Int64;
  I: Integer;
begin
  SetLength(V, Params.Count);
  SetLength(S, Params.Count);
  SetLength(I64, Params.Count);
  for I := 0 to Params.Count - 1 do
    case Params[I].JSONType of
      jtNumber:
        begin
          I64[I] := Params[I].AsInt64;
          V[I].VType := vtInt64;
          V[I].VInt64 := @I64[I];
        end;
      jtBoolean:
        begin
          I64[I] := Ord(Params[I].AsBoolean);
          V[I].VType := vtInt64;
          V[I].VInt64 := @I64[I];
        end;
      jtNull:
        begin
          V[I].VType := vtPointer;
          V[I].VPointer := nil;
        end;
    else
      S[I] := Params[I].AsString;
      V[I].VType := vtAnsiString;
      V[I].VAnsiString := Pointer(S[I]);
    end;
  Session.Exec(SQL, V);
end;

procedure TSalonStore.Write(Session: TDbSession; Kind: TSalonKind; Data: TJSONObject; const Id: string;
  Exists: Boolean);
var
  Names: TStringArray;
  SQL, Marks: string;
  I: Integer;
  P: TJSONArray;
begin
  Names := Fields(Kind);
  Names := Concat(Names, ['updated_at', 'synced_at', 'dirty', 'deleted']);
  P := Values(Names, Data);
  try
    if Exists then
    begin
      SQL := 'update ' + KindTables[Kind] + ' set ';
      for I := 0 to High(Names) do
      begin
        if I > 0 then SQL := SQL + ', ';
        SQL := SQL + Names[I] + ' = ?';
      end;
      SQL := SQL + ' where id = ?';
      P.Add(Id);
    end
    else
    begin
      SQL := 'insert into ' + KindTables[Kind] + ' (id';
      Marks := '?';
      for I := 0 to High(Names) do
      begin
        SQL := SQL + ', ' + Names[I];
        Marks := Marks + ', ?';
      end;
      SQL := SQL + ') values (' + Marks + ')';
      P.Insert(0, TJSONString.Create(Id));
    end;
    Exec(Session, SQL, P);
  finally
    P.Free;
  end;
end;

{ the values a new record has when they are not given }
procedure AddDefaults(Kind: TSalonKind; Data: TJSONObject);

  procedure Default(const Name: string; Value: TJSONData);
  begin
    if (Data.Find(Name) = nil) or (Data.Find(Name).JSONType = jtNull) then
      Data.Elements[Name] := Value
    else
      Value.Free;
  end;

begin
  case Kind of
    skCustomer:
      begin
        Default('phone', TJSONString.Create(''));
        Default('email', TJSONString.Create(''));
        Default('notes', TJSONString.Create(''));
      end;
    skAppointment:
      begin
        Default('minutes', TJSONIntegerNumber.Create(30));
        Default('service', TJSONString.Create(''));
        Default('price_cents', TJSONInt64Number.Create(0));
        Default('status', TJSONString.Create('booked'));
      end;
    skInvoice:
      begin
        Default('lines', TJSONString.Create('[]'));
        Default('net_cents', TJSONInt64Number.Create(0));
        Default('vat_rate', TJSONIntegerNumber.Create(20));
        Default('vat_cents', TJSONInt64Number.Create(0));
        Default('total_cents', TJSONInt64Number.Create(0));
        Default('paid', TJSONIntegerNumber.Create(0));
      end;
  end;
end;

function TSalonStore.Get(Kind: TSalonKind; const Id: string): TJSONObject;
begin
  Result := FDb.QueryOne('select * from ' + KindTables[Kind] + ' where id = ? and deleted = 0', [Id]);
end;

function TSalonStore.Save(Kind: TSalonKind; Data: TJSONObject): string;
var
  Old, Merged: TJSONObject;
  I: Integer;
begin
  Result := JStr(Data, 'id');
  Old := nil;
  if Result <> '' then
    Old := FDb.QueryOne('select * from ' + KindTables[Kind] + ' where id = ?', [Result]);
  { the stored record with the new values over it }
  if Old <> nil then
    Merged := Old
  else
    Merged := TJSONObject.Create;
  try
    for I := 0 to Data.Count - 1 do
      Merged.Elements[Data.Names[I]] := Data.Items[I].Clone;
    if Old = nil then
      AddDefaults(Kind, Merged);
    if Kind = skCustomer then
    begin
      Merged.Strings['name'] := Trim(JStr(Merged, 'name'));
      Merged.Strings['email'] := Trim(JStr(Merged, 'email'));
    end;
    if (Kind = skAppointment) and (JStr(Merged, 'status') = '') then
      Merged.Strings['status'] := 'booked';
    Check(Kind, Merged);
    if Result = '' then
      Result := NewId;
    Merged.Strings['updated_at'] := NowStamp;
    Merged.Integers['dirty'] := 1;
    if Merged.Find('deleted') = nil then
      Merged.Integers['deleted'] := 0;
    if Merged.Find('synced_at') = nil then
      Merged.Strings['synced_at'] := '';
    Write(FDb, Kind, Merged, Result, Old <> nil);
  finally
    Merged.Free;
  end;
end;

procedure TSalonStore.Delete(Kind: TSalonKind; const Id: string);
begin
  FDb.Exec('update ' + KindTables[Kind] + ' set deleted = 1, dirty = 1, updated_at = ? where id = ?', [NowStamp, Id]);
end;

function TSalonStore.List(Kind: TSalonKind; const Filter: string): TJSONArray;
var
  Like: string;
begin
  case Kind of
    skCustomer:
      begin
        Like := '%' + LowerCase(Trim(Filter)) + '%';
        Result := FDb.Query('select * from customers where deleted = 0 and (lower(name) like ? or phone like ? or ' +
          'lower(email) like ?) order by lower(name), id', [Like, Like, Like]);
      end;
    skAppointment:
      Result := FDb.Query('select * from appointments where deleted = 0 order by starts_at, id', []);
    skInvoice:
      Result := FDb.Query('select i.*, c.name as customer_name from invoices i left join customers c on ' +
        'c.id = i.customer_id where i.deleted = 0 order by i.number desc', []);
  end;
end;

function TSalonStore.Day(const DateIso: string): TJSONArray;
begin
  Result := FDb.Query('select a.*, c.name as customer_name from appointments a left join customers c on ' +
    'c.id = a.customer_id where a.deleted = 0 and a.starts_at like ? order by a.starts_at, a.id', [DateIso + '%']);
end;

function TSalonStore.Uninvoiced(const CustomerId: string): TJSONArray;
begin
  Result := FDb.Query('select * from appointments where deleted = 0 and customer_id = ? and status = ? ' +
    'order by starts_at', [CustomerId, 'done']);
end;

function TSalonStore.Invoice(const CustomerId: string; const AppointmentIds: array of string;
  VatRate: Integer): string;
var
  Lines: TJSONArray;
  A, Inv: TJSONObject;
  Id, Year, Last: string;
  Net: Int64;
  N: Integer;
begin
  if Length(AppointmentIds) = 0 then
    raise ESalonInvalid.Create('there is nothing to invoice');
  Lines := TJSONArray.Create;
  Inv := TJSONObject.Create;
  try
    Net := 0;
    for Id in AppointmentIds do
    begin
      A := Get(skAppointment, Id);
      if A = nil then
        raise ESalonInvalid.CreateFmt('there is no appointment %s', [Id]);
      try
        if JStr(A, 'customer_id') <> CustomerId then
          raise ESalonInvalid.Create('the appointments are of another customer');
        if JStr(A, 'status') <> 'done' then
          raise ESalonInvalid.Create('only done appointments are invoiced');
        Lines.Add(JObject(['description', Copy(JStr(A, 'starts_at'), 1, 10) + ' ' + JStr(A, 'service'),
          'cents', JInt(A, 'price_cents')]));
        Inc(Net, JInt(A, 'price_cents'));
      finally
        A.Free;
      end;
    end;
    { the next number of this year: 2026-0001, 2026-0002, ... }
    Year := FormatDateTime('yyyy', Date);
    Last := FDb.QueryValue('select max(number) from invoices where number like ?', [Year + '-%']);
    N := StrToIntDef(Copy(Last, 6, 10), 0) + 1;
    Inv.Strings['customer_id'] := CustomerId;
    Inv.Strings['number'] := Format('%s-%.4d', [Year, N]);
    Inv.Strings['issued_on'] := FormatDateTime('yyyy-mm-dd', Date);
    Inv.Strings['lines'] := Lines.AsJSON;
    Inv.Int64s['net_cents'] := Net;
    Inv.Integers['vat_rate'] := VatRate;
    Inv.Int64s['vat_cents'] := VatOf(Net, VatRate);
    Inv.Int64s['total_cents'] := Net + VatOf(Net, VatRate);
    Inv.Integers['paid'] := 0;
    Result := Save(skInvoice, Inv);
    for Id in AppointmentIds do
    begin
      A := JObject(['id', Id, 'status', 'invoiced']);
      try
        Save(skAppointment, A);
      finally
        A.Free;
      end;
    end;
  finally
    Lines.Free;
    Inv.Free;
  end;
end;

function TSalonStore.Count(Kind: TSalonKind): Integer;
begin
  Result := FDb.QueryInt('select count(*) from ' + KindTables[Kind] + ' where deleted = 0', []);
end;

function TSalonStore.Changes(const Since: string; Dirty: Boolean): TJSONObject;
var
  K: TSalonKind;
  Rows: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  for K := Low(TSalonKind) to High(TSalonKind) do
  begin
    if Dirty then
      Rows := FDb.Query('select * from ' + KindTables[K] + ' where dirty = 1 order by updated_at', [])
    else
      Rows := FDb.Query('select * from ' + KindTables[K] + ' where synced_at > ? order by synced_at', [Since]);
    { what only this side needs to know stays here }
    for I := 0 to Rows.Count - 1 do
    begin
      Rows.Objects[I].Delete('dirty');
      Rows.Objects[I].Delete('synced_at');
      Rows.Objects[I].Delete('customer_name');
    end;
    Result.Add(KindTables[K], Rows);
  end;
end;

function TSalonStore.Apply(Data: TJSONObject; Server: Boolean): Integer;
var
  K: TSalonKind;
  Rows: TJSONArray;
  R, Old: TJSONObject;
  I: Integer;
  Tx: TDbTransaction;
  Stamp: string;
begin
  Result := 0;
  Stamp := NowStamp;
  Tx := FDb.BeginTransaction;
  try
    for K := Low(TSalonKind) to High(TSalonKind) do
    begin
      if not (Data.Find(KindTables[K]) is TJSONArray) then
        Continue;
      Rows := TJSONArray(Data.Find(KindTables[K]));
      for I := 0 to Rows.Count - 1 do
      begin
        if not (Rows[I] is TJSONObject) then
          Continue;
        R := TJSONObject(Rows[I].Clone);
        try
          if (JStr(R, 'id') = '') or (JStr(R, 'updated_at') = '') then
            raise ESalonInvalid.CreateFmt('a record of %s without id or updated_at', [KindTables[K]]);
          AddDefaults(K, R);   { an older program may not send every field }
          if JInt(R, 'deleted') = 0 then
            Check(K, R);       { the other side may be an old or a broken program }
          Old := Tx.QueryOne('select updated_at, dirty from ' + KindTables[K] + ' where id = ?', [JStr(R, 'id')]);
          try
            { the newer version wins; the same version again changes nothing }
            if (Old <> nil) and (JStr(Old, 'updated_at') >= JStr(R, 'updated_at')) then
              Continue;
            if Server then
              R.Strings['synced_at'] := Stamp
            else
              R.Strings['synced_at'] := '';
            R.Integers['dirty'] := 0;
            if R.Find('deleted') = nil then
              R.Integers['deleted'] := 0;
            Write(Tx, K, R, JStr(R, 'id'), Old <> nil);
            Inc(Result);
          finally
            Old.Free;
          end;
        finally
          R.Free;
        end;
      end;
    end;
    Tx.Commit;
  finally
    Tx.Free;
  end;
end;

procedure TSalonStore.MarkSent(Data: TJSONObject);
var
  K: TSalonKind;
  Rows: TJSONArray;
  I: Integer;
begin
  for K := Low(TSalonKind) to High(TSalonKind) do
    if Data.Find(KindTables[K]) is TJSONArray then
    begin
      Rows := TJSONArray(Data.Find(KindTables[K]));
      for I := 0 to Rows.Count - 1 do
        FDb.Exec('update ' + KindTables[K] + ' set dirty = 0 where id = ? and updated_at = ?',
          [JStr(Rows[I], 'id'), JStr(Rows[I], 'updated_at')]);
    end;
end;

initialization
  InitCriticalSection(StampLock);

finalization
  DoneCriticalSection(StampLock);

end.
