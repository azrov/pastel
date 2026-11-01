# salon-core

The shared part of a small business system — a hair salon here, but the same fits a clinic, a repair shop or a tutor: **customers, appointments and invoices**, and the **synchronization** between the computers in the shop and the server.

It is a library (`type = "lib"`) used by two programs:

| | |
|---|---|
| [salon-desk](../salon-desk) | The desktop app in the shop (Linux, Windows). Works without a network, on a SQLite file; a click on *Sync* exchanges the changes with the server |
| [salon-api](../salon-api) | The server: keeps everything (PostgreSQL, MySQL or SQLite) and answers `POST /api/sync`; also a small read-only API |

Both use the same units, so a customer is checked and stored the same way on the desktop and on the server.

| Unit | |
|---|---|
| `SalonStore` | The tables, saving with checks, lists, a day's appointments, invoices with VAT, and the sync: `Changes`, `Apply`, `MarkSent` — on [Pastel.Sync](../../docs/sync.md) |
| `SalonSync` | The desktop side of the sync over HTTP |
| `SalonMoney` | Money in cents: `CentsToText`, `TryTextToCents`, `VatOf` |
| `SalonPrint` | An invoice as PDF or HTML (`InvoiceReport`, [Pastel.Report](../../docs/documents.md)), the invoices as an Excel file (`InvoicesSheet`) |

How the sync works: every record gets its id where it is made (no clashes between computers) and `updated_at`, the time of its last change. The desktop marks what it changes (`dirty`), sends it, and takes what the server got from the other computers since its last sync. When both sides changed a record, the newer change wins. Records are never deleted, only marked, so deletions travel too.

```sh
pastel test     # tests/store_test.pas: two desktops and a server, synced by hand
```
