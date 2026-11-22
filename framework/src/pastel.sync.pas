(* Pastel - data that works offline and is synchronized with a server: the
  desktop (or phone) keeps its own SQLite file, works without a network, and
  exchanges the changes with the server when it can.

    Store := TSyncStore.Create(TDatabase.Open('sqlite:shop.db'), True);
    Store.AddTable('customers', 'name varchar(200) not null, ' +
      'phone varchar(50) not null default '''', notes text');
    Store.OnCheck := @CheckRecord;                 // raise ESyncInvalid for wrong values
    Store.CreateTables;

    Id := Store.Save('customers', JObject(['name', 'Ayşe Yılmaz']));   // a new id; checked
    Rows := Store.List('customers', 'lower(name) like ?', ['%ayşe%'], 'name');
    Store.Delete('customers', Id);                 // marked, so the deletion travels too

    R := SyncWithServer(Store, 'https://shop.example.com', ApiKey, LastSync);   // the client
    AddSyncRoute(Web, ServerStore);                // the server (Pastel.SyncWeb): POST /api/sync

  How it works: every record gets its id where it is made (16 random
  characters, so computers never clash), and updated_at, the time of its
  last change (UTC, sortable as text). A client marks what it changes
  (dirty), sends it, and takes what the server got from others since its
  last sync. When a record was changed on both sides, the newer change wins;
  sending the same records twice changes nothing. Records are never really
  deleted, only marked (deleted = 1). The server's clock decides what is new
  for a client (synced_at), so clocks of the computers may be wrong.

  The salon example (examples/salon-core) is built on it.
  Part of the Pastel project, MIT License. *)
unit Pastel.Sync;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.Db;

type
  ESyncInvalid = class(Exception);

  TSyncCheckEvent = procedure(const Table: string; Data: TJSONObject) of object;

  TSyncResult = record
    Sent, Received: Integer;
  end;

  TSyncStore = class
  private
    FDb: TDatabase;
    FOwnsDb, FServer: Boolean;
    FTables: TStringList;         { name -> its SQL columns; Objects: TStringList of field names }
    FOnCheck: TSyncCheckEvent;
    function FieldsOf(const Table: string): TStringList;
    procedure Write(Session: TDbSession; const Table: string; Data: TJSONObject; const Id: string; Exists: Boolean);
    procedure DoCheck(const Table: string; Data: TJSONObject);
  public
    constructor Create(ADb: TDatabase; OwnsDb: Boolean = False);
    destructor Destroy; override;
    { A table that is synchronized: its columns as SQL, without the ones
      every table gets (id, updated_at, synced_at, dirty, deleted). }
    procedure AddTable(const Name, Columns: string);
    { The tables, when they are missing. }
    procedure CreateTables;
    function Tables: TStringArray;
    function Fields(const Table: string): TStringArray;

    { Checks and stores a record: a new one without "id", else the one with
      this id (values not given keep theirs). Returns the id. }
    function Save(const Table: string; Data: TJSONObject): string;
    { One record, nil when there is none (or it is deleted); the caller frees it. }
    function Get(const Table, Id: string): TJSONObject;
    procedure Delete(const Table, Id: string);
    { The records that are not deleted. Where: more conditions ('status = ?'),
      OrderBy: 'name' (default: updated_at). The caller frees it. }
    function List(const Table: string; const Where: string = ''; const Params: array of const;
      const OrderBy: string = ''): TJSONArray;
    function List(const Table: string): TJSONArray;
    function Count(const Table: string): Integer;

    { ---- synchronization ---- }
    { The records changed here: on a client the dirty ones (Since ignored),
      on the server those stored after Since (its clock). An object with one
      array per table. }
    function Changes(const Since: string; Dirty: Boolean): TJSONObject;
    { Takes records from the other side; returns how many were newer and stored. }
    function Apply(Data: TJSONObject): Integer;
    { After the server took them: not dirty any more (unless changed again meanwhile). }
    procedure MarkSent(Data: TJSONObject);
    { The number of records waiting to be sent. }
    function Pending: Integer;

    property Db: TDatabase read FDb;
    { True on the server: Save and Apply stamp records with the server's
      clock, so clients get them on their next sync. }
    property IsServer: Boolean read FServer write FServer;
    { Checks a record before it is stored (also records that come with a
      sync): raise ESyncInvalid with a message for the user. }
    property OnCheck: TSyncCheckEvent read FOnCheck write FOnCheck;
  end;

{ The current time as records are stamped: '2026-11-01T09:30:00.123000Z';
  always larger than the one before, also in the same millisecond. }
function SyncStamp: string;
{ A new id: 16 random characters. }
function NewSyncId: string;
{ A client's sync: sends what changed here to Url + Path (POST, JSON), takes
  what changed there. LastSync: the server's time of the last sync, kept by
  the caller ('' the first time). EHttpError when the server cannot be
  reached; nothing is lost, the changes go next time. }
function SyncWithServer(Store: TSyncStore; const Url, ApiKey: string; var LastSync: string;
  const Path: string = '/api/sync'): TSyncResult;
(* What the server does with a sync request: {"since": "...", "changes": {...}}
  -> {"now": "...", "applied": 2, "changes": {...}} (Pastel.SyncWeb uses it). *)
function AnswerSync(Store: TSyncStore; Request: TJSONObject): TJSONObject;

implementation

uses
  DateUtils, Pastel.Json, Pastel.Crypto, Pastel.Http;

const
  CommonColumns = 'id varchar(32) primary key, updated_at varchar(32) not null, ' +
    'synced_at varchar(32) not null default '''', dirty integer not null default 0, ' +
    'deleted integer not null default 0';
  Bookkeeping: array[0..3] of string = ('updated_at', 'synced_at', 'dirty', 'deleted');

var
  StampLock: TRTLCriticalSection;
  LastMs: string = '';
  StampCount: Integer = 0;

function SyncStamp: string;
var
  Ms: string;
begin
  EnterCriticalSection(StampLock);
  try
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

function NewSyncId: string;
begin
  Result := Copy(RandomToken(16), 1, 16);
end;

{ the names of the columns in SQL like 'name varchar(200) not null, phone text' }
function ColumnNames(const Columns: string): TStringList;
var
  Depth, I, Start: Integer;
  Part, First: string;

  procedure Take(const P: string);
  begin
    First := LowerCase(Trim(P));
    if Pos(' ', First) > 0 then
      First := Copy(First, 1, Pos(' ', First) - 1);
    First := StringReplace(First, '"', '', [rfReplaceAll]);
    if (First <> '') and (First <> 'primary') and (First <> 'unique') and (First <> 'foreign') and
       (First <> 'constraint') and (First <> 'check') then
      Result.Add(First);
  end;

begin
  Result := TStringList.Create;
  Depth := 0;
  Start := 1;
  for I := 1 to Length(Columns) do
    case Columns[I] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      ',':
        if Depth = 0 then
        begin
          Part := Copy(Columns, Start, I - Start);
          Take(Part);
          Start := I + 1;
        end;
    end;
  Take(Copy(Columns, Start, MaxInt));
end;

{ JSON values as an array of const for Pastel.Db }
procedure ExecJson(Session: TDbSession; const SQL: string; Params: TJSONArray);
var
  V: array of TVarRec;
  S: array of AnsiString;
  I64: array of Int64;
  F: array of Extended;
  I: Integer;
begin
  SetLength(V, Params.Count);
  SetLength(S, Params.Count);
  SetLength(I64, Params.Count);
  SetLength(F, Params.Count);
  for I := 0 to Params.Count - 1 do
    case Params[I].JSONType of
      jtNumber:
        if Params[I] is TJSONFloatNumber then
        begin
          F[I] := Params[I].AsFloat;
          V[I].VType := vtExtended;
          V[I].VExtended := @F[I];
        end
        else
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
      jtArray, jtObject:
        begin
          S[I] := Params[I].AsJSON;
          V[I].VType := vtAnsiString;
          V[I].VAnsiString := Pointer(S[I]);
        end;
    else
      S[I] := Params[I].AsString;
      V[I].VType := vtAnsiString;
      V[I].VAnsiString := Pointer(S[I]);
    end;
  Session.Exec(SQL, V);
end;

{ ---- TSyncStore ---- }

constructor TSyncStore.Create(ADb: TDatabase; OwnsDb: Boolean);
begin
  inherited Create;
  FDb := ADb;
  FOwnsDb := OwnsDb;
  FTables := TStringList.Create;
  FTables.OwnsObjects := True;
end;

destructor TSyncStore.Destroy;
begin
  FTables.Free;
  if FOwnsDb then
    FDb.Free;
  inherited Destroy;
end;

procedure TSyncStore.AddTable(const Name, Columns: string);
var
  F: TStringList;
  B: string;
begin
  if FTables.IndexOfName(Name) >= 0 then
    raise ESyncInvalid.CreateFmt('the table %s is there already', [Name]);
  F := ColumnNames(Columns);
  for B in Bookkeeping do
    if F.IndexOf(B) >= 0 then
    begin
      F.Free;
      raise ESyncInvalid.CreateFmt('%s: the column %s is made by Pastel.Sync; leave it out', [Name, B]);
    end;
  FTables.AddObject(Name + '=' + Columns, F);
end;

function TSyncStore.FieldsOf(const Table: string): TStringList;
var
  I: Integer;
begin
  I := FTables.IndexOfName(Table);
  if I < 0 then
    raise ESyncInvalid.CreateFmt('%s is not a table of this store (AddTable)', [Table]);
  Result := TStringList(FTables.Objects[I]);
end;

function TSyncStore.Fields(const Table: string): TStringArray;
begin
  Result := FieldsOf(Table).ToStringArray;
end;

function TSyncStore.Tables: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, FTables.Count);
  for I := 0 to FTables.Count - 1 do
    Result[I] := FTables.Names[I];
end;

procedure TSyncStore.CreateTables;
var
  I: Integer;
begin
  for I := 0 to FTables.Count - 1 do
  begin
    FDb.Exec('create table if not exists ' + FTables.Names[I] + ' (' + CommonColumns + ', ' +
      FTables.ValueFromIndex[I] + ')', []);
    FDb.Exec('create index if not exists ' + FTables.Names[I] + '_synced on ' + FTables.Names[I] + ' (synced_at)', []);
  end;
end;

procedure TSyncStore.DoCheck(const Table: string; Data: TJSONObject);
begin
  if Assigned(FOnCheck) then
    FOnCheck(Table, Data);
end;

procedure TSyncStore.Write(Session: TDbSession; const Table: string; Data: TJSONObject; const Id: string;
  Exists: Boolean);
var
  Names: TStringList;
  Cols: array of string;
  SQL, Marks: string;
  I: Integer;
  P: TJSONArray;
  V: TJSONData;
  B: string;
begin
  Names := FieldsOf(Table);
  Cols := nil;
  P := TJSONArray.Create;
  try
    for I := 0 to Names.Count - 1 do
    begin
      V := Data.Find(Names[I]);
      { a new record without a value: the column's default }
      if not Exists and ((V = nil) or (V.JSONType = jtNull)) then
        Continue;
      Cols := Concat(Cols, [Names[I]]);
      if V = nil then P.Add(TJSONNull.Create) else P.Add(V.Clone);
    end;
    for B in Bookkeeping do
    begin
      Cols := Concat(Cols, [B]);
      V := Data.Find(B);
      if V = nil then P.Add(TJSONNull.Create) else P.Add(V.Clone);
    end;
    if Exists then
    begin
      SQL := 'update ' + Table + ' set ';
      for I := 0 to High(Cols) do
      begin
        if I > 0 then SQL := SQL + ', ';
        SQL := SQL + Cols[I] + ' = ?';
      end;
      SQL := SQL + ' where id = ?';
      P.Add(Id);
    end
    else
    begin
      SQL := 'insert into ' + Table + ' (id';
      Marks := '?';
      for I := 0 to High(Cols) do
      begin
        SQL := SQL + ', ' + Cols[I];
        Marks := Marks + ', ?';
      end;
      SQL := SQL + ') values (' + Marks + ')';
      P.Insert(0, TJSONString.Create(Id));
    end;
    ExecJson(Session, SQL, P);
  finally
    P.Free;
  end;
end;

function TSyncStore.Save(const Table: string; Data: TJSONObject): string;
var
  Old, Merged: TJSONObject;
  I: Integer;
begin
  FieldsOf(Table);
  Result := JStr(Data, 'id');
  Old := nil;
  if Result <> '' then
    Old := FDb.QueryOne('select * from ' + Table + ' where id = ?', [Result]);
  if Old <> nil then
    Merged := Old
  else
    Merged := TJSONObject.Create;
  try
    for I := 0 to Data.Count - 1 do
      if (Data.Names[I] <> 'id') and (Data.Names[I] <> 'updated_at') and (Data.Names[I] <> 'synced_at') and
         (Data.Names[I] <> 'dirty') then
        Merged.Elements[Data.Names[I]] := Data.Items[I].Clone;
    DoCheck(Table, Merged);
    if Result = '' then
      Result := NewSyncId;
    Merged.Strings['updated_at'] := SyncStamp;
    if FServer then
    begin
      Merged.Strings['synced_at'] := SyncStamp;
      Merged.Integers['dirty'] := 0;
    end
    else
    begin
      Merged.Integers['dirty'] := 1;
      if Merged.Find('synced_at') = nil then
        Merged.Strings['synced_at'] := '';
    end;
    if (Merged.Find('deleted') = nil) or (Merged.Find('deleted').JSONType = jtNull) then
      Merged.Integers['deleted'] := 0;
    Write(FDb, Table, Merged, Result, Old <> nil);
  finally
    Merged.Free;
  end;
end;

function TSyncStore.Get(const Table, Id: string): TJSONObject;
begin
  FieldsOf(Table);
  Result := FDb.QueryOne('select * from ' + Table + ' where id = ? and deleted = 0', [Id]);
end;

procedure TSyncStore.Delete(const Table, Id: string);
begin
  FieldsOf(Table);
  if FServer then
    FDb.Exec('update ' + Table + ' set deleted = 1, dirty = 0, updated_at = ?, synced_at = ? where id = ?',
      [SyncStamp, SyncStamp, Id])
  else
    FDb.Exec('update ' + Table + ' set deleted = 1, dirty = 1, updated_at = ? where id = ?', [SyncStamp, Id]);
end;

function TSyncStore.List(const Table, Where: string; const Params: array of const; const OrderBy: string): TJSONArray;
var
  SQL: string;
begin
  FieldsOf(Table);
  SQL := 'select * from ' + Table + ' where deleted = 0';
  if Where <> '' then
    SQL := SQL + ' and (' + Where + ')';
  if OrderBy <> '' then
    SQL := SQL + ' order by ' + OrderBy
  else
    SQL := SQL + ' order by updated_at';
  Result := FDb.Query(SQL, Params);
end;

function TSyncStore.List(const Table: string): TJSONArray;
begin
  Result := List(Table, '', [], '');
end;

function TSyncStore.Count(const Table: string): Integer;
begin
  FieldsOf(Table);
  Result := FDb.QueryInt('select count(*) from ' + Table + ' where deleted = 0', []);
end;

function TSyncStore.Changes(const Since: string; Dirty: Boolean): TJSONObject;
var
  I, J: Integer;
  Rows: TJSONArray;
  Name: string;
begin
  Result := TJSONObject.Create;
  for I := 0 to FTables.Count - 1 do
  begin
    Name := FTables.Names[I];
    if Dirty then
      Rows := FDb.Query('select * from ' + Name + ' where dirty = 1 order by updated_at', [])
    else
      Rows := FDb.Query('select * from ' + Name + ' where synced_at > ? order by synced_at', [Since]);
    { what only this side needs to know stays here }
    for J := 0 to Rows.Count - 1 do
    begin
      Rows.Objects[J].Delete('dirty');
      Rows.Objects[J].Delete('synced_at');
    end;
    Result.Add(Name, Rows);
  end;
end;

function TSyncStore.Apply(Data: TJSONObject): Integer;
var
  I, J: Integer;
  Rows: TJSONArray;
  R, Old: TJSONObject;
  Tx: TDbTransaction;
  Stamp, Name: string;
begin
  Result := 0;
  Stamp := SyncStamp;
  Tx := FDb.BeginTransaction;
  try
    for I := 0 to FTables.Count - 1 do
    begin
      Name := FTables.Names[I];
      if not (Data.Find(Name) is TJSONArray) then
        Continue;
      Rows := TJSONArray(Data.Find(Name));
      for J := 0 to Rows.Count - 1 do
      begin
        if not (Rows[J] is TJSONObject) then
          Continue;
        R := TJSONObject(Rows[J].Clone);
        try
          if (JStr(R, 'id') = '') or (JStr(R, 'updated_at') = '') then
            raise ESyncInvalid.CreateFmt('a record of %s without id or updated_at', [Name]);
          if JInt(R, 'deleted') = 0 then
            DoCheck(Name, R);       { the other side may be an old or a broken program }
          Old := Tx.QueryOne('select updated_at from ' + Name + ' where id = ?', [JStr(R, 'id')]);
          try
            { the newer version wins; the same version again changes nothing }
            if (Old <> nil) and (JStr(Old, 'updated_at') >= JStr(R, 'updated_at')) then
              Continue;
            if FServer then
              R.Strings['synced_at'] := Stamp
            else
              R.Strings['synced_at'] := '';
            R.Integers['dirty'] := 0;
            if R.Find('deleted') = nil then
              R.Integers['deleted'] := 0;
            Write(Tx, Name, R, JStr(R, 'id'), Old <> nil);
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

procedure TSyncStore.MarkSent(Data: TJSONObject);
var
  I, J: Integer;
  Rows: TJSONArray;
  Name: string;
begin
  for I := 0 to FTables.Count - 1 do
  begin
    Name := FTables.Names[I];
    if Data.Find(Name) is TJSONArray then
    begin
      Rows := TJSONArray(Data.Find(Name));
      for J := 0 to Rows.Count - 1 do
        FDb.Exec('update ' + Name + ' set dirty = 0 where id = ? and updated_at = ?',
          [JStr(Rows[J], 'id'), JStr(Rows[J], 'updated_at')]);
    end;
  end;
end;

function TSyncStore.Pending: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FTables.Count - 1 do
    Inc(Result, FDb.QueryInt('select count(*) from ' + FTables.Names[I] + ' where dirty = 1', []));
end;

{ ---- client and server ---- }

function CountRows(Data: TJSONObject): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Data.Count - 1 do
    if Data.Items[I] is TJSONArray then
      Inc(Result, Data.Items[I].Count);
end;

function SyncWithServer(Store: TSyncStore; const Url, ApiKey: string; var LastSync: string;
  const Path: string): TSyncResult;
var
  Client: THttpClient;
  Mine, Body: TJSONObject;
  Answer: TJSONData;
  R: THttpResponse;
begin
  Result.Sent := 0;
  Result.Received := 0;
  Mine := Store.Changes('', True);
  Body := TJSONObject.Create;
  Client := THttpClient.Create(Url);
  try
    Body.Strings['since'] := LastSync;
    Body.Add('changes', Mine.Clone);
    if ApiKey <> '' then
      Client.Headers := ['X-API-Key: ' + ApiKey];
    Client.Timeout := 15000;
    R := Client.PostJson(Path, Body);
    R.RaiseForStatus;
    Answer := R.Json;
    try
      if not (Answer is TJSONObject) or not (TJSONObject(Answer).Find('changes') is TJSONObject) then
        raise EHttpError.Create('the server''s answer is not a sync answer');
      { theirs first: our records that changed meanwhile stay newer }
      Result.Received := Store.Apply(TJSONObject(TJSONObject(Answer).Find('changes')));
      Store.MarkSent(Mine);
      Result.Sent := CountRows(Mine);
      LastSync := JStr(Answer, 'now', LastSync);
    finally
      Answer.Free;
    end;
  finally
    Client.Free;
    Body.Free;
    Mine.Free;
  end;
end;

function AnswerSync(Store: TSyncStore; Request: TJSONObject): TJSONObject;
var
  Now_, Since: string;
  Applied: Integer;
begin
  if not (Request.Find('changes') is TJSONObject) then
    raise ESyncInvalid.Create('changes is required (an object with one array per table)');
  Since := JStr(Request, 'since');
  { the time before taking anything: what others send meanwhile comes next time }
  Now_ := SyncStamp;
  Applied := Store.Apply(TJSONObject(Request.Find('changes')));
  Result := TJSONObject.Create;
  Result.Strings['now'] := Now_;
  Result.Integers['applied'] := Applied;
  Result.Add('changes', Store.Changes(Since, False));
end;

initialization
  InitCriticalSection(StampLock);

finalization
  DoneCriticalSection(StampLock);

end.
