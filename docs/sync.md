# Data that works offline: Pastel.Sync

A shop's computer, a field worker's laptop, a phone: they should keep working when the network is down, and the server should still end up with everything. `Pastel.Sync` does this. Every computer keeps its own SQLite file; a sync sends what changed there and takes what changed elsewhere.

```
desktop 1 ─┐                       ┌─ SQLite on the computer, works offline
desktop 2 ─┼── POST /api/sync ─── server (PostgreSQL, MySQL or SQLite)
phone ─────┘
```

The [salon example](guide-business.md) is built on it.

## The store

```pascal
uses
  Pastel.Db, Pastel.Sync;

Store := TSyncStore.Create(TDatabase.Open('sqlite:' + DbFile), True);    // True: the store frees the database
Store.AddTable('customers', 'name varchar(200) not null, ' +
  'phone varchar(50) not null default '''', notes text');
Store.AddTable('appointments', 'customer_id varchar(32) not null, ' +
  'starts_at varchar(16) not null, price_cents bigint not null default 0');
Store.OnCheck := @CheckRecord;
Store.CreateTables;
```

`AddTable` takes the columns as SQL, without the ones every table gets: `id`, `updated_at`, `synced_at`, `dirty`, `deleted`. The same code runs on the computers and on the server, so both check the data the same way.

```pascal
Id := Store.Save('customers', JObject(['name', 'Ayşe Yılmaz']));        // a new record: a new id
Store.Save('customers', JObject(['id', Id, 'phone', '0532 111 22 33'])); // changes only the phone
C := Store.Get('customers', Id);                                          // nil when there is none
Rows := Store.List('customers', 'lower(name) like ?', ['%ayşe%'], 'name');
Store.Delete('customers', Id);
N := Store.Pending;                                                       // changes not sent yet
```

```pascal
procedure TShop.CheckRecord(const Table: string; Data: TJSONObject);
begin
  if (Table = 'customers') and (Trim(JStr(Data, 'name')) = '') then
    raise ESyncInvalid.Create(_('A customer needs a name'));
end;
```

`OnCheck` runs before every `Save`, and for every record that comes with a sync — the other side may be an old or a broken program.

## Syncing

The computer:

```pascal
R := SyncWithServer(Store, SettingsForm.ServerUrl, SettingsForm.ApiKey, FLastSync);
StatusLabel.Text := Format(_('%d sent, %d received'), [R.Sent, R.Received]);
```

`FLastSync` is the server's time of the last sync; keep it (in the settings) and give it again next time, so only newer changes come. When the server cannot be reached, `SyncWithServer` raises `EHttpError` and nothing is lost: the changes stay marked and go next time.

The server:

```pascal
uses
  Pastel.Sync, Pastel.SyncWeb;

Store.IsServer := True;
AddSyncRoute(Web, Store);                    // POST /api/sync
Web.RequireApiKey('/api', Config.GetList('api.keys'));
```

## How it works

| Rule | Why |
|---|---|
| Ids are made where the record is made: 16 random characters | Two computers that both add a customer offline never get the same id |
| Every change stamps `updated_at` (UTC, with milliseconds) | When a record was changed on two computers, **the newer change wins** |
| A computer marks what it changes (`dirty`) | Only those are sent; after the server took them, they are not marked any more |
| Nothing is really deleted: `deleted = 1` | A deletion travels like any change |
| The server stamps what it stores with its own clock (`synced_at`) | "What is new for you" does not depend on the computers' clocks |

Sending the same records twice changes nothing, so a sync that broke off halfway is simply done again.

**When "the newer wins" is not right:** for a phone number it is. For a stock count it is not — two shops that each sold one would end with one sale. There, store the *change* as its own record (`-1 shampoo`, a new id each time) and add them up.

## Without HTTP

`Changes`, `Apply` and `MarkSent` are what `SyncWithServer` uses, for other ways of moving the data (a file on a USB stick, a message queue):

```pascal
Mine := Store.Changes('', True);              // a computer: what is dirty
Server.Apply(Mine);                           // the other side takes it
Store.MarkSent(Mine);
Theirs := Server.Changes(LastSync, False);    // the server: what is newer than LastSync
Answer := AnswerSync(Server, Request);        // the whole server side of one sync
```
