# Pastel documentation

Everything about Pastel, by topic. Every page has examples you can copy; the [examples](#examples) are complete programs that are built and tested with every change.

## Getting started

| | |
|---|---|
| [Getting started](getting-started.md) | Install, the first project, debugging, a release — in fifteen minutes |
| [The `pastel` command](commands.md) | Every command with examples |
| [The project file](project.md) | Everything in `pastel.toml`; upgrading a project |

## Guides: a whole program, step by step

| | |
|---|---|
| [A command-line tool](guide-cli.md) | Arguments, files, output, tests, a release |
| [A REST API with a database](guide-api.md) | Routes, JSON, validation, migrations, deployment |
| [A desktop app](guide-desktop.md) | Forms, menus, dialogs, tables, data, languages, an installer |
| [A business system: desktop + server](guide-business.md) | One library shared by a desktop app and its server; working offline and syncing |

## Desktop apps

| | |
|---|---|
| [Forms and controls](forms.md) | `.pform` files, layout, the designer, hot reload, UI test scripts |
| [Controls reference](controls.md) | Every control and component, each with a `.pform` and a code example |
| [Writing components](components.md) | Your own controls and non-visual components; sharing them in a library |

## Programs and services

| | |
|---|---|
| [Console programs](console.md) | Arguments, colors, tables, questions, progress |
| [JSON, settings and logging](data.md) | `Pastel.Json`, `Pastel.Config`, `Pastel.Log` |
| [Files, programs, HTTP](system.md) | `Pastel.Files`, `Pastel.Process`, `Pastel.Http`, `Pastel.Env` |
| [Services](services.md) | Programs that keep running: jobs, signals, systemd |
| [Web APIs and sites](web.md) | Routes, JSON, validation, API keys, JWT, CORS, limits |
| [Databases](database.md) | SQLite, PostgreSQL, MySQL; queries, transactions, migrations |
| [Security](security.md) | Passwords, tokens, signatures; what the server protects against |
| [Deploying](deploy.md) | `.deb`, Docker, systemd, HTTPS behind nginx or Caddy |

## Working with Pastel

| | |
|---|---|
| [Everyday work](workflow.md) | Watching, formatting, libraries and dependencies |
| [Testing](testing.md) | Test suites, asserts, `pastel test`, the test explorer |
| [VS Code](../vscode/README.md) | The extension: designer, code intelligence, tasks |

## Reference

| | |
|---|---|
| [API reference](api/README.md) | Every framework unit, type and routine, from the source comments |
| [Compatibility](compatibility.md) | What stays the same from version to version |
| [Performance](performance.md) | Start-up time, memory, requests per second, drawing speed |

## Examples

| | |
|---|---|
| [dupfinder](../examples/dupfinder/README.md) | A command-line tool that finds duplicate files |
| [weather](../examples/weather/README.md) | A command-line tool that calls a web API |
| [notes-api](../examples/notes-api/README.md) | A web API with a web page, run as a service |
| [contacts](../examples/contacts/README.md) | A desktop address book with SQLite, a list and data binding |
| [notepad](../examples/notepad/README.md) | A desktop text editor: menus, file dialogs, translated into Turkish |
| [components](../examples/components/README.md) | A library of components: a star rating, a component that remembers a form |
| [components-demo](../examples/components-demo/README.md) | An order form that uses that library |
| [salon-core](../examples/salon-core/README.md) | The shared part of a business system: customers, appointments, invoices, sync |
| [salon-desk](../examples/salon-desk/README.md) | Its desktop app: works offline on SQLite, syncs with the server; English and Turkish |
| [salon-api](../examples/salon-api/README.md) | Its server: keeps the data of every computer, answers the sync |

## For contributors

Every new feature comes with its documentation and an example in the same change — a page or a section here, a `.pform` and code example for controls, an entry for commands. The tests check that every control is in the [controls reference](controls.md) and every command in [the command reference](commands.md). See [CONTRIBUTING.md](../CONTRIBUTING.md).
