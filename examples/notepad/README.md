# notepad

A small text editor: a menu bar with shortcuts (Ctrl+N/O/S, Ctrl+Shift+S),
open and save dialogs, a status bar with the word count, word wrap and dark
mode from the View menu, and "Save the changes?" before the window closes.

```sh
pastel run -- notes.txt   # opens a file
pastel test               # tests/textstats_test.pas
```

What to look at:

- `src/forms/Home.pform` – `TMenuBar`, `TMemo`, a status bar `TRow`,
  `OnCloseQuery`.
- `src/forms/Home.pas` – `OpenFileDialog`, `SaveFileDialog`, `MessageDlg`
  with Yes/No/Cancel, `Appearance` for dark mode.
- `tests/ui.txt` – a script that types, saves, opens and closes the app:
  `PASTEL_HEADLESS=1 PASTEL_TEST_SCRIPT=tests/ui.txt ./build/linux/debug/notepad`
