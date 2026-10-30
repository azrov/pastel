unit Db_Test;

{ SQLite always; PostgreSQL and MySQL/MariaDB when PASTEL_TEST_POSTGRES_URL /
  PASTEL_TEST_MYSQL_URL point to an empty test database. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, Pastel.Testing, Pastel.Db, Pastel.Json, Pastel.Files, Pastel.Env,
  Pastel.Log;

type
  TDbTests = class(TTestSuite)
  private
    procedure RunAll(const Url: string);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure WorksOnSqlite;
    procedure WorksOnPostgres;
    procedure WorksOnMysql;
    procedure SplitsScripts;
    procedure ExplainsBadAddresses;
  end;

implementation

var
  Dir: string;

procedure TDbTests.SetUp;
begin
  Dir := MakeTempDir('pastel-db-test');
  Log.Console := False;
end;

procedure TDbTests.TearDown;
begin
  Log.Console := True;
  DeleteDir(Dir);
end;

function IdColumn(Db: TDatabase): string;
begin
  case Db.Kind of
    dbSQLite: Result := 'id integer primary key';
    dbPostgres: Result := 'id serial primary key';
  else
    Result := 'id integer auto_increment primary key';
  end;
end;

type
  TInserter = class(TThread)
    Db: TDatabase;
    Errors: Integer;
    procedure Execute; override;
  end;

procedure TInserter.Execute;
var
  I: Integer;
begin
  for I := 1 to 25 do
  try
    Db.Insert('insert into hits (who) values (?)', ['thread']);
  except
    Inc(Errors);
  end;
end;

procedure TDbTests.RunAll(const Url: string);
var
  Db: TDatabase;
  Rows: TJSONArray;
  Row: TJSONObject;
  Id1, Id2: Int64;
  Tx: TDbTransaction;
  Threads: array[1..8] of TInserter;
  I, Errors: Integer;
  Status: TStringList;
begin
  Db := TDatabase.Open(Url);
  try
    Db.Exec('drop table if exists users', []);
    Db.Exec('drop table if exists hits', []);
    Db.Exec('drop table if exists schema_migrations', []);
    Db.Exec('drop table if exists notes', []);
    Db.Exec('drop table if exists tags', []);
    Db.Exec('create table users (' + IdColumn(Db) + ', name varchar(100) not null, ' +
      'email varchar(100) unique, score float, note varchar(200))', []);

    { insert and read back }
    Id1 := Db.Insert('insert into users (name, email, score) values (?, ?, ?)', ['Ayşe', 'ayse@example.com', 9.5]);
    Id2 := Db.Insert('insert into users (name, email, note) values (?, ?, ?)',
      ['x''); drop table users; --', 'x@example.com', nil]);
    AssertEquals(1, Id1);
    AssertEquals(2, Id2);
    Rows := Db.Query('select id, name, email, score, note from users order by id', []);
    try
      AssertEquals(2, Rows.Count);
      AssertEquals('Ayşe', JStr(Rows, '[0].name'));
      AssertEquals(1, JInt(Rows, '[0].id'));
      AssertEquals(9.5, JFloat(Rows, '[0].score'), 1e-9);
      AssertEquals('x''); drop table users; --', JStr(Rows, '[1].name'), 'values cannot change the SQL');
      AssertTrue(Rows.Objects[1].Find('note').JSONType = jtNull, 'NULL is null');
    finally
      Rows.Free;
    end;

    Row := Db.QueryOne('select name from users where email = ?', ['ayse@example.com']);
    try
      AssertEquals('Ayşe', JStr(Row, 'name'));
    finally
      Row.Free;
    end;
    AssertNil(Db.QueryOne('select * from users where id = ?', [99]));
    AssertEquals(2, Db.QueryInt('select count(*) from users', []));
    AssertEquals('none', Db.QueryValue('select name from users where id = ?', [99], 'none'));
    AssertEquals(1, Db.Exec('update users set score = ? where id = ?', [1, Id2]));
    AssertEquals(0, Db.Exec('update users set score = ? where id = ?', [1, 99]));

    { a duplicate value }
    try
      Db.Insert('insert into users (name, email) values (?, ?)', ['B', 'ayse@example.com']);
      Fail('a duplicate was accepted');
    except
      on E: EDbDuplicate do ;
    end;

    { mistakes in SQL say where }
    try
      Db.Query('select nothing from nowhere', []);
      Fail('bad SQL was accepted');
    except
      on E: EDbError do
        AssertContains('select nothing from nowhere', E.Message);
    end;
    try
      Db.Query('select * from users where id = ?', []);
      Fail('a missing value was accepted');
    except
      on E: EDbError do
        AssertContains('1 ? but 0 value(s)', E.Message);
    end;

    { transactions }
    Tx := Db.BeginTransaction;
    try
      Tx.Exec('update users set name = ? where id = ?', ['changed', Id1]);
      AssertEquals('changed', Tx.QueryValue('select name from users where id = ?', [Id1]));
    finally
      Tx.Free;     { no Commit: rolled back }
    end;
    AssertEquals('Ayşe', Db.QueryValue('select name from users where id = ?', [Id1]));
    Tx := Db.BeginTransaction;
    try
      Tx.Exec('update users set name = ? where id = ?', ['Ayşe Y.', Id1]);
      Tx.Commit;
    finally
      Tx.Free;
    end;
    AssertEquals('Ayşe Y.', Db.QueryValue('select name from users where id = ?', [Id1]));

    { many threads at once }
    Db.Exec('create table hits (' + IdColumn(Db) + ', who varchar(20))', []);
    for I := Low(Threads) to High(Threads) do
    begin
      Threads[I] := TInserter.Create(True);
      Threads[I].Db := Db;
      Threads[I].Start;
    end;
    Errors := 0;
    for I := Low(Threads) to High(Threads) do
    begin
      Threads[I].WaitFor;
      Inc(Errors, Threads[I].Errors);
      Threads[I].Free;
    end;
    AssertEquals(0, Errors);
    AssertEquals(200, Db.QueryInt('select count(*) from hits', []));

    { migrations }
    WriteText(JoinPath([Dir, 'm', '001_notes.sql']),
      '-- the notes; a ; in a comment' + LineEnding +
      'create table notes (' + IdColumn(Db) + ', title varchar(100));' + LineEnding +
      'insert into notes (title) values (''a; b'');' + LineEnding);
    WriteText(JoinPath([Dir, 'm', '002_more.sql']), 'insert into notes (title) values (''c'');' + LineEnding +
      'create table tags (id {{id}}, name varchar(20));' + LineEnding + 'insert into tags (name) values (''x'');');
    AssertEquals(2, Db.Migrate(JoinPath([Dir, 'm'])));
    AssertEquals(0, Db.Migrate(JoinPath([Dir, 'm'])));
    AssertEquals('a; b', Db.QueryValue('select title from notes order by id', []));
    AssertEquals(1, Db.QueryInt('select id from tags', []), '{{id}} numbers the rows');
    if Db.Kind <> dbMySQL then      { MySQL cannot roll back table changes }
    begin
      WriteText(JoinPath([Dir, 'm', '003_broken.sql']),
        'insert into notes (title) values (''d'');' + LineEnding + 'this is not sql;');
      try
        Db.Migrate(JoinPath([Dir, 'm']));
        Fail('a broken migration was accepted');
      except
        on E: EDbError do
          AssertContains('migration 003_broken.sql failed', E.Message);
      end;
      AssertEquals(2, Db.QueryInt('select count(*) from notes', []), 'rolled back');
    end;
    Status := Db.MigrationStatus(JoinPath([Dir, 'm']));
    try
      AssertStartsWith('applied', Status.Values['001_notes']);
    finally
      Status.Free;
    end;
  finally
    Db.Free;
  end;
end;

procedure TDbTests.WorksOnSqlite;
begin
  RunAll('sqlite:' + Dir + 'test.db');
end;

procedure TDbTests.WorksOnPostgres;
begin
  if GetEnv('PASTEL_TEST_POSTGRES_URL') = '' then
    Skip('set PASTEL_TEST_POSTGRES_URL=postgres://user:password@localhost/testdb');
  RunAll(GetEnv('PASTEL_TEST_POSTGRES_URL'));
end;

procedure TDbTests.WorksOnMysql;
begin
  if GetEnv('PASTEL_TEST_MYSQL_URL') = '' then
    Skip('set PASTEL_TEST_MYSQL_URL=mysql://user:password@localhost/testdb');
  RunAll(GetEnv('PASTEL_TEST_MYSQL_URL'));
end;

procedure TDbTests.SplitsScripts;
var
  S: TStringArray;
begin
  S := SplitSql('create table a (x int); -- comment; here' + LineEnding +
    'insert into a values (''x;y''); /* ; */ select 1');
  AssertEquals(3, Length(S));
  AssertEquals('insert into a values (''x;y'')', S[1]);
end;

procedure TDbTests.ExplainsBadAddresses;
begin
  try
    TDatabase.Open('oracle://x/y').Free;
    Fail('accepted');
  except
    on E: EDbError do
      AssertContains('unknown database "oracle"', E.Message);
  end;
  try
    TDatabase.Open('postgres://who:secret-word@127.0.0.1:1/nothing').Free;
    Fail('accepted');
  except
    on E: EDbError do
    begin
      AssertContains('cannot connect to postgres://who:***@127.0.0.1:1/nothing', E.Message);
      AssertFalse(Pos('secret-word', E.Message) > 0, 'the password must not show');
    end;
  end;
end;

initialization
  RegisterTests(TDbTests);
end.
