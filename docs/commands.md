# The `pastel` command

Everything Pastel does from the terminal, with examples. `pastel help` shows the short list; every command works in any folder of a project (it finds `pastel.toml`). Exit codes: `0` worked, `1` failed (compile errors, failing tests...), `2` wrong usage.

**Projects:** [new](#pastel-new) · [upgrade](#pastel-upgrade) · [clean](#pastel-clean)
**Packages:** [add](#pastel-add) · [remove](#pastel-remove) · [update](#pastel-update) · [search](#pastel-search) · [deps](#pastel-deps)
**Building and running:** [build](#pastel-build) · [run](#pastel-run) · [test](#pastel-test) · [fmt](#pastel-fmt) · [check](#pastel-check)
**Shipping:** [package](#pastel-package) · [targets](#pastel-targets) · [doctor](#pastel-doctor)
**Apps:** [lang](#pastel-lang) · [preview](#pastel-preview) · [schema](#pastel-schema)
**Services:** [migrate](#pastel-migrate)
**Other:** [version](#pastel-version) · [help](#pastel-help)

## pastel new

Creates a project, or adds a form, a control or a model (a table) to it.

```sh
pastel new console hello        # a command-line program
pastel new app notes            # a desktop app with a window (src/forms/Home.pform)
pastel new service watcher      # a program that keeps running (systemd)
pastel new api shop             # a web API with a database, models, migrations and tests
pastel new lib text-tools       # units for other projects (no program of its own)

pastel new form Settings        # in an app: src/forms/Settings.pform/.pas, added to main.pas
pastel new control StarRating   # in an app or lib: src/controls/starrating.pas
pastel new model Customer name:string! email:string age:integer
                                # a table: its migration, src/models/customers.pas and tests
```

Forms exist only in app projects: `pastel new form` in a console program, a service or an API stops and says so — a window there would never be shown. Make the window part as an app that uses the project (`pastel add <project> --path ../<project>`). Controls (`pastel new control`) belong to apps and libraries.

In VS Code, **Pastel: New Project…** does the same as `pastel new` with a wizard: the kind of project, its name, its folder and its platforms.

The kinds are explained in [getting-started.md](getting-started.md); forms in [forms.md](forms.md), controls in [components.md](components.md), models in [database.md](database.md#models-where-the-sql-lives).

## pastel build

Compiles the project into `build/<platform>/<debug|release>/`.

```sh
pastel build                     # debug build for this computer
pastel build --release           # optimized, without debug information (-r)
pastel build --target windows    # for another platform (-t); see pastel targets
pastel build --all               # every platform in [targets] platforms
pastel build -v                  # show the compiler's command and every message
```

Before compiling, `.pform` files are checked and turned into code, and `assets/` is compiled in (release builds). Compiler errors show the file and line, relative to the project.

## pastel run

Builds and starts the program on this computer.

```sh
pastel run
pastel run -- --verbose input.txt      # arguments after -- go to the program
pastel run --watch                     # build and start again on every saved file
pastel run --release
```

While a desktop app runs, saving a `.pform` file updates the window at once (hot reload).

## pastel test

Runs the tests in `tests/` (units with `TTestSuite` classes, see [testing.md](testing.md)).

```sh
pastel test                  # all
pastel test money            # only tests whose name contains "money"
pastel test --watch          # again on every saved file
pastel test --json           # results as JSON (for editors and CI)
```

## pastel fmt

Formats Pascal code in one standard style ([workflow.md](workflow.md#format-pastel-fmt)).

```sh
pastel fmt                   # every .pas file of the project
pastel fmt src/forms         # only these files or folders
pastel fmt --check           # only report; exit code 1 when something is not formatted (CI)
pastel fmt --stdin < a.pas   # read code, write it formatted (editors)
```

## pastel check

Finds mistakes without a full build: in `.pform` files (unknown controls and properties, wrong values, missing event handlers), or in a `.pas` file (compiler errors).

```sh
pastel check                                  # every .pform of the project
pastel check src/forms/Home.pform
pastel check src/forms/Home.pas --json        # compiler errors as JSON
cat Home.pform | pastel check src/forms/Home.pform --stdin --json    # unsaved text (editors)
```

## pastel package

A release build, packed to hand out ([deploy.md](deploy.md), [guide-desktop.md](guide-desktop.md#12-shipping)).

```sh
pastel package                          # dist/<name>-<version>-linux.tar.gz (Windows: .zip)
pastel package --target windows         # a .zip with the .exe and its DLLs
pastel package --all                    # every platform in pastel.toml
pastel package deb                      # a Debian/Ubuntu package (service: with systemd unit; app: menu entry)
pastel package docker                   # a container image (services)
pastel package appimage                 # one file that runs on most Linux systems (apps)
pastel package installer --target windows   # a Windows installer (needs makensis)
pastel package --no-build               # pack what was built already
```

Next to every archive is a `.sha256` file. What goes in: the program, `README`, `LICENSE` and `[package] include` from `pastel.toml`.

## pastel targets

Lists the platforms Pastel can build for and their short names (`windows`, `rpi`, `linux-arm64`...).

```sh
pastel targets
```

## pastel doctor

Checks the setup: the compiler, the libraries apps and HTTPS need, and which platforms can be built.

```sh
pastel doctor
pastel doctor --install windows    # set up building for Windows on Linux: Free Pascal's units
                                   # for Windows (from fpc-source) and SDL2.dll / freetype.dll
```

## pastel lang

Collects the texts of an app for translation into `assets/lang/<code>.json` ([guide-desktop.md](guide-desktop.md#10-look-and-feel-languages)).

```sh
pastel lang add tr       # a new language: assets/lang/tr.json with every text
pastel lang              # update every language file; tells what is not translated yet
pastel lang list         # the texts that would be translated
```

## pastel migrate

Runs database migrations from `database/migrations/` ([database.md](database.md)).

```sh
pastel migrate                          # run what did not run yet
pastel migrate status                   # applied / pending
pastel migrate new add_customers        # a new file: database/migrations/002_add_customers.sql
pastel migrate --database postgres://user:pw@localhost/shop
```

## pastel add

Adds a package to `[dependencies]` and `pastel.lock`, and fetches it ([packages.md](packages.md)).

```sh
pastel add serial                                    # from the registry, the newest version
pastel add serial@^1.0                               # a range of versions
pastel add chart --git https://github.com/someone/pastel-chart
pastel add gpio --git https://github.com/azrov/pastel-extras --path gpio --branch main
pastel add salon-core --path ../salon-core           # a folder on this computer
```

## pastel remove

Removes packages from `pastel.toml`, and from `pastel.lock` what nothing needs any more.

```sh
pastel remove serial
```

## pastel update

Moves packages to the newest version `pastel.toml` allows and writes `pastel.lock`.

```sh
pastel update               # all
pastel update serial        # one
```

## pastel search

Looks for packages in the registry, by name and description.

```sh
pastel search               # every package
pastel search barcode
```

## pastel deps

The dependencies, theirs, and the versions used.

```sh
pastel deps
pastel deps --json          # for editors: name, version, folder
```

## pastel upgrade

Brings a project made with an older Pastel up to date ([project.md](project.md#upgrading-a-project)).

```sh
pastel upgrade --check     # only tell what would change (exit code 1 if anything)
pastel upgrade
```

## pastel clean

Deletes `build/`.

```sh
pastel clean
```

## pastel preview

Draws a form into a PNG without running the app — for documentation, reviews, or a quick look.

```sh
pastel preview src/forms/Home.pform -o home.png
pastel preview src/forms/Home.pform -o home-dark.png --dark
```

## pastel schema

Prints every control and component with its properties as JSON. Editors (the VS Code designer) use it; with controls of the project or its libraries, it includes them.

```sh
pastel schema > controls.json
```

## pastel version

```sh
pastel version        # pastel 1.0.0
```

## pastel help

```sh
pastel help           # also: pastel --help
```
