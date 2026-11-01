# Announcing Pastel 1.0

*The release announcement (blog, forums, Free Pascal and Lazarus communities, Hacker News).*

---

**Pastel 1.0 is out: a free, Delphi-like way to build programs in Object Pascal, with VS Code and Free Pascal.**

Many of us learned programming with Delphi: draw a form, double-click a button, write the code, press F9. Pastel brings that way of working to today's tools — and to more than desktop apps.

## What you can build

- **Desktop apps for Linux and Windows.** Forms live in readable `.pform` files that you design in VS Code: drag controls in, set properties, double-click an event to write its code. About 40 controls (grids, trees, menus, dialogs, tabs, date pickers, money fields, tool bars, splitters, 38 icons...), data binding, translations, themes and dark mode, sharp on high-DPI screens. Save the form while the app runs and the window updates at once.
- **Web APIs and Linux services.** Routes, JSON, validation, API keys and JWT, rate limits, SQLite/PostgreSQL/MySQL with migrations, background jobs, systemd, `.deb` and Docker packages.
- **Command-line tools.** Arguments with automatic help, colors and tables, settings, logging, HTTP, tests.

![The contacts example](images/contacts.png)

## What it feels like

```sh
pastel new app contacts
cd contacts
pastel run
```

```pascal
procedure THomeForm.SaveClick(Sender: TObject);
begin
  FStore.SaveJson(ContactData.ToJson);
  ShowMessage('Saved.');
end;
```

VS Code knows your code and the framework: completion, hover, go to definition, rename, compiler errors while you type, a test explorer, F5 debugging with readable objects, lists and JSON.

Libraries are shared like with Composer or npm: `pastel add serial` fetches a package, keeps its exact version in `pastel.lock`, and its controls appear in the designer's toolbox. The registry is [pastel-packages](https://github.com/azrov/pastel-packages); [pastel-extras](https://github.com/azrov/pastel-extras) has the first ones (serial ports).

When the app is ready: `pastel package installer --target windows` makes a Windows installer, `pastel package appimage` and `pastel package deb` Linux packages — all from one Linux machine.

## Fast and small

A console program starts in a millisecond; a desktop app is under a megabyte and draws its first frame in 30 ms; a web service uses a few megabytes of memory and answers thousands of requests per second. Pastel programs are native code compiled by [Free Pascal](https://www.freepascal.org/).

## Stable

1.0 means the framework API, the project file, the form format and the commands stay compatible for all of 1.x. Projects from earlier versions come along with `pastel upgrade`.

## Get it

- Linux: `curl -fsSL https://github.com/azrov/pastel/releases/latest/download/install.sh | sh`
- Windows: the `.zip` from the release page
- VS Code: the `.vsix` from the release page (*Extensions → ⋯ → Install from VSIX*)
- Docs and guides: [github.com/azrov/pastel/tree/main/docs](https://github.com/azrov/pastel/tree/main/docs); start with *Getting started*

Pastel is MIT-licensed and made in the open. Bug reports, ideas and contributions are very welcome — see [CONTRIBUTING.md](https://github.com/azrov/pastel/blob/main/CONTRIBUTING.md).
