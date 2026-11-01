{ Pastel - databases: SQLite, PostgreSQL, MySQL/MariaDB.

    Db := TDatabase.Open(Config.Require('database.url'));
        // 'sqlite:data/app.db'
        // 'postgres://user:password@localhost:5432/shop'
        // 'mysql://user:password@localhost/shop'
    Db.Migrate;                                          // database/migrations/*.sql

    Rows := Db.Query('select id, name from users where age > ? order by name', [18]);
    User := Db.QueryOne('select * from users where id = ?', [Id]);     // nil when none
    Count := Db.QueryInt('select count(*) from users', []);
    Id := Db.Insert('insert into users (name, email) values (?, ?)', [Name, Email]);
    Changed := Db.Exec('update users set name = ? where id = ?', [Name, Id]);

    Tx := Db.BeginTransaction;
    try
      Tx.Exec('update accounts set balance = balance - ? where id = ?', [Amount, From]);
      Tx.Exec('update accounts set balance = balance + ? where id = ?', [Amount, To_]);
      Tx.Commit;
    finally
      Tx.Free;          // rolls back when Commit was not reached
    end;

  Rows come back as JSON (TJSONArray of TJSONObject, TJSONObject), ready
  for Res.Json and the J... functions of Pastel.Json; the caller frees them.
  Values go in as ? and are never pasted into the SQL, so they cannot
  change it (no SQL injection). A TDatabase can be used from several
  threads at once: it keeps a pool of connections.
  Part of the Pastel project, MIT License. }
unit Pastel.Db;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fpjson, db, sqldb;

type
  EDbError = class(Exception);
  { a unique column or primary key already has this value }
  EDbDuplicate = class(EDbError);

  TDbKind = (dbSQLite, dbPostgres, dbMySQL);

  { Internal: one connection of the pool. }
  TDbConnection = class
  public
    Conn: TSQLConnection;
    Trans: TSQLTransaction;
    InUse: Boolean;
    destructor Destroy; override;
  end;

  TDatabase = class;

  { What TDatabase and TDbTransaction have in common: the queries. }
  TDbSession = class
  protected
    FDb: TDatabase;
    function Acquire: TDbConnection; virtual; abstract;
    procedure Release(C: TDbConnection; Failed: Boolean); virtual; abstract;
  public
    { all rows; the caller frees the result }
    function Query(const SQL: string; const Params: array of const): TJSONArray;
    { the first row, or nil; the caller frees it }
    function QueryOne(const SQL: string; const Params: array of const): TJSONObject;
    { the first column of the first row }
    function QueryValue(const SQL: string; const Params: array of const; const Default: string = ''): string;
    function QueryInt(const SQL: string; const Params: array of const; Default: Int64 = 0): Int64;
    { insert/update/delete/DDL; the number of rows changed }
    function Exec(const SQL: string; const Params: array of const): Int64;
    { an insert; the id of the new row (PostgreSQL: the table needs an "id" column) }
    function Insert(const SQL: string; const Params: array of const): Int64;
  end;

  TDbTransaction = class(TDbSession)
  private
    FConn: TDbConnection;
    FDone: Boolean;
  protected
    function Acquire: TDbConnection; override;
    procedure Release(C: TDbConnection; Failed: Boolean); override;
  public
    constructor Create(ADb: TDatabase);
    { rolls back unless committed }
    destructor Destroy; override;
    procedure Commit;
    procedure Rollback;
  end;

  TDatabase = class(TDbSession)
  private
    FKind: TDbKind;
    FUrl, FHost, FUser, FPassword, FName: string;
    FPort: Integer;
    FPool: TList;
    FLock: TCriticalSection;
    FMaxConnections: Integer;
    function NewConnection: TDbConnection;
    function ToolOptions(out Env: SysUtils.TStringArray): SysUtils.TStringArray;
  protected
    function Acquire: TDbConnection; override;
    procedure Release(C: TDbConnection; Failed: Boolean); override;
  public
    { see the examples above; EDbError when it cannot connect }
    class function Open(const Url: string; MaxConnections: Integer = 10): TDatabase;
    constructor Create(const Url: string; MaxConnections: Integer = 10);
    destructor Destroy; override;
    function BeginTransaction: TDbTransaction;
    // Runs the .sql files in Dir that did not run yet, in name order, each in
    // a transaction, and notes them in the table schema_migrations. In the
    // files, {{id}} stands for an auto-numbered primary key in the way of
    // the database (id {{id}}), so one file works everywhere. Dir ''
    // means database/migrations next to the program, else in the current
    // folder. Returns how many ran.
    function Migrate(const Dir: string = ''): Integer;
    { name=applied/pending for every migration file }
    function MigrationStatus(const Dir: string = ''): TStringList;
    property Kind: TDbKind read FKind;
    { the address without the password }
    function SafeUrl: string;
    { A copy of the whole database in FileName, while it is used. SQLite: a
      database file (VACUUM INTO); PostgreSQL and MySQL: SQL text, made by
      pg_dump or mysqldump (which must be installed). }
    procedure Backup(const FileName: string);
    { A backup into Dir named by the time (shop-2026-11-01-093015-120.db or .sql);
      only the Keep newest backups there stay. Returns the file name. For a
      daily job: Db.BackupTo('backups', 14). }
    function BackupTo(const Dir: string; Keep: Integer = 10): string;
    { Puts a backup back: the database becomes what it was then. SQLite: the
      file replaces the database (nothing else may use it meanwhile);
      PostgreSQL and MySQL: psql or mysql run the SQL. }
    procedure Restore(const FileName: string);
  end;

{ the folder Migrate uses when given '' }
function DefaultMigrationsDir: string;
{ splits a script into statements at ; (not inside quotes or comments) }
function SplitSql(const Script: string): TStringArray;

implementation

uses
  StrUtils, DateUtils, sqlite3dyn, sqlite3conn, pqconnection, mysql57conn, mysql80conn,
  mysql57dyn, mysql80dyn, Pastel.Json, Pastel.Log, Pastel.Files, Pastel.Process;

{ ---------------- helpers ---------------- }

type
  TSQLiteAccess = class(TSQLite3Connection);

function UrlPart(const S: string): string;
var
  I, H: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) and TryStrToInt('$' + Copy(S, I + 1, 2), H) then
    begin
      Result := Result + Chr(H);
      Inc(I, 3);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
end;

{ ? -> :p1, :p2 ... outside quotes }
function NumberParams(const SQL: string; out Count: Integer): string;
var
  I: Integer;
  Quote: Char;
begin
  Result := '';
  Count := 0;
  Quote := #0;
  I := 1;
  while I <= Length(SQL) do
  begin
    if Quote <> #0 then
    begin
      if SQL[I] = Quote then
        Quote := #0;
    end
    else if SQL[I] in ['''', '"', '`'] then
      Quote := SQL[I]
    else if SQL[I] = '?' then
    begin
      Inc(Count);
      Result := Result + ':p' + IntToStr(Count);
      Inc(I);
      Continue;
    end;
    Result := Result + SQL[I];
    Inc(I);
  end;
end;

function CleanMessage(const S: string): string;
var
  I: Integer;
begin
  Result := Trim(S);
  { "TSQLite3Connection : ..." / "PQConnection : ..." }
  I := Pos(' : ', Result);
  if (I > 0) and (I < 30) and (Pos('Connection', Copy(Result, 1, I)) > 0) then
    Delete(Result, 1, I + 2);
  Result := StringReplace(Result, 'Execution of query failed (PGRES_FATAL_ERROR) Server error: ', '', []);
  Result := Trim(StringReplace(Result, LineEnding, ' ', [rfReplaceAll]));
  { PostgreSQL: "Execution of query failed (PostgreSQL: ERROR: ... Primary Error: <the reason>)" }
  I := Pos('Primary Error: ', Result);
  if I > 0 then
  begin
    Result := Trim(Copy(Result, I + 15, MaxInt));
    if (Result <> '') and (Result[Length(Result)] = ')') then
      SetLength(Result, Length(Result) - 1);
  end;
end;

function Wrap(E: Exception; const SQL: string): EDbError;
var
  M: string;
begin
  M := CleanMessage(E.Message);
  if (Pos('UNIQUE constraint failed', M) > 0) or (Pos('duplicate key value', M) > 0) or
     (Pos('Duplicate entry', M) > 0) then
    Result := EDbDuplicate.Create(M)
  else
    Result := EDbError.Create(M + ' (in: ' + Copy(Trim(SQL), 1, 200) + ')');
end;

procedure BindParams(Q: TSQLQuery; const Params: array of const; Count: Integer);
var
  I: Integer;
  P: TParam;
begin
  if Count <> Length(Params) then
    raise EDbError.CreateFmt('the SQL has %d ? but %d value(s) were given', [Count, Length(Params)]);
  for I := 0 to High(Params) do
  begin
    P := Q.Params.ParamByName('p' + IntToStr(I + 1));
    case Params[I].VType of
      vtInteger: P.AsLargeInt := Params[I].VInteger;
      vtInt64: P.AsLargeInt := Params[I].VInt64^;
      vtQWord: P.AsLargeInt := Int64(Params[I].VQWord^);
      vtExtended: P.AsFloat := Params[I].VExtended^;
      vtCurrency: P.AsFloat := Params[I].VCurrency^;
      vtBoolean: P.AsBoolean := Params[I].VBoolean;
      vtAnsiString: P.AsString := AnsiString(Params[I].VAnsiString);
      vtUnicodeString: P.AsString := UTF8Encode(UnicodeString(Params[I].VUnicodeString));
      vtWideString: P.AsString := UTF8Encode(WideString(Params[I].VWideString));
      vtString: P.AsString := Params[I].VString^;
      vtChar: P.AsString := Params[I].VChar;
      vtWideChar: P.AsString := UTF8Encode(UnicodeString(Params[I].VWideChar));
      vtPChar: P.AsString := Params[I].VPChar;
      vtPointer:
        if Params[I].VPointer = nil then
          P.Clear
        else
          raise EDbError.CreateFmt('value %d: pointers cannot be stored', [I + 1]);
    else
      raise EDbError.CreateFmt('value %d: this kind of value cannot be stored', [I + 1]);
    end;
  end;
end;

function FieldToJson(F: TField): TJSONData;
var
  S: string;
begin
  if F.IsNull then
    Exit(TJSONNull.Create);
  case F.DataType of
    ftSmallint, ftInteger, ftWord, ftLargeint, ftAutoInc:
      Result := TJSONInt64Number.Create(F.AsLargeInt);
    ftFloat, ftCurrency, ftBCD, ftFMTBcd:
      Result := TJSONFloatNumber.Create(F.AsFloat);
    ftBoolean:
      Result := TJSONBoolean.Create(F.AsBoolean);
    ftDate:
      Result := TJSONString.Create(FormatDateTime('yyyy-mm-dd', F.AsDateTime));
    ftDateTime, ftTimeStamp:
      Result := TJSONString.Create(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', F.AsDateTime));
  else
    S := F.AsString;
    SetCodePage(RawByteString(S), CP_UTF8, False);
    Result := TJSONString.Create(S);
  end;
end;

function RowToJson(Q: TSQLQuery): TJSONObject;
var
  I: Integer;
begin
  Result := TJSONObject.Create;
  for I := 0 to Q.Fields.Count - 1 do
    Result.Add(Q.Fields[I].FieldName, FieldToJson(Q.Fields[I]));
end;

function NewQuery(C: TDbConnection; const SQL: string; const Params: array of const): TSQLQuery;
var
  Count: Integer;
begin
  Result := TSQLQuery.Create(nil);
  try
    Result.DataBase := C.Conn;
    Result.Transaction := C.Trans;
    Result.UsePrimaryKeyAsKey := False;
    Result.SQL.Text := NumberParams(SQL, Count);
    BindParams(Result, Params, Count);
  except
    Result.Free;
    raise;
  end;
end;

procedure EnsureTransaction(C: TDbConnection);
begin
  if not C.Trans.Active then
    C.Trans.StartTransaction;
end;

{ ---------------- TDbConnection ---------------- }

destructor TDbConnection.Destroy;
begin
  if Trans <> nil then
  begin
    if Trans.Active then
      Trans.Rollback;
    Trans.Free;
  end;
  if Conn <> nil then
  begin
    Conn.Connected := False;
    Conn.Free;
  end;
  inherited Destroy;
end;

{ ---------------- TDbSession ---------------- }

function TDbSession.Query(const SQL: string; const Params: array of const): TJSONArray;
var
  C: TDbConnection;
  Q: TSQLQuery;
  Failed: Boolean;
begin
  Result := TJSONArray.Create;
  Failed := True;
  C := Acquire;
  try
    Q := nil;
    try
      Q := NewQuery(C, SQL, Params);
      EnsureTransaction(C);
      Q.Open;
      while not Q.EOF do
      begin
        Result.Add(RowToJson(Q));
        Q.Next;
      end;
      Q.Close;
      Failed := False;
    except
      on E: EDbError do
      begin
        Result.Free;
        raise;
      end;
      on E: Exception do
      begin
        Result.Free;
        raise Wrap(E, SQL);
      end;
    end;
  finally
    Q.Free;
    Release(C, Failed);
  end;
end;

function TDbSession.QueryOne(const SQL: string; const Params: array of const): TJSONObject;
var
  Rows: TJSONArray;
begin
  Rows := Query(SQL, Params);
  try
    if Rows.Count = 0 then
      Exit(nil);
    Result := TJSONObject(Rows.Extract(0));
  finally
    Rows.Free;
  end;
end;

function TDbSession.QueryValue(const SQL: string; const Params: array of const; const Default: string): string;
var
  Row: TJSONObject;
begin
  Row := QueryOne(SQL, Params);
  if (Row = nil) or (Row.Count = 0) or (Row.Items[0].JSONType = jtNull) then
    Result := Default
  else
    Result := Row.Items[0].AsString;
  Row.Free;
end;

function TDbSession.QueryInt(const SQL: string; const Params: array of const; Default: Int64): Int64;
begin
  Result := StrToInt64Def(QueryValue(SQL, Params, IntToStr(Default)), Default);
end;

function TDbSession.Exec(const SQL: string; const Params: array of const): Int64;
var
  C: TDbConnection;
  Q: TSQLQuery;
  Failed: Boolean;
begin
  Failed := True;
  C := Acquire;
  Q := nil;
  try
    try
      Q := NewQuery(C, SQL, Params);
      EnsureTransaction(C);
      Q.ExecSQL;
      Result := Q.RowsAffected;
      Failed := False;
    except
      on E: EDbError do
        raise;
      on E: Exception do
        raise Wrap(E, SQL);
    end;
  finally
    Q.Free;
    Release(C, Failed);
  end;
end;

function TDbSession.Insert(const SQL: string; const Params: array of const): Int64;
var
  C: TDbConnection;
  Q: TSQLQuery;
  Failed: Boolean;
begin
  Failed := True;
  Result := 0;
  C := Acquire;
  Q := nil;
  try
    try
      if FDb.Kind = dbPostgres then
      begin
        if Pos('returning', LowerCase(SQL)) > 0 then
          Q := NewQuery(C, SQL, Params)
        else
          Q := NewQuery(C, TrimRight(SQL) + ' returning id', Params);
        EnsureTransaction(C);
        Q.Open;
        if not Q.EOF then
          Result := Q.Fields[0].AsLargeInt;
        Q.Close;
      end
      else
      begin
        Q := NewQuery(C, SQL, Params);
        EnsureTransaction(C);
        Q.ExecSQL;
        if C.Conn is TSQLite3Connection then
          Result := TSQLite3Connection(C.Conn).GetInsertID
        else if C.Conn is TMySQL80Connection then
          Result := TMySQL80Connection(C.Conn).GetInsertID
        else if C.Conn is TMySQL57Connection then
          Result := TMySQL57Connection(C.Conn).GetInsertID;
      end;
      Failed := False;
    except
      on E: EDbError do
        raise;
      on E: Exception do
        raise Wrap(E, SQL);
    end;
  finally
    Q.Free;
    Release(C, Failed);
  end;
end;

{ ---------------- TDbTransaction ---------------- }

constructor TDbTransaction.Create(ADb: TDatabase);
begin
  inherited Create;
  FDb := ADb;
  FConn := ADb.Acquire;
  try
    if FConn.Trans.Active then
      FConn.Trans.Commit;
    FConn.Trans.StartTransaction;
  except
    on E: Exception do
    begin
      FDb.Release(FConn, True);
      FConn := nil;
      raise Wrap(E, 'begin');
    end;
  end;
end;

destructor TDbTransaction.Destroy;
begin
  if (FConn <> nil) and not FDone then
    Rollback;
  inherited Destroy;
end;

function TDbTransaction.Acquire: TDbConnection;
begin
  if FDone or (FConn = nil) then
    raise EDbError.Create('the transaction has ended already');
  Result := FConn;
end;

procedure TDbTransaction.Release(C: TDbConnection; Failed: Boolean);
begin
  { the connection stays with the transaction until Commit or Rollback }
end;

procedure TDbTransaction.Commit;
begin
  Acquire;
  try
    FConn.Trans.Commit;
  except
    on E: Exception do
    begin
      Rollback;
      raise Wrap(E, 'commit');
    end;
  end;
  FDone := True;
  FDb.Release(FConn, False);
  FConn := nil;
end;

procedure TDbTransaction.Rollback;
var
  Failed: Boolean;
begin
  if FDone or (FConn = nil) then
    Exit;
  Failed := False;
  try
    if FConn.Trans.Active then
      FConn.Trans.Rollback;
  except
    Failed := True;    { the connection is broken: the pool drops it }
  end;
  FDone := True;
  FDb.Release(FConn, Failed);
  FConn := nil;
end;

{ ---------------- TDatabase ---------------- }

class function TDatabase.Open(const Url: string; MaxConnections: Integer): TDatabase;
begin
  Result := TDatabase.Create(Url, MaxConnections);
  try
    Result.Release(Result.Acquire, False);    { connect now, so a wrong address shows at once }
  except
    Result.Free;
    raise;
  end;
end;

constructor TDatabase.Create(const Url: string; MaxConnections: Integer);
var
  Rest, Scheme, Auth, HostPart: string;
  I: Integer;
begin
  inherited Create;
  FDb := Self;
  FUrl := Url;
  FPool := TList.Create;
  FLock := TCriticalSection.Create;
  FMaxConnections := MaxConnections;
  I := Pos(':', Url);
  if I = 0 then
    raise EDbError.CreateFmt('"%s" is not a database address; examples: sqlite:data/app.db, ' +
      'postgres://user:password@localhost/shop, mysql://user:password@localhost/shop', [Url]);
  Scheme := LowerCase(Copy(Url, 1, I - 1));
  Rest := Copy(Url, I + 1, MaxInt);
  case Scheme of
    'sqlite', 'sqlite3':
      begin
        FKind := dbSQLite;
        if Copy(Rest, 1, 2) = '//' then
          Delete(Rest, 1, 2);
        FName := Rest;
        if FName = ':memory:' then
          FMaxConnections := 1      { every connection would have its own database }
        else if FName = '' then
          raise EDbError.Create('sqlite needs a file: sqlite:data/app.db');
      end;
    'postgres', 'postgresql', 'mysql', 'mariadb':
      begin
        if Scheme[1] = 'p' then
          FKind := dbPostgres
        else
          FKind := dbMySQL;
        if Copy(Rest, 1, 2) <> '//' then
          raise EDbError.CreateFmt('use %s://user:password@host/database', [Scheme]);
        Delete(Rest, 1, 2);
        I := Pos('?', Rest);
        if I > 0 then
          SetLength(Rest, I - 1);
        I := Pos('/', Rest);
        if I = 0 then
          raise EDbError.CreateFmt('the address needs a database name: %s://user:password@host/database', [Scheme]);
        FName := UrlPart(Copy(Rest, I + 1, MaxInt));
        HostPart := Copy(Rest, 1, I - 1);
        I := LastDelimiter('@', HostPart);
        if I > 0 then
        begin
          Auth := Copy(HostPart, 1, I - 1);
          Delete(HostPart, 1, I);
          I := Pos(':', Auth);
          if I > 0 then
          begin
            FUser := UrlPart(Copy(Auth, 1, I - 1));
            FPassword := UrlPart(Copy(Auth, I + 1, MaxInt));
          end
          else
            FUser := UrlPart(Auth);
        end;
        I := Pos(':', HostPart);
        if I > 0 then
        begin
          FPort := StrToIntDef(Copy(HostPart, I + 1, MaxInt), 0);
          SetLength(HostPart, I - 1);
        end;
        FHost := HostPart;
        if FHost = '' then
          FHost := 'localhost';
      end;
  else
    raise EDbError.CreateFmt('unknown database "%s" (sqlite, postgres or mysql)', [Scheme]);
  end;
end;

destructor TDatabase.Destroy;
var
  I: Integer;
begin
  if FPool <> nil then
    for I := 0 to FPool.Count - 1 do
      TObject(FPool[I]).Free;
  FPool.Free;
  FLock.Free;
  inherited Destroy;
end;

function TDatabase.SafeUrl: string;
begin
  if FPassword = '' then
    Result := FUrl
  else
    Result := StringReplace(FUrl, ':' + FPassword + '@', ':***@', []);
end;

var
  MySqlLoaded: Integer = 0;     { 0 not yet, 57 or 80 }
  MySqlLock: TCriticalSection;

{ MySQL 8 client (libmysqlclient.so.21) or MariaDB's (libmariadb.so.3) }
function LoadMySql: Integer;
const
  {$IFDEF WINDOWS}
  Libs80: array[0..0] of string = ('libmysql.dll');
  Libs57: array[0..1] of string = ('libmariadb.dll', 'libmysql.dll');
  {$ELSE}
  Libs80: array[0..0] of string = ('libmysqlclient.so.21');
  Libs57: array[0..2] of string = ('libmariadb.so.3', 'libmysqlclient.so.20', 'libmysqlclient.so');
  {$ENDIF}
var
  L: string;
begin
  MySqlLock.Acquire;
  try
    if MySqlLoaded = 0 then
    begin
      for L in Libs80 do
        if MySqlLoaded = 0 then
        try
          mysql80dyn.InitialiseMysql(L);
          MySqlLoaded := 80;
        except
          on EInOutError do ;
        end;
      for L in Libs57 do
        if MySqlLoaded = 0 then
        try
          mysql57dyn.InitialiseMysql(L);
          MySqlLoaded := 57;
        except
          on EInOutError do ;
        end;
      if MySqlLoaded = 0 then
        raise EDbError.Create('the MySQL/MariaDB client library was not found ' +
          '(Debian/Ubuntu: sudo apt install libmariadb3)');
    end;
    Result := MySqlLoaded;
  finally
    MySqlLock.Release;
  end;
end;

function TDatabase.NewConnection: TDbConnection;
begin
  Result := TDbConnection.Create;
  try
    case FKind of
      dbSQLite:
        begin
          Result.Conn := TSQLite3Connection.Create(nil);
          if FName <> ':memory:' then
            EnsureDir(ExtractFileDir(ExpandFileName(FName)));
        end;
      dbPostgres:
        Result.Conn := TPQConnection.Create(nil);
      dbMySQL:
        if LoadMySql = 80 then
          Result.Conn := TMySQL80Connection.Create(nil)
        else
        begin
          Result.Conn := TMySQL57Connection.Create(nil);
          { MariaDB's client calls itself 3.x; it speaks the 5.7 interface }
          TMySQL57Connection(Result.Conn).SkipLibraryVersionCheck := True;
        end;
    end;
    Result.Conn.DatabaseName := FName;
    Result.Conn.HostName := FHost;
    Result.Conn.UserName := FUser;
    Result.Conn.Password := FPassword;
    if FPort > 0 then
      Result.Conn.Params.Values['Port'] := IntToStr(FPort);
    Result.Conn.CharSet := 'UTF8';
    if FKind = dbMySQL then
      Result.Conn.CharSet := 'utf8mb4';
    if FKind = dbPostgres then
      { "table does not exist, skipping" and such would go to the console }
      Result.Conn.Params.Add('options=''-c client_min_messages=warning''');
    Result.Trans := TSQLTransaction.Create(nil);
    Result.Trans.DataBase := Result.Conn;
    Result.Conn.Transaction := Result.Trans;
    try
      Result.Conn.Connected := True;
    except
      on E: Exception do
        raise EDbError.CreateFmt('cannot connect to %s: %s', [SafeUrl, CleanMessage(E.Message)]);
    end;
    if FKind = dbSQLite then
    begin
      { outside a transaction, which ExecuteDirect would start.
        Several connections to one file: wait for locks instead of failing. }
      TSQLiteAccess(Result.Conn).execsql('PRAGMA busy_timeout = 5000');
      TSQLiteAccess(Result.Conn).execsql('PRAGMA foreign_keys = ON');
      if FName <> ':memory:' then
        TSQLiteAccess(Result.Conn).execsql('PRAGMA journal_mode = WAL');
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ ---------------- backups ---------------- }

function DbTool(const Name, Package: string): string;
begin
  Result := Which(Name);
  if Result = '' then
    raise EDbError.CreateFmt('%s is needed for this (Debian/Ubuntu: sudo apt install %s)', [Name, Package]);
end;

function TDatabase.ToolOptions(out Env: SysUtils.TStringArray): SysUtils.TStringArray;
begin
  Env := nil;
  Result := nil;
  case FKind of
    dbPostgres:
      begin
        Result := ['-h', FHost, '-U', FUser];
        if FPort > 0 then
          Result := Concat(Result, ['-p', IntToStr(FPort)]);
        Env := ['PGPASSWORD=' + FPassword];
      end;
    dbMySQL:
      begin
        Result := ['-h', FHost, '-u', FUser];
        if FPort > 0 then
          Result := Concat(Result, ['-P', IntToStr(FPort)]);
        Env := ['MYSQL_PWD=' + FPassword];
      end;
  end;
end;

procedure TDatabase.Backup(const FileName: string);
var
  C: TDbConnection;
  O: TRunOptions;
  R: TRunResult;
  Env: TStringArray;
  Args: TStringArray;
begin
  EnsureDir(ExtractFileDir(ExpandFileName(FileName)));
  if FileExists(FileName) then
    DeleteFile(FileName);
  O := Default(TRunOptions);
  case FKind of
    dbSQLite:
      begin
        if FName = ':memory:' then
          raise EDbError.Create('a database in memory has no backup');
        { VACUUM cannot run in a transaction: straight on a connection }
        C := Acquire;
        try
          try
            TSQLiteAccess(C.Conn).execsql('VACUUM INTO ''' +
              StringReplace(ExpandFileName(FileName), '''', '''''', [rfReplaceAll]) + '''');
          except
            on E: Exception do
              raise EDbError.CreateFmt('the backup of %s failed: %s', [SafeUrl, CleanMessage(E.Message)]);
          end;
        finally
          Release(C, False);
        end;
      end;
    dbPostgres:
      begin
        Args := Concat(ToolOptions(Env), ['--no-owner', '--clean', '--if-exists', '-f', FileName, FName]);
        O.Env := Env;
        R := Run(DbTool('pg_dump', 'postgresql-client'), Args, O);
        if not R.Ok then
          raise EDbError.CreateFmt('the backup of %s failed: %s', [SafeUrl, Trim(R.Errors)]);
      end;
    dbMySQL:
      begin
        Args := Concat(ToolOptions(Env), ['--single-transaction', '--routines', '--result-file=' + FileName, FName]);
        O.Env := Env;
        R := Run(DbTool('mysqldump', 'mariadb-client'), Args, O);
        if not R.Ok then
          raise EDbError.CreateFmt('the backup of %s failed: %s', [SafeUrl, Trim(R.Errors)]);
      end;
  end;
end;

function TDatabase.BackupTo(const Dir: string; Keep: Integer): string;
var
  Base, Ext: string;
  Files: TStringList;
  F: string;
begin
  if FKind = dbSQLite then
  begin
    Base := ChangeFileExt(ExtractFileName(FName), '');
    Ext := '.db';
  end
  else
  begin
    Base := FName;
    Ext := '.sql';
  end;
  Result := JoinPath([Dir, Format('%s-%s%s', [Base, FormatDateTime('yyyy-mm-dd-hhnnss-zzz', Now), Ext])]);
  Backup(Result);
  if Keep > 0 then
  begin
    Files := TStringList.Create;
    try
      for F in ListFiles(Dir, Base + '-????-??-??-??????-???' + Ext) do
        Files.Add(F);
      Files.Sort;           { the time in the name sorts them }
      while Files.Count > Keep do
      begin
        DeleteFile(Files[0]);
        Files.Delete(0);
      end;
    finally
      Files.Free;
    end;
  end;
end;

procedure TDatabase.Restore(const FileName: string);
var
  O: TRunOptions;
  R: TRunResult;
  Env, Args: TStringArray;
  I: Integer;
begin
  if not FileExists(FileName) then
    raise EDbError.CreateFmt('no backup %s', [FileName]);
  O := Default(TRunOptions);
  case FKind of
    dbSQLite:
      begin
        if FName = ':memory:' then
          raise EDbError.Create('a database in memory cannot be restored');
        { closes the connections; the next query opens the restored file }
        FLock.Acquire;
        try
          for I := 0 to FPool.Count - 1 do
            if TDbConnection(FPool[I]).InUse then
              raise EDbError.Create('the database is in use; restore it when nothing else uses it');
          for I := 0 to FPool.Count - 1 do
            TDbConnection(FPool[I]).Free;
          FPool.Clear;
          DeleteFile(FName + '-wal');
          DeleteFile(FName + '-shm');
          CopyFile(FileName, FName);
        finally
          FLock.Release;
        end;
      end;
    dbPostgres:
      begin
        Args := Concat(ToolOptions(Env), ['-v', 'ON_ERROR_STOP=1', '-q', '-f', FileName, FName]);
        O.Env := Env;
        R := Run(DbTool('psql', 'postgresql-client'), Args, O);
        if not R.Ok then
          raise EDbError.CreateFmt('restoring %s failed: %s', [SafeUrl, Trim(R.Errors)]);
      end;
    dbMySQL:
      begin
        Args := Concat(ToolOptions(Env), [FName]);
        O.Env := Env;
        O.Input := ReadText(FileName);
        R := Run(DbTool('mysql', 'mariadb-client'), Args, O);
        if not R.Ok then
          raise EDbError.CreateFmt('restoring %s failed: %s', [SafeUrl, Trim(R.Errors)]);
      end;
  end;
end;

function TDatabase.Acquire: TDbConnection;
var
  I, Waited: Integer;
begin
  Waited := 0;
  repeat
    FLock.Acquire;
    try
      for I := 0 to FPool.Count - 1 do
        if not TDbConnection(FPool[I]).InUse then
        begin
          Result := TDbConnection(FPool[I]);
          Result.InUse := True;
          Exit;
        end;
      if FPool.Count < FMaxConnections then
      begin
        Result := NewConnection;
        Result.InUse := True;
        FPool.Add(Result);
        Exit;
      end;
    finally
      FLock.Release;
    end;
    { all connections are busy: wait for one }
    Sleep(5);
    Inc(Waited, 5);
  until Waited > 30000;
  raise EDbError.Create('no database connection became free in 30 seconds');
end;

procedure TDatabase.Release(C: TDbConnection; Failed: Boolean);
begin
  try
    if C.Trans.Active then
      if Failed then
        C.Trans.Rollback
      else
        C.Trans.Commit;
  except
    Failed := True;
  end;
  FLock.Acquire;
  try
    if Failed and not C.Conn.Connected then
    begin
      FPool.Remove(C);      { a broken connection: the next one is new }
      C.Free;
    end
    else
      C.InUse := False;
  finally
    FLock.Release;
  end;
end;

function TDatabase.BeginTransaction: TDbTransaction;
begin
  Result := TDbTransaction.Create(Self);
end;

{ ---------------- migrations ---------------- }

function DefaultMigrationsDir: string;
begin
  Result := JoinPath([AppDir, 'database', 'migrations']);
  if not DirectoryExists(Result) then
    Result := JoinPath(['database', 'migrations']);
end;

function SplitSql(const Script: string): SysUtils.TStringArray;
var
  I: Integer;
  Cur: string;
  Quote: Char;
  InComment, InBlockComment: Boolean;

  procedure Flush;
  begin
    if Trim(Cur) <> '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Trim(Cur);
    end;
    Cur := '';
  end;

begin
  Result := nil;
  Cur := '';
  Quote := #0;
  InComment := False;
  InBlockComment := False;
  I := 1;
  while I <= Length(Script) do
  begin
    if InComment then
    begin
      if Script[I] in [#10, #13] then
        InComment := False;
    end
    else if InBlockComment then
    begin
      if Copy(Script, I, 2) = '*/' then
      begin
        InBlockComment := False;
        Inc(I);
      end;
    end
    else if Quote <> #0 then
    begin
      Cur := Cur + Script[I];
      if Script[I] = Quote then
        Quote := #0;
    end
    else if Copy(Script, I, 2) = '--' then
      InComment := True
    else if Copy(Script, I, 2) = '/*' then
    begin
      InBlockComment := True;
      Inc(I);
    end
    else if Script[I] in ['''', '"', '`'] then
    begin
      Quote := Script[I];
      Cur := Cur + Script[I];
    end
    else if Script[I] = ';' then
      Flush
    else
      Cur := Cur + Script[I];
    Inc(I);
  end;
  Flush;
end;

procedure EnsureMigrationTable(Db: TDatabase);
begin
  Db.Exec('create table if not exists schema_migrations (' +
    'version varchar(255) primary key, applied_at varchar(40) not null)', []);
end;

function MigrationFiles(const Dir: string): SysUtils.TStringArray;
begin
  if not DirectoryExists(Dir) then
    raise EDbError.CreateFmt('no migrations folder "%s"', [Dir]);
  Result := ListFiles(Dir, '*.sql');
end;

function IdType(Kind: TDbKind): string;
begin
  case Kind of
    dbSQLite: Result := 'integer primary key autoincrement';
    dbPostgres: Result := 'bigserial primary key';
  else
    Result := 'bigint auto_increment primary key';
  end;
end;

function TDatabase.Migrate(const Dir: string): Integer;
var
  D, F, Version, Stmt: string;
  Done: TJSONArray;
  Applied: TStringList;
  I: Integer;
  Tx: TDbTransaction;
begin
  Result := 0;
  D := Dir;
  if D = '' then
    D := DefaultMigrationsDir;
  EnsureMigrationTable(Self);
  Applied := TStringList.Create;
  try
    Applied.Sorted := True;
    Done := Query('select version from schema_migrations', []);
    try
      for I := 0 to Done.Count - 1 do
        Applied.Add(JStr(Done[I], 'version'));
    finally
      Done.Free;
    end;
    for F in MigrationFiles(D) do
    begin
      Version := ChangeFileExt(ExtractFileName(F), '');
      if Applied.IndexOf(Version) >= 0 then
        Continue;
      Tx := BeginTransaction;
      try
        try
          // {{id}}: the auto-numbered primary key, written the way this database wants it
          for Stmt in SplitSql(StringReplace(ReadText(F), '{{id}}', IdType(FKind), [rfReplaceAll])) do
            Tx.Exec(Stmt, []);
          Tx.Exec('insert into schema_migrations (version, applied_at) values (?, ?)',
            [Version, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', LocalTimeToUniversal(Now))]);
          Tx.Commit;
        except
          on E: Exception do
            raise EDbError.CreateFmt('migration %s failed: %s', [ExtractFileName(F), E.Message]);
        end;
      finally
        Tx.Free;
      end;
      Log.Info('migrated %s', [Version]);
      Inc(Result);
    end;
  finally
    Applied.Free;
  end;
end;

function TDatabase.MigrationStatus(const Dir: string): TStringList;
var
  D, F, Version: string;
  Done: TJSONArray;
  Applied: TStringList;
  I: Integer;
begin
  D := Dir;
  if D = '' then
    D := DefaultMigrationsDir;
  EnsureMigrationTable(Self);
  Result := TStringList.Create;
  Applied := TStringList.Create;
  try
    Done := Query('select version, applied_at from schema_migrations', []);
    try
      for I := 0 to Done.Count - 1 do
        Applied.Values[JStr(Done[I], 'version')] := JStr(Done[I], 'applied_at');
    finally
      Done.Free;
    end;
    for F in MigrationFiles(D) do
    begin
      Version := ChangeFileExt(ExtractFileName(F), '');
      if Applied.IndexOfName(Version) >= 0 then
        Result.Add(Version + '=applied ' + Applied.Values[Version])
      else
        Result.Add(Version + '=pending');
    end;
  finally
    Applied.Free;
  end;
end;

initialization
  MySqlLock := TCriticalSection.Create;
  {$IFDEF LINUX}
  { FPC asks for libsqlite3.so, which only the -dev package installs;
    servers have the runtime library libsqlite3.so.0 (package libsqlite3-0) }
  SQLiteDefaultLibrary := 'libsqlite3.so.0';
  {$ENDIF}
finalization
  MySqlLock.Free;
end.
