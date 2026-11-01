# salon-api

The server of the salon system ([salon-core](../salon-core)): it keeps the data of every computer in the shop and answers their synchronization; a small read-only API shows the data to other programs (a web page, a phone app).

| Route | |
|---|---|
| `POST /api/sync` | `{"since": "...", "changes": {...}}` from the desktop: takes its changes, answers with what changed since its last sync |
| `GET /api/customers?q=ayşe` | Customers whose name, phone or e-mail contain `q` |
| `GET /api/appointments?date=2026-11-03` | The appointments of a day, with the customer's name |
| `GET /api/invoices` | The invoices, newest first |
| `GET /api/invoices/:id/pdf` | One invoice as PDF (the same as the desktop's, from [`SalonPrint`](../salon-core/src/salonprint.pas)) |
| `GET /api/invoices.xlsx` | Every invoice as an Excel file, to download |
| `GET /health` | For monitoring |

```sh
pastel run                              # http://127.0.0.1:8080, data in data/salon.db
curl localhost:8080/api/customers
pastel test                             # tests/sync_api_test.pas: the routes over real HTTP
pastel package deb                      # for a Linux server with systemd (deploy/)
```

Settings are in `config.toml` (`[database] url` for PostgreSQL or MySQL; `[salon] address`, the name and address on invoices; `[api] keys` so only the shop's computers get in). See [docs/web.md](../../docs/web.md) and [docs/deploy.md](../../docs/deploy.md).
