# Guide: a business system — desktop app and server

Many small businesses need the same thing: a program at the reception that works even when the internet does not, and a server that keeps everything together, for a second computer, a web page or a phone app. This guide shows how the salon example is built, so you can build your own (a clinic, a repair shop, a warehouse) the same way.

![The salon app in Turkish](images/salon.png)

The example has three projects:

| Project | Kind | What it is |
|---|---|---|
| [`examples/salon-core`](../examples/salon-core) | `lib` | The data, its checks and the synchronization — **shared** |
| [`examples/salon-desk`](../examples/salon-desk) | `app` | The desktop app: SQLite on the computer, *Sync* button |
| [`examples/salon-api`](../examples/salon-api) | `service` | The server: PostgreSQL, MySQL or SQLite; `POST /api/sync` |

```
salon-desk ──uses──> salon-core <──uses── salon-api
     │                                       ▲
     └────── POST /api/sync (HTTP, JSON) ────┘
```

## 1. Put the data in a library

The checks ("a customer needs a name", "an e-mail has an @") and the SQL must be the same on the desktop and on the server. So they go into a library, used by both:

```sh
pastel new lib salon-core
```

```toml
# salon-desk/pastel.toml and salon-api/pastel.toml
[dependencies]
salon-core = { path = "../salon-core" }
```

The store works on any database `Pastel.Db` knows; the desktop gives it a SQLite file, the server what its settings say:

```pascal
Store := TSalonStore.Create(TDatabase.Open('sqlite:' + DbFile), True);     // desktop
Store := TSalonStore.Create(TDatabase.Open(Config.Require('database.url')), True);   // server
Store.CreateTables;
```

Records are JSON objects (what `Pastel.Db` returns), so they go straight into lists, data bindings and HTTP answers:

```pascal
Id := Store.Save(skCustomer, CustomerData.ToJson);     // checked; ESalonInvalid with a message
Rows := Store.Day('2026-11-03');                        // the appointments, with customer_name
Store.Invoice(CustomerId, AppointmentIds, 20);          // lines, VAT, the next number
```

Two rules make synchronization possible later — follow them from the first day:

- **Ids are made where the record is made** (`NewId`: 16 random characters), not by the database (`autoincrement`). Two computers that both add a customer offline never get the same id.
- **Nothing is really deleted.** `Delete` sets `deleted = 1`, so the deletion can travel to the other computers like any change.

Money is kept in **cents** (`price_cents`, an `Int64`): `0.10 + 0.20` is exactly `0.30`, and VAT is rounded once, on purpose (`VatOf`).

## 2. Work offline, remember what changed

Every `Save` writes `updated_at` (the time, UTC, sortable as text: `2026-11-01T09:30:00.123000Z`) and `dirty = 1`: "changed here, not sent yet". The desktop works on its own file all day; the network is only needed for the *Sync* button.

## 3. Synchronize

One request does everything:

```
POST /api/sync
{"since": "<the server's time of the last sync>",
 "changes": {"customers": [...], "appointments": [...], "invoices": [...]}}     the dirty records

200 {"now": "...", "applied": 2,
     "changes": {"customers": [...], ...}}      what other computers sent since "since"
```

The desktop side ([`SalonSync`](../examples/salon-core/src/salonsync.pas)):

```pascal
R := SyncWithServer(Store, SettingsForm.ServerUrl, SettingsForm.ApiKey, FLastSync);
StatusLabel.Text := Format(_('Synced: %d sent, %d received.'), [R.Sent, R.Received]);
```

The server side ([`saloncontroller.pas`](../examples/salon-api/src/controllers/saloncontroller.pas)) — the same store, three calls:

```pascal
Now_ := NowStamp;                                   // before anything is taken
Applied := FStore.Apply(Changes, True);             // True: stamp them with the server's clock
Theirs := FStore.Changes(Since, False);             // what was stored after "since"
```

When the same record was changed on two computers, **the newer change wins** (`updated_at`): `Apply` stores a record only when it is newer than the one there. That makes the sync safe to repeat — sending the same records twice changes nothing — and a failed sync loses nothing: the records stay dirty and go next time.

"Since" uses the **server's clock** (`synced_at`), not the computers': their clocks may be wrong by minutes, the server's is one clock for all.

The tests sync two "desktops" and a "server" (three SQLite files) by hand, without HTTP: [`tests/store_test.pas`](../examples/salon-core/tests/store_test.pas) — the newer change wins, deletions travel, syncing twice changes nothing. [`tests/sync_api_test.pas`](../examples/salon-api/tests/sync_api_test.pas) does it over real HTTP.

## 4. The desktop app

Three pages in a `TTabControl`; each page is a list (`TListView`) with a form next to it:

```
object DayList: TListView              // Time, Customer, Service, Price, Status
  Sortable = False
  OnChange = DayListChange
  ...
object AppointmentCard: TCard          // the selected appointment, or a new one
  object CustomerCombo: TComboBox
  object TimeCombo: TComboBox
  object PriceEdit: TCurrencyEdit      // from examples/components
```

- The day is a `TDatePicker` with ‹ › and *Today* buttons; changing it reloads the list (`OnChange`).
- Customers use a `TDataBinding`: `CustomerData.Load(Row)` fills the form, `CustomerData.ToJson` is the record to save.
- The settings (server address, API key, VAT) are a second form shown with `ShowModal`, remembered by a `TFormMemory`.
- Every text is in `_('...')` or the `.pform`; `pastel lang add tr` made `assets/lang/tr.json`.

## 5. The server

A `pastel new api` project with the template's tasks replaced by one controller. In production:

```toml
# config.toml on the server
[database]
url = "postgres://salon:secret@localhost/salon"
[api]
keys = ["<one key per shop computer: openssl rand -base64 32>"]
```

```sh
pastel package deb      # then on the server: sudo apt install ./dist/salon-api_1.0.0_amd64.deb
```

Put it behind HTTPS ([deploy.md](deploy.md)); the read-only routes (`/api/customers`, `/api/appointments?date=`, `/api/invoices`) are there for a web page or a phone app.

## 6. Test it like a user

The UI scripts drive the real app without a screen ([`tests/ui.txt`](../examples/salon-desk/tests/ui.txt)):

```
click CustomersPage
type NameEdit Ayşe Yılmaz
click SaveCustomerButton
expect CountsLabel 1 customers, 0 invoices
click AgendaPage
set DayPicker.DateText 2026-11-03
...
click CreateInvoiceButton
expect InvoiceLinesLabel 2026-11-03 Color: 900.50|Net 900.50 + VAT 20% 180.10 = 1,080.60
```

`tests/run.sh` also starts the server and lets two "computers" sync through it ([`tests/sync.txt`](../examples/salon-desk/tests/sync.txt), [`tests/sync-2.txt`](../examples/salon-desk/tests/sync-2.txt)).

## Going further

- **Who changed what:** add a `changed_by` field (the computer's or the user's name) to every record; the sync carries it along.
- **Conflicts that matter:** "the newer wins" is right for a phone number. For stock counts, send the *change* (`-2 shampoo`) instead of the new value, and add them up on the server.
- **More than one shop:** a `shop_id` on every record, and `Changes` only sends a shop its own records.
