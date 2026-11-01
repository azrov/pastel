# Pastel.Sync

Data that works offline and is synchronized with a server: the
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

`uses Pastel.Sync;` · source: [framework/src/pastel.sync.pas](../../framework/src/pastel.sync.pas)

**Contents:** [ESyncInvalid](#esyncinvalid) · [TSyncResult](#tsyncresult) · [TSyncStore](#tsyncstore) · [SyncStamp](#syncstamp) · [NewSyncId](#newsyncid) · [SyncWithServer](#syncwithserver) · [AnswerSync](#answersync)

## Types

### ESyncInvalid

```pascal
type ESyncInvalid = class(Exception)
```

### TSyncResult

```pascal
type TSyncResult = record
```

| | |
|---|---|
| `Sent: Integer` |  |
| `Received: Integer` |  |

### TSyncStore

```pascal
type TSyncStore = class
```

| | |
|---|---|
| `constructor Create(ADb: TDatabase; OwnsDb: Boolean = False)` |  |
| `destructor Destroy` |  |
| `procedure AddTable(const Name: string; const Columns: string)` | A table that is synchronized: its columns as SQL, without the ones every table gets (id, updated_at, synced_at, dirty, deleted). |
| `procedure CreateTables` | The tables, when they are missing. |
| `function Tables: TStringArray` |  |
| `function Fields(const Table: string): TStringArray` |  |
| `function Save(const Table: string; Data: TJSONObject): string` | Checks and stores a record: a new one without "id", else the one with this id (values not given keep theirs). Returns the id. |
| `function Get(const Table: string; const Id: string): TJSONObject` | One record, nil when there is none (or it is deleted); the caller frees it. |
| `procedure Delete(const Table: string; const Id: string)` |  |
| `function List(const Table: string; const Where: string = ''; const Params: array of const; const OrderBy: string = ''): TJSONArray` | The records that are not deleted. Where: more conditions ('status = ?'), OrderBy: 'name' (default: updated_at). The caller frees it. |
| `function List(const Table: string): TJSONArray` |  |
| `function Count(const Table: string): Integer` |  |
| `function Changes(const Since: string; Dirty: Boolean): TJSONObject` |  |
| `function Apply(Data: TJSONObject): Integer` | Takes records from the other side; returns how many were newer and stored. |
| `procedure MarkSent(Data: TJSONObject)` | After the server took them: not dirty any more (unless changed again meanwhile). |
| `function Pending: Integer` | The number of records waiting to be sent. |
| `property Db: TDatabase` |  |
| `property IsServer: Boolean` | True on the server: Save and Apply stamp records with the server's clock, so clients get them on their next sync. |
| `property OnCheck: TSyncCheckEvent` | Checks a record before it is stored (also records that come with a sync): raise ESyncInvalid with a message for the user. |

## Other types

| | |
|---|---|
| `type TSyncCheckEvent = procedure(Table: string; Data: TJSONObject)` |  |

## Routines

### SyncStamp

```pascal
function SyncStamp: string
```

The current time as records are stamped: '2026-11-01T09:30:00.123000Z';
always larger than the one before, also in the same millisecond.

### NewSyncId

```pascal
function NewSyncId: string
```

A new id: 16 random characters.

### SyncWithServer

```pascal
function SyncWithServer(Store: TSyncStore; const Url: string; const ApiKey: string; var LastSync: string; const Path: string = '/api/sync'): TSyncResult
```

A client's sync: sends what changed here to Url + Path (POST, JSON), takes
what changed there. LastSync: the server's time of the last sync, kept by
the caller ('' the first time). EHttpError when the server cannot be
reached; nothing is lost, the changes go next time.

### AnswerSync

```pascal
function AnswerSync(Store: TSyncStore; Request: TJSONObject): TJSONObject
```

What the server does with a sync request: {"since": "...", "changes": {...}}
-> {"now": "...", "applied": 2, "changes": {...}} (Pastel.SyncWeb uses it).

