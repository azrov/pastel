# Databases: `Pastel.Db`

SQLite, PostgreSQL and MySQL/MariaDB with one small API. Rows come back as
JSON, ready to send from a web handler. `pastel new api` makes a complete
project with it: models, controllers, migrations and tests.

```pascal
uses Pastel.Db, Pastel.Json, fpjson;

Db := TDatabase.Open('sqlite:data/app.db');
Db.Migrate;                                   { database/migrations/*.sql }

Id := Db.Insert('insert into users (name, email) values (?, ?)', ['Ayşe', 'ayse@example.com']);
Rows := Db.Query('select id, name from users where name like ? order by name', ['A%']);
try
  for I := 0 to Rows.Count - 1 do
    WriteLn(JStr(Rows, Format('[%d].name', [I])));
finally
  Rows.Free;
end;
```

## Which database

| Address | |
|---|---|
| `sqlite:data/app.db` | a file; the folder is created. Nothing to install on Linux (`libsqlite3`) |
| `sqlite::memory:` | in memory, gone when the program ends (tests) |
| `postgres://user:password@host:5432/name` | PostgreSQL (`libpq`) |
| `mysql://user:password@host:3306/name` | MySQL or MariaDB (`libmysqlclient` or `libmariadb`) |

Keep the address in the settings, never in the code:
`[database] url = "..."` in config.toml, or the environment variable
`MYAPP_DATABASE_URL`. Messages and logs show it without the password
(`Db.SafeUrl`: `postgres://user:***@host/name`).

SQLite is set up for servers: waits up to 5 s when another connection
writes, WAL journal, foreign keys on. Start with SQLite; move to PostgreSQL
when several servers share the data. The same code and migrations work on
all three.

## Queries

| | |
|---|---|
| `Db.Query(SQL, [values])` | all rows: `TJSONArray` of `TJSONObject` |
| `Db.QueryOne(SQL, [values])` | the first row, or `nil` |
| `Db.QueryValue(SQL, [values], Default)` | the first column of the first row, as text |
| `Db.QueryInt(SQL, [values], Default)` | the same as a number: `select count(*) ...` |
| `Db.Exec(SQL, [values])` | update, delete, create table...: the number of rows changed |
| `Db.Insert(SQL, [values])` | an insert: the id of the new row |

You free what `Query` and `QueryOne` return, or hand it to `Res.Json`,
which frees it. Columns become JSON values: numbers, text, `true`/`false`
(on PostgreSQL; SQLite and MySQL give `0`/`1`), and `null`.

**Values always go in as `?`.** They are sent apart from the SQL, so a
name like `x'); drop table users; --` is stored as a name and can never
change the query. Never build SQL from user input with `+` or `Format`.

## Errors

| | |
|---|---|
| `EDbDuplicate` | a unique column already has this value: answer 409 |
| `EDbError` | anything else: bad SQL (the message shows the SQL), cannot connect, wrong number of `?` |

```pascal
try
  Db.Insert('insert into users (email) values (?)', [Email]);
except
  on EDbDuplicate do
    raise EWebError.Create(409, 'this email is already registered');
end;
```

## Transactions

```pascal
Tx := Db.BeginTransaction;
try
  Tx.Exec('update accounts set balance = balance - ? where id = ?', [Amount, From]);
  Tx.Exec('update accounts set balance = balance + ? where id = ?', [Amount, To_]);
  Tx.Commit;
finally
  Tx.Free;      { without Commit (an exception) everything is undone }
end;
```

A transaction has the same query functions as `Db`.

## Threads

One `TDatabase` serves the whole program, including every web request at
the same time: it keeps a pool of connections (10 unless
`TDatabase.Open(Url, 20)`). Open it once when the program starts.

## Migrations: the tables

The tables are made by SQL files in `database/migrations`, run in name
order, each once:

```
database/migrations/
  001_create_tasks.sql
  002_add_priority.sql
```

```sql
create table tasks (
  id {{id}},
  title varchar(200) not null,
  done boolean not null default false
);
```

`{{id}}` becomes the auto-numbered key of each database
(`integer primary key autoincrement`, `bigserial primary key`,
`bigint auto_increment primary key`), so one file works everywhere.

```sh
pastel migrate new add_priority     # database/migrations/002_add_priority.sql
pastel migrate status               # applied and pending
pastel migrate                      # runs the pending ones
pastel migrate --database postgres://...   # another database
```

`Db.Migrate` in the program does the same when it starts, so a new version
on the server brings its tables along. Each file runs in a transaction
(on MySQL, `create`/`alter` cannot be undone: keep one change per file).
The table `schema_migrations` records what ran. **Never change a migration
after it ran somewhere**; add a new one.

## Models: where the SQL lives

`pastel new api` puts all SQL of a table in one class, the model
(`src/models/tasks.pas`); the controllers (`src/controllers/`) only
handle HTTP and call the model:

```pascal
function TTasks.Find(Id: Int64): TJSONObject;
begin
  Result := FDb.QueryOne('select id, title, done from tasks where id = ?', [Id]);
end;
```

The model's tests use a fresh SQLite file per test (`tests/tasks_test.pas`).

## Testing with PostgreSQL and MySQL

The framework's own tests run the same checks on all three databases when
these variables point to empty test databases:

```sh
PASTEL_TEST_POSTGRES_URL=postgres://pastel:pastel@localhost/pastel_test \
PASTEL_TEST_MYSQL_URL=mysql://pastel:pastel@localhost/pastel_test pastel test
```

## Limits today

- Plain SQL; no query builder or ORM yet.
- Large binary columns (BLOB) are not supported in rows.
- Windows: SQLite needs `sqlite3.dll` next to the program; PostgreSQL and MySQL need their client DLLs.
