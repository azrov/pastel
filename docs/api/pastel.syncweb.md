# Pastel.SyncWeb

The server side of Pastel.Sync: one route that clients sync with.

    Store := TSyncStore.Create(Db);
    Store.IsServer := True;
    Store.AddTable('customers', 'name varchar(200) not null, phone varchar(50)');
    Store.CreateTables;
    AddSyncRoute(Web, Store);                 // POST /api/sync

  Protect it like any route: [api] keys in config.toml (X-API-Key), or JWT.

`uses Pastel.SyncWeb;` · source: [framework/src/pastel.syncweb.pas](../../framework/src/pastel.syncweb.pas)

## Routines

### AddSyncRoute

```pascal
procedure AddSyncRoute(Web: TWebServer; Store: TSyncStore; const Path: string = '/api/sync')
```

POST Path: {"since": "...", "changes": {...}} -> {"now", "applied", "changes"}.
A record with a wrong value answers 422 with the reason.

