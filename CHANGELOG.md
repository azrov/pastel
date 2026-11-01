# Changelog

The `pastel` tool and the framework. The VS Code extension has its own list: [vscode/CHANGELOG.md](vscode/CHANGELOG.md). What is planned is in [ROADMAP.md](ROADMAP.md).

## 1.0.0-rc.6

Packages, like Composer for PHP.

- `pastel add serial`, `pastel add x --git URL [--path folder] [--branch b]`, `pastel remove`, `pastel update`, `pastel search`, `pastel deps [--json]`
- `[dependencies]`: `serial = "^1.2"` (the registry), `{ git = "...", version = "^0.3" }`, `branch`, `rev`; versions are git tags, ranges like Composer and Cargo (`^`, `~`, `>=`)
- `pastel.lock`: the exact commit of every package, also of the packages they use; versions that cannot both be met are explained
- One cache for all projects (`~/.cache/pastel`, `PASTEL_CACHE`); building needs no network when the packages are there
- The registry: [github.com/azrov/pastel-packages](https://github.com/azrov/pastel-packages); `PASTEL_REGISTRY` for another one
- Building: units are compiled again when their sources move (another version of a package); FPC units for a cross target are taken from the package made for that system (`Serial` for Windows from rtl-extra)
- Documentation: [docs/packages.md](docs/packages.md)

## 1.0.0-rc.5

- `TSplitter`: a bar the user drags to share the room between two controls; `TToolBar` and `TStatusBar`
- Buttons: `Icon` (38 built-in line icons, `Pastel.Icons`; your own with `RegisterIcon`) and `Style = Flat`
- UI scripts: `drag Name dx dy`
- Examples: notepad has a tool bar with icons and a status bar; contacts a splitter

## 1.0.0-rc.4

- F9 in VS Code runs the right program: with a library's file open, the program that uses it (or a choice, remembered; *Pastel: Choose the Program to Run* changes it), or its tests when nothing uses it; `pastel run` in a library names the programs that use it
- Layout: in a row that is too narrow, growing controls give up width; `pastel check` warns about rows whose controls are still cut off
- `Pastel.Inputs`: `TDatePicker`, `TCalendarView` and `TCurrencyEdit` move from the components example into the framework; new `TNumberEdit` (a whole number with ▲▼, `Min`, `Max`, `Step`) and `TTimeEdit` (`HH:MM`, `Step` minutes); documented in the controls reference
- ROADMAP: the plan from 1.0 to 2.0

## 1.0.0-rc.3

A business system as an example.

- `examples/salon-core`, `salon-desk`, `salon-api`: customers, appointments and invoices; a desktop app that works offline on SQLite and syncs with its server; both share one library; English and Turkish
- Guide: a business system — desktop app and server (`docs/guide-business.md`)
- UI scripts: text of several lines (labels, memos) is compared with `|` between the lines

## 1.0.0-rc.2

Components and documentation.

- Controls and components of libraries (`[dependencies]`) are in the designer's toolbox, like the project's own; non-visual components (`TTimer`, `TAction`, `TDataBinding`, your own) are in the schema and the toolbox too
- `examples/components`: a library with `TStarRating`, `TCurrencyEdit`, `TDatePicker` and `TFormMemory`; `examples/components-demo` uses it
- `Pastel.Lang`: `MonthName`, `DayNameShort` in 11 languages
- UI scripts: `set Name.Property value`
- Documentation: an index of all topics, a reference of every control with examples (`docs/controls.md`), every command with examples (`docs/commands.md`), writing components (`docs/components.md`); `tests/docs-coverage.sh` fails when a control, command or example is not documented
- Dependencies can be given with a full path

## 1.0.0-rc.1

The release candidate for 1.0. From 1.0 on, the framework API in `docs/api/stable.txt`, `pastel.toml`, `.pform` files and the `pastel` commands stay compatible within 1.x ([docs/compatibility.md](docs/compatibility.md)).

- Project files: `pastel = "1.0"`; `pastel upgrade` brings 0.x projects up to date
- Contributing guide, security policy, code of conduct, issue and pull request forms
- Workflows to publish the VS Code extension on the Marketplace and Open VSX

## 0.7.0 — Road to 1.0

- The stable API is frozen in `docs/api/stable.txt` and checked by the tests; helpers for Pastel's own use are marked *Internal*
- `pastel.toml` records the Pastel version (`pastel = "0.7"`); `pastel upgrade [--check]`; unknown settings are reported
- Web server limits: body size (413), header size (431), slow clients (408), connections (503); `[server] max_body_mb`, `request_timeout`, `max_connections`
- Security: static files checked once more on the final path; `X-Content-Type-Options: nosniff`; behind a proxy only the last `X-Forwarded-For` address counts; faster rate limiter
- `tests/perf.sh`: start-up time, size, memory, requests per second, drawing speed ([docs/performance.md](docs/performance.md))
- CI for Linux, Linux ARM64 and Windows; release builds and `install.sh` for tags; the documentation as a website with checked links

## 0.6.0 — Desktop apps, complete and shippable

- `TGrid`, `TListView`, `TTreeView`; `TDataBinding` (controls ↔ JSON rows, objects, grid rows)
- Translations: `assets/lang/*.json`, `_('...')`, `pastel lang`; number and date formats of the language
- `assets/theme.toml`; the system's file dialogs; the `.exe` icon from `assets/icon.png`
- Packages: `pastel package appimage`, `installer` (Windows, NSIS), desktop `.deb` with menu entry and icon; SDL2 and FreeType DLLs next to Windows programs
- `pastel doctor --install windows`: builds for Windows on Linux without a cross-compiler
- Only what changed is repainted; `PASTEL_CHECK_REPAINT=1`
- The project's own controls (`src/controls/`, `pastel new control`) in `.pform` files, the designer and its toolbox

## 0.5.0 — Desktop apps, essentials

- About 20 new controls: check boxes, radio buttons, switches, combo boxes, list boxes, memos, images, tabs, scroll boxes, progress bars, sliders, spinners, menus, popup menus, actions, timers, tooltips
- Dialogs: `ShowMessage`, `Ask`, `MessageDlg`, `InputBox`, open/save/folder; several forms, `ShowModal`, `pastel new form`
- Text editing with selection, clipboard and undo; word-wrapped labels
- Dark theme, high-DPI drawing, assets compiled into release builds, window icon and fonts from `assets/`
- Hot reload keeps what the user typed and chose
- UI test scripts drive dialogs, menus and tabs
- Examples: `contacts` (SQLite address book), `notepad` (text editor)

## 0.4.0 — Code intelligence in VS Code

- Pascal completion, hover, parameter hints, go to definition, find references and rename, from the project, the framework and the Free Pascal sources
- Compiler errors while typing; quick fixes (add a unit to `uses`, complete a class)
- The API reference (`docs/api/`) made from the framework's comments

## 0.3.0 — Linux services

- `pastel new service` and `pastel new api`; `pastel migrate`; `pastel package deb` and `docker`
- `Pastel.Service` (systemd, signals, jobs), `Pastel.Web` (routes, JSON, static files, CORS, API keys, JWT, rate limits, validation), `Pastel.Db` (SQLite, PostgreSQL, MySQL, transactions, pool, migrations), `Pastel.Workers`, `Pastel.Crypto`, `Pastel.Jwt`
- VS Code: routes, jobs and migrations in the Pastel panel; ▶ Send above routes

## 0.2.0 — Console programs, complete

- `pastel test`, `run --watch`, `fmt`, `package`, `new lib`, local dependencies, profiles
- `Pastel.Testing`, `Pastel.Args`, `Pastel.Term`, `Pastel.Text`, `Pastel.Log`, `Pastel.Config`, `Pastel.Json`, `Pastel.Files`, `Pastel.Process`, `Pastel.Http`, `Pastel.Env`
- VS Code: test explorer, snippets, F5 debugging, format on save
- Examples: `dupfinder`, `weather`

## 0.1.0 — Foundation

- `pastel new`, `build`, `run`, `clean`, `targets`, `doctor`, `check`, `preview`, `schema`; cross-compiling to Windows and Raspberry Pi
- The UI framework: SDL2 window, FreeType text, `.pform` forms with generated base classes, flexbox-style layout, hot reload
- VS Code: form designer, `.pform` language support, run and build commands
