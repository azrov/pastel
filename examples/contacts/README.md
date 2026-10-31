# contacts

A desktop address book: a list with search on the left, the contact on the
right, menus and shortcuts, a confirmation before deleting. The contacts are
kept in a SQLite file in the user's app data folder (`CONTACTS_DB=file.db`
uses another one).

```sh
pastel run            # the app
pastel test           # the store's tests (tests/contactstore_test.pas)
```

What to look at:

- `src/forms/Home.pform` – the window: a menu bar, `TAction`s shared by the
  menu and the buttons, a `TRow` with two columns.
- `src/forms/Home.pas` – the event handlers; `Ask` and `ShowMessage` dialogs.
- `src/services/contactstore.pas` – the database code (`Pastel.Db`), kept out
  of the form so it can be tested without a window.
- `tests/ui.txt` – a script that clicks and types through the app:
  `CONTACTS_DB=/tmp/c.db PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/linux/debug/contacts`
