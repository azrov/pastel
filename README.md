# Pastel

**A modern cross-platform app framework and toolchain for Object Pascal.**

Write your app once in Object Pascal and run it on desktop, mobile, server and Raspberry Pi. Pastel is built on top of the [Free Pascal](https://www.freepascal.org/) compiler and brings a modern developer experience: a simple command-line tool, clear project conventions, forms with hot reload, and a UI drawn by Pastel itself so it looks the same everywhere.

> ⚠️ **Status: early development.** Working today: the `pastel` command-line tool (console apps for Linux, Windows and Raspberry Pi) and a first version of the UI framework (windows, forms from `.pform` files, buttons, edits, labels, flexbox-style layout, hot reload) on Linux and Windows. Ideas, feedback and contributions are very welcome.

## Why Pastel?

Object Pascal is a fast, readable, compiled language with a loyal community. But today you have two choices:

- **Delphi** is powerful and modern, but commercial.
- **Lazarus** is free and open source, but its IDE and workflow feel dated, and mobile support is limited.

Pastel aims to be the missing piece: free, open source, modern, and easy to set up.

## Goals

- **One codebase, many platforms:** Linux, Windows, macOS, Android, iOS and Raspberry Pi
- **Any kind of app:** GUI apps, terminal tools, servers and headless device programs
- **Easy setup:** `pastel doctor` finds and installs missing compilers and SDKs
- **Modern editor experience:** VS Code extension with code completion, live preview and hot reload
- **Clear conventions:** every Pastel project has the same structure, so you always know where things are
- **Familiar for Pascal developers:** components, properties and events, the way Delphi developers already think

## Try it today

You need [Free Pascal](https://www.freepascal.org/) 3.2 or newer (on Linux Mint / Ubuntu: `sudo apt install fpc`). GUI apps also use SDL2 and FreeType, which most Linux desktops already have (`sudo apt install libsdl2-2.0-0 libfreetype6`). On Windows, put `SDL2.dll` and `freetype.dll` next to your program.

```sh
git clone https://github.com/<you>/pastel.git
cd pastel
./build.sh            # Windows: build.bat
```

This creates `bin/pastel`. Put it on your `PATH` (for example `ln -s "$PWD/bin/pastel" ~/.local/bin/pastel`), then create a desktop app:

```sh
pastel new app hello
cd hello
pastel run          # opens the window; edit src/forms/Home.pform while it runs
```

Or a console program:

```sh
pastel new console hello
cd hello
pastel run                        # build and run on this computer
pastel run -- Ali                 # pass arguments to your program
pastel build --release            # optimized build
pastel build --target windows     # a Windows .exe, built on Linux
pastel build --target rpi         # a Raspberry Pi program
pastel build --all --release      # every platform listed in pastel.toml
pastel test                       # run the tests in tests/ (see docs/testing.md)
pastel doctor                     # what can this computer build?
```

Build output goes to `build/<platform>/<debug|release>/`. Compiler errors point to the file and line, relative to your project.

Building for another platform needs the Free Pascal cross-compiler for it. `pastel doctor` tells you what is missing; today [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe) is the easiest way to install cross-compilers. Automatic installation is planned.

| Command | What it does |
|---|---|
| `pastel new app <name>` | Create a desktop app with a form |
| `pastel new console <name>` | Create a console project |
| `pastel build` | Compile (`-t <platform>`, `-r` release, `--all`, `-v` verbose) |
| `pastel run` | Compile and run on this computer |
| `pastel test [filter]` | Run the tests in `tests/` |
| `pastel clean` | Remove the `build/` folder |
| `pastel targets` | List platforms and short names (`rpi`, `win`, ...) |
| `pastel doctor` | Check the compiler and which platforms are ready |

## VS Code

The `vscode/` folder contains the Pastel extension for Visual Studio Code. Build it with `cd vscode && npm install && npm run compile && npm run package`, then install the `.vsix` file with *Extensions: Install from VSIX…*. It gives you:

- a **Pastel Run** button and Run / Build / Build for Platform commands, with errors in the Problems panel
- a **form designer** beside the editor: click to select, edit properties, drag to move, drag in new controls; updated as you type
- completion, hover help and checks while typing in `.pform` files
- `Ctrl+click` from `OnClick = SendClick` to the code, and a quick fix that creates missing event handlers
- a Pastel panel in the activity bar, Pascal outline and go to definition (into the framework too)
- Delphi keys: F9 run, Ctrl+F9 build, F12 form/code, Ctrl+Shift+Up/Down declaration/body

New projects come with `.vscode` settings: `Ctrl+Shift+B` builds, `F5` debugs with gdb (needs the C/C++ extension).

## How a GUI app looks

```
pastel new app myapp
cd myapp
pastel run
pastel build android
pastel build rpi
```

A form is described in a readable `.pform` file (see [docs/forms.md](docs/forms.md) for all controls and properties):

```
object HomeForm: THomeForm
  Title = 'Hello'
  object Card: TCard
    object NameEdit: TEdit
      Placeholder = 'Your name'
    end
    object SendButton: TButton
      Text = 'Send'
      OnClick = SendClick
    end
  end
  object Greeting: TLabel
  end
end
```

And the logic stays in plain Object Pascal:

```pascal
procedure THomeForm.SendClick(Sender: TObject);
begin
  Greeting.Text := 'Hello, ' + NameEdit.Text;
end;
```

Pastel generates a base class with a field for every control in the `.pform` file, so the code can use `NameEdit` and `Greeting` directly. The generated code never mixes with yours.

## Project structure

```
myapp/
├── pastel.toml        project settings
├── src/
│   ├── main.pas       entry point
│   ├── forms/         screens: Home.pform + Home.pas
│   ├── models/        data classes
│   └── services/      business logic, HTTP, database
├── assets/            images, fonts, translations
├── platforms/         platform-specific settings and icons
├── tests/
└── build/             build output (not committed)
```

## Architecture

| Layer | Written in |
|---|---|
| Your app (`.pas` + `.pform`) | Object Pascal |
| Controls, layout, `.pform` loading, hot reload (`framework/`) | Object Pascal |
| Drawing: anti-aliased shapes and text into a pixel buffer | Object Pascal |
| Glyph rendering ([FreeType](https://freetype.org/)), windows and input ([SDL2](https://libsdl.org/)) | Existing C libraries, loaded at run time |
| Compiler | [Free Pascal](https://www.freepascal.org/), unmodified |

Today Pastel draws everything in software, which is plenty for typical apps. The drawing calls are kept small so a GPU backend (such as [Skia](https://skia.org/)) can be added later, and SDL2 can be swapped for SDL3 once Linux distributions ship it.

## Roadmap

Pastel grows in this order: console programs (0.2), Linux services with web APIs and databases (0.3), code intelligence in VS Code (0.4), then desktop apps (0.5–0.6), up to a stable 1.0. See [ROADMAP.md](ROADMAP.md) for the full list.

## Contributing

Pastel is in its earliest stage, which is the best time to shape it. Open an issue to share ideas, report problems or discuss the design.

The `pastel` tool itself is written in Object Pascal (`cli/`). Run the tests with `./build.sh test`.

## License

[MIT](LICENSE)
