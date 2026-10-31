# Pastel roadmap to 1.0

Pastel grows in this order: **console programs → Linux services → desktop apps**. Each step builds on the one before: a service is a console program that runs for a long time, and a desktop app uses the same libraries as a service.

Every milestone ends with something you can really use, and with tests and documentation for it. Items are checked off as they are done.

**Version 1.0 means:** you can build and ship a real console tool, a real Linux service (REST API with a database, packaged and running under systemd) and a real desktop business app (Linux and Windows) with Pastel, using VS Code, without hitting a wall. File formats (`pastel.toml`, `.pform`) and public APIs are stable from 1.0 on.

---

## 0.1 — Foundation (done)

What exists today.

**Tool (`pastel`)**
- [x] `new console`, `new app`, `build`, `run`, `clean`, `targets`, `doctor`
- [x] Debug and release builds, compiler errors with file and line
- [x] Cross-compiling to Windows and Raspberry Pi (when the cross-compilers are installed)
- [x] `check`, `preview`, `schema` for editors

**GUI framework**
- [x] Window, event loop, software rendering with FreeType text (SDL2)
- [x] `.pform` forms, generated base classes, RTTI properties and events
- [x] Controls: label, button, edit, card, row, column, spacer
- [x] Flexbox-style layout, keyboard focus, clipboard
- [x] Window settings and events (resizable, maximize, close query, ...)
- [x] Hot reload of `.pform` files, headless mode and UI test scripts

**VS Code extension**
- [x] Run/Build commands and Delphi keys, problems panel
- [x] Form designer (select, properties, drag and drop, toolbox)
- [x] `.pform` completion, checks, quick fixes
- [x] Pascal colors, outline, go to definition, symbol search
- [x] Pastel panel in the activity bar

---

## 0.2 — Console programs, complete (done)

Goal: writing a command-line tool in Pastel is pleasant from the first line to the release.

**Tool**
- [x] `pastel test`: finds and runs tests in `tests/`, clear report, exit code for CI
- [x] `pastel run --watch`: rebuild and restart when a file changes (also `pastel test --watch`)
- [x] `pastel fmt`: format Pascal code with one standard style (`--check` for CI, `--stdin` for editors)
- [x] `pastel package`: a `.tar.gz` (Linux) or `.zip` (Windows) with the program, ready to hand out
- [x] `pastel new lib`: a library project that other projects can use
- [x] Use another local Pastel project as a dependency (`[dependencies]` in `pastel.toml`)
- [x] `pastel.toml`: version shown by the program (`--version`, generated `AppInfo` unit)
- [x] `pastel.toml`: build-time defines per profile

**Library (`Pastel.Core`, usable without the GUI)**
- [x] `Pastel.Testing`: test cases, asserts with readable messages
- [x] `Pastel.Args`: command-line arguments and sub-commands, automatic `--help`
- [x] `Pastel.Term`: colors, tables, progress bars, prompts (yes/no, input, choice)
- [x] `Pastel.Text`: upper/lower case and lengths for every language (Turkish/Azerbaijani i)
- [x] UTF-8 everywhere, also in the Windows console; thread support without `cthreads` in `uses`
- [x] `Pastel.Log`: log levels, to the console or a file, with timestamps (also JSON, journald, rotation, threads)
- [x] `Pastel.Config`: settings from `.toml`, `.json` and environment variables
- [x] `Pastel.Json`: easy reading and writing of JSON (on top of FPC's fpjson)
- [x] `Pastel.Files` and `Pastel.Process`: paths, reading/writing files, running other programs
- [x] `Pastel.Http` client: GET/POST with JSON, timeouts, HTTPS with certificate checks, proxies
- [x] `Pastel.Env`: environment variables in UTF-8 (also on Windows)

**VS Code**
- [x] Test explorer: run and debug single tests from the editor
- [x] Pascal snippets (class, procedure, try/finally, for, case, ...)
- [x] F5 debugging without manual setup; readable strings and arrays in the debugger
- [x] Format on save (uses `pastel fmt`)

**Docs**
- [x] Getting started guide (install, first project, debug, release): `docs/getting-started.md`
- [x] Console programs: `docs/console.md`; testing: `docs/testing.md`; JSON, settings, logging: `docs/data.md`; files, programs, HTTP: `docs/system.md`; watch, format, libraries: `docs/workflow.md`; `pastel.toml` and packages: `docs/project.md`
- [x] Guide: writing a command-line tool: `docs/guide-cli.md`
- [x] Examples: a file tool, a tool that calls a web API: `examples/dupfinder`, `examples/weather`

---

## 0.3 — Linux services (done)

Goal: a REST API with a database, deployed on a Linux server as a systemd service, built only with Pastel.

**Tool**
- [x] `pastel new service`: a long-running program with configuration, logging and clean shutdown (with a systemd unit)
- [x] `pastel new api`: a web API project with models, controllers, migrations and tests
- [x] `pastel package deb`: a `.deb` with the program, its config file and a systemd unit
- [x] `pastel package docker`: a container image (Debian slim, non-root, health check); a static image without a base OS later
- [x] `pastel migrate`: run database migrations (`database/migrations/`); `status`, `new`
- [x] `pastel run` restarts the service on code changes (with `--watch`)

**Library (`Pastel.Service`, `Pastel.Web`, `Pastel.Db`)**
- [x] Service life cycle: start, stop on SIGTERM/SIGINT, reload config on SIGHUP; systemd notify and watchdog
- [x] Logging in a form journald understands; optional JSON logs
- [x] Timers and scheduled jobs (every N seconds, daily at a time)
- [x] Background worker threads and safe message passing between them: `Pastel.Workers`
- [x] HTTP server: routing (`GET /users/:id`), JSON requests and responses, static files
- [x] Middleware: logging, CORS, authentication (API keys, JWT), rate limits
- [x] Validation of request data with clear error responses
- [x] `Pastel.Crypto`: password hashing, random tokens, SHA-256/HMAC; `Pastel.Jwt`
- [x] Health check endpoint for monitoring
- [x] Database access for SQLite, PostgreSQL and MySQL/MariaDB (on top of FPC's SQLDB): `docs/database.md`
- [x] Simple query API with parameters; transactions; connection pool
- [x] Migrations with version tracking
- [x] HTTPS (OpenSSL) or a guide for running behind nginx/caddy: `docs/deploy.md`

**VS Code**
- [x] Project explorer shows routes, jobs and migrations for service and API projects
- [x] "Send request" for routes (try an endpoint from the editor): CodeLens above routes, button in the panel

**Docs**
- [x] Guide: build a REST API (with a database): `docs/guide-api.md`
- [x] Guide: deploy to a Linux server (systemd, .deb, Docker, nginx): `docs/deploy.md`
- [x] Example: a to-do REST API with SQLite and PostgreSQL (what `pastel new api` makes; tested on MariaDB too)

---

## 0.4 — Code intelligence (done)

Goal: VS Code understands Pascal like Lazarus/Delphi do.

- [x] Pascal code intelligence: completion of members (`NameEdit.` → `Text`, `SetFocus`, ...), parameter hints, hover with types; it reads the project, the Pastel framework and the Free Pascal sources (in the VS Code extension; a language server for other editors later)
- [x] Find all references, rename a symbol across the project
- [x] Errors underlined while typing (not only after building): the compiler checks the unsaved text, `pastel check file.pas --stdin`
- [x] Unit names in `uses` completed from the project, the framework and Free Pascal
- [x] Quick fixes: add a missing unit to `uses`, create a method body from its declaration (Delphi's Ctrl+Shift+C)
- [x] Documentation comments shown in hover and completion; API reference generated from them: `docs/api/`

---

## 0.5 — Desktop apps, essentials (done)

Goal: typical small business apps (forms, lists, dialogs) on Linux and Windows.

**Controls**
- [x] CheckBox, RadioButton (grouped by parent), Switch
- [x] ComboBox (drop-down list)
- [x] Memo (multi-line text, scrolling, word wrap)
- [x] ListBox with many items (only visible rows are drawn); a multi-column ListView moves to 0.6
- [x] Image (PNG, JPEG), icons
- [x] ScrollBox (scrolling area), TabControl (pages)
- [x] ProgressBar, Slider, Spinner
- [x] Menu bar, context menus, keyboard shortcuts (actions)
- [x] Tooltips

**Framework**
- [x] Text editing: selection with mouse and Shift, cut/copy/paste of selection, undo
- [x] Label word wrap and multi-line text
- [x] More than one form; modal dialogs (`ShowModal`)
- [x] Dialogs: `ShowMessage`, confirm, input; open/save file dialogs (drawn by Pastel inside the window; native dialogs move to 0.6)
- [x] `TTimer`; running work in a thread and updating the UI safely
- [x] `.pform`: nested properties (`Font.Size`) and lists (`Items = ('A', 'B')`)
- [x] High-DPI screens (scaling)
- [x] Dark theme and theme switching (`Appearance`: light, dark, system)
- [x] Fonts and images from `assets/`, bundled into the program
- [x] App icon: window icon from `assets/icon.png` (the icon of the Windows .exe file moves to 0.6)
- [x] Hot reload keeps typed text and state where possible

**VS Code designer**
- [x] Undo/redo inside the designer, copy/paste of controls
- [x] Rename a control (updates the `.pas` code too)
- [x] "New Form" command
- [x] Preview at different window sizes and in dark theme

**Docs**
- [x] Guide: building a desktop app (`docs/guide-desktop.md`); reference of all controls
- [x] Examples: `notepad` (text editor), `contacts` (address book with SQLite), both with UI test scripts

---

## 0.6 — Desktop apps, complete and shippable (done)

- [x] Grid/table control (`TGrid`: sorting, editing, many rows)
- [x] `TTreeView`, multi-column `TListView`
- [x] The system's open/save dialogs (Windows; zenity or kdialog on Linux), Pastel's drawn ones as fallback
- [x] Icon of the Windows `.exe` file from `assets/icon.png`; app-wide styles (`assets/theme.toml`)
- [x] Data binding: `TDataBinding` connects controls to JSON rows (database), objects or grid rows
- [x] Translations (`assets/lang/*.json`, `_('...')`, `pastel lang`), number and date formats of the language
- [x] Windows: SDL2/FreeType DLLs copied next to the program automatically; installer (`pastel package installer`)
- [x] Linux desktop: AppImage and `.deb` with menu entry and icon
- [x] `pastel doctor --install windows`: compiles the Windows units from the Free Pascal sources and gets the DLLs (Raspberry Pi still needs a cross-compiler from fpcupdeluxe)
- [ ] Move from SDL2 to SDL3 (when Linux distributions ship it) — moved to after 1.0
- [x] Faster drawing: only what changed is repainted (and uploaded to the screen)
- [x] Custom controls in your project show up in the designer's toolbox (`src/controls/`, `pastel new control`)

---

## 0.7 — Road to 1.0 (done, except testing on other machines)

- [x] Review all public APIs and file formats; then freeze them: `docs/api/stable.txt` lists the stable API and the tests fail when a line of it disappears; helpers for Pastel's own use are marked *Internal* ([compatibility.md](docs/compatibility.md))
- [x] `pastel.toml` records the Pastel version it was made for (`pastel = "0.7"`); `pastel upgrade` for older projects; unknown settings are reported
- [x] Complete documentation website (`tools/site`, published with GitHub Pages; every link and anchor is checked by the tests); all examples tested in CI
- [ ] Tested hosts: Linux x64 is tested; the CI jobs for Linux ARM64 (Raspberry Pi class) and Windows are set up but have not run yet
- [x] CI on Linux, Linux ARM64 and Windows; release builds made automatically for a tag (`.github/workflows/release.yml`, `tools/pack-release.sh`)
- [x] Security review of the web server and the database layer: request size, header size, timeouts and connection limits, path checks, `X-Forwarded-For` ([security.md](docs/security.md#what-the-web-server-and-the-database-layer-protect-against))
- [x] Performance checks: start-up time, memory, requests per second, drawing speed (`tests/perf.sh`, [performance.md](docs/performance.md))

---

## 1.0.0

- [ ] Release on GitHub with ready-made downloads (Linux, Windows) and an install script (`tools/install.sh` and the release workflow are ready)
- [ ] VS Code extension on the Marketplace and Open VSX
- [ ] Announcement, contributing guide, issue templates

---

## After 1.0

- SDL3 instead of SDL2
- Cross-compilers for Raspberry Pi installed by `pastel doctor --install`
- Android and iOS apps
- macOS (desktop) packages and signing
- GPU drawing (Skia) for heavy graphics
- Web target (WebAssembly)
- Package registry for sharing libraries
- Accessibility (screen readers)

---

## Known gaps today

Things that work differently than one would expect, so they are not surprises:

- Building for Raspberry Pi needs a cross-compiler installed by hand (fpcupdeluxe); Windows: `pastel doctor --install windows`
- Windows programs that use HTTPS need the OpenSSL DLLs next to them; `[package.windows] include` puts them into the package
- In desktop apps, code changes restart the app (`pastel run --watch`); only `.pform` changes are hot-reloaded
- macOS and 32-bit Raspberry Pi are not tested yet
