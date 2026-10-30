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

## 0.3 — Linux services (next)

Goal: a REST API with a database, deployed on a Linux server as a systemd service, built only with Pastel.

**Tool**
- [ ] `pastel new service`: a long-running program with configuration, logging and clean shutdown
- [ ] `pastel new api`: a web API project with routes and controllers (Laravel-like structure)
- [ ] `pastel package deb`: a `.deb` with the program, its config file and a systemd unit
- [ ] `pastel package docker`: a small container image (static binary, no base OS needed)
- [ ] `pastel migrate`: run database migrations (`database/migrations/`)
- [ ] `pastel run` restarts the service on code changes (with `--watch`)

**Library (`Pastel.Service`, `Pastel.Web`, `Pastel.Db`)**
- [ ] Service life cycle: start, stop on SIGTERM/SIGINT, reload config on SIGHUP
- [x] Logging in a form journald understands; optional JSON logs
- [ ] Timers and scheduled jobs (every N seconds, daily at a time)
- [ ] Background worker threads and safe message passing between them
- [ ] HTTP server: routing (`GET /users/:id`), JSON requests and responses, static files
- [ ] Middleware: logging, CORS, authentication (API keys, JWT), rate limits
- [ ] Validation of request data with clear error responses
- [ ] Health check endpoint for monitoring
- [ ] Database access for SQLite, PostgreSQL and MySQL/MariaDB (on top of FPC's SQLDB)
- [ ] Simple query API with parameters; transactions; connection pool
- [ ] Migrations with version tracking
- [ ] HTTPS (OpenSSL) or a guide for running behind nginx/caddy

**VS Code**
- [ ] Project explorer shows routes, migrations and services for API projects
- [ ] "Send request" for routes (try an endpoint from the editor)

**Docs**
- [ ] Guide: build a REST API (with a database)
- [ ] Guide: deploy to a Linux server (systemd, .deb, Docker, nginx)
- [ ] Example: a to-do REST API with SQLite and PostgreSQL

---

## 0.4 — Code intelligence

Goal: VS Code understands Pascal like Lazarus/Delphi do.

- [ ] Pascal language server: completion of members (`NameEdit.` → `Text`, `SetFocus`, ...), parameter hints, hover with types
- [ ] Find all references, rename a symbol across the project
- [ ] Errors underlined while typing (not only after building)
- [ ] Unit names in `uses` completed from the project and the framework
- [ ] Quick fixes: add a missing unit to `uses`, create a method body from its declaration (Delphi's Ctrl+Shift+C)
- [ ] Documentation comments shown in hover and completion; API reference generated from them

---

## 0.5 — Desktop apps, essentials

Goal: typical small business apps (forms, lists, dialogs) on Linux and Windows.

**Controls**
- [ ] CheckBox, RadioButton/RadioGroup, Switch
- [ ] ComboBox (drop-down list)
- [ ] Memo (multi-line text, scrolling, word wrap)
- [ ] ListBox / ListView with many items (only visible rows are drawn)
- [ ] Image (PNG, JPEG), icons
- [ ] ScrollBox (scrolling area), TabControl (pages)
- [ ] ProgressBar, Slider, Spinner
- [ ] Menu bar, context menus, keyboard shortcuts (actions)
- [ ] Tooltips

**Framework**
- [ ] Text editing: selection with mouse and Shift, cut/copy/paste of selection, undo
- [ ] Label word wrap and multi-line text
- [ ] More than one form; modal dialogs (`ShowModal`)
- [ ] Dialogs: `ShowMessage`, confirm, input; open/save file dialogs
- [ ] `TTimer`; running work in a thread and updating the UI safely
- [ ] `.pform`: nested properties (`Font.Size`) and lists (`Items = ('A', 'B')`)
- [ ] High-DPI screens (scaling)
- [ ] Dark theme and theme switching; app-wide styles
- [ ] Fonts and images from `assets/`, bundled into the program
- [ ] App icon (window and file)
- [ ] Hot reload keeps typed text and state where possible

**VS Code designer**
- [ ] Undo/redo inside the designer, copy/paste of controls
- [ ] Rename a control (updates the `.pas` code too)
- [ ] "New Form" command
- [ ] Preview at different window sizes and in dark theme

**Docs**
- [ ] Guide: building a desktop app; reference of all controls
- [ ] Example: a notes app, an address book with SQLite

---

## 0.6 — Desktop apps, complete and shippable

- [ ] Grid/table control (sorting, editing, many rows)
- [ ] TreeView
- [ ] Data binding: connect controls to objects or database rows
- [ ] Translations (`assets/lang/`), right number and date formats
- [ ] Windows: SDL2/FreeType DLLs copied next to the program automatically; installer (`pastel package windows`)
- [ ] Linux desktop: AppImage and `.deb` with menu entry and icon
- [ ] `pastel doctor --install`: download and set up cross-compilers for Windows and Raspberry Pi
- [ ] Move from SDL2 to SDL3 (when Linux distributions ship it)
- [ ] Faster drawing: repaint only what changed
- [ ] Custom controls in your project show up in the designer's toolbox

---

## 0.7 — Road to 1.0

- [ ] Review all public APIs and file formats; then freeze them
- [ ] `pastel.toml` records the Pastel version it was made for; upgrade helper for older projects
- [ ] Complete documentation website; all examples tested in CI
- [ ] Tested hosts: Linux x64 and ARM64 (Raspberry Pi), Windows 10/11 (and Windows 7 as far as possible)
- [ ] CI on Linux and Windows, release builds made automatically
- [ ] Security review of the web server and the database layer
- [ ] Performance checks: start-up time, memory, requests per second, drawing speed

## 1.0.0

- [ ] Release on GitHub with ready-made downloads (Linux, Windows) and an install script
- [ ] VS Code extension on the Marketplace and Open VSX
- [ ] Announcement, contributing guide, issue templates

---

## After 1.0

- Android and iOS apps
- macOS (desktop) packages and signing
- GPU drawing (Skia) for heavy graphics
- Web target (WebAssembly)
- Package registry for sharing libraries
- Accessibility (screen readers)

---

## Known gaps today

Things that work differently than one would expect, so they are not surprises:

- Building for Windows/Raspberry Pi needs cross-compilers installed by hand (fpcupdeluxe)
- Windows programs need `SDL2.dll` and `freetype.dll` (desktop apps) or the OpenSSL DLLs (HTTPS) next to them; `[package.windows] include` puts them into the package
- In desktop apps, code changes restart the app (`pastel run --watch`); only `.pform` changes are hot-reloaded, and they reset typed text
- One window per app; no dialogs yet
- No text selection in edits; no multi-line text
- Pascal completion only knows `.pform` files, not members of Pascal classes
- macOS and 32-bit Raspberry Pi are not tested yet
