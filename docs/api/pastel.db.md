# Pastel.Db

Databases: SQLite, PostgreSQL, MySQL/MariaDB.

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

`uses Pastel.Db;` · source: [framework/src/pastel.db.pas](../../framework/src/pastel.db.pas)

**Contents:** [EDbError](#edberror) · [EDbDuplicate](#edbduplicate) · [TDbKind](#tdbkind) · [TDbSession](#tdbsession) · [TDbTransaction](#tdbtransaction) · [TDatabase](#tdatabase) · [DefaultMigrationsDir](#defaultmigrationsdir) · [SplitSql](#splitsql)

## Types

### EDbError

```pascal
type EDbError = class(Exception)
```

### EDbDuplicate

```pascal
type EDbDuplicate = class(EDbError)
```

a unique column or primary key already has this value

### TDbKind

```pascal
type TDbKind = (dbSQLite, dbPostgres, dbMySQL)
```

- `dbSQLite`
- `dbPostgres`
- `dbMySQL`
### TDbSession

```pascal
type TDbSession = class
```

What TDatabase and TDbTransaction have in common: the queries.

| | |
|---|---|
| `function Query(const SQL: string; const Params: array of const): TJSONArray` | all rows; the caller frees the result |
| `function QueryOne(const SQL: string; const Params: array of const): TJSONObject` | the first row, or nil; the caller frees it |
| `function QueryValue(const SQL: string; const Params: array of const; const Default: string = ''): string` | the first column of the first row |
| `function QueryInt(const SQL: string; const Params: array of const; Default: Int64 = 0): Int64` |  |
| `function Exec(const SQL: string; const Params: array of const): Int64` | insert/update/delete/DDL; the number of rows changed |
| `function Insert(const SQL: string; const Params: array of const): Int64` | an insert; the id of the new row (PostgreSQL: the table needs an "id" column) |

### TDbTransaction

```pascal
type TDbTransaction = class(TDbSession)
```

| | |
|---|---|
| `constructor Create(ADb: TDatabase)` |  |
| `destructor Destroy` | rolls back unless committed |
| `procedure Commit` |  |
| `procedure Rollback` |  |

### TDatabase

```pascal
type TDatabase = class(TDbSession)
```

| | |
|---|---|
| `class function Open(const Url: string; MaxConnections: Integer = 10): TDatabase` | see the examples above; EDbError when it cannot connect |
| `constructor Create(const Url: string; MaxConnections: Integer = 10)` |  |
| `destructor Destroy` |  |
| `function BeginTransaction: TDbTransaction` |  |
| `function Migrate(const Dir: string = ''): Integer` | Runs the .sql files in Dir that did not run yet, in name order, each in a transaction, and notes them in the table schema_migrations. In the files, {{id}} stands for an auto-numbered primary key in the way of the database (id {{id}}), so one file works everywhere. Dir '' means database/migrations next to the program, else in the current folder. Returns how many ran. |
| `function MigrationStatus(const Dir: string = ''): TStringList` | name=applied/pending for every migration file |
| `property Kind: TDbKind` |  |
| `function SafeUrl: string` | the address without the password |

## Routines

### DefaultMigrationsDir

```pascal
function DefaultMigrationsDir: string
```

the folder Migrate uses when given ''

### SplitSql

```pascal
function SplitSql(const Script: string): TStringArray
```

splits a script into statements at ; (not inside quotes or comments)

