# Getting started

From nothing to a program you can hand out, in about fifteen minutes. The
commands are for Linux (Mint, Ubuntu, Debian); Windows differences are noted.

## 1. Install Free Pascal

Pastel uses the Free Pascal compiler (3.2 or newer) and does not change it.

- **Linux Mint / Ubuntu / Debian:** `sudo apt install fpc`
- **Windows:** the installer from [freepascal.org](https://www.freepascal.org/download.html)
  (choose the 64-bit Windows version), and say yes to adding it to `PATH`.

Check: `fpc -iV` prints `3.2.2` (or newer).

## 2. Build the `pastel` tool

```sh
cd pastel             # the folder with build.sh
./build.sh            # Windows: build.bat
```

This makes `bin/pastel` (`bin\pastel.exe`). Put it on your `PATH` so you can
type `pastel` anywhere:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/bin/pastel" ~/.local/bin/pastel     # log out and in once if "pastel" is not found
```

On Windows: *Settings → System → About → Advanced system settings →
Environment Variables*, and add the `bin` folder to `Path`.

Then:

```sh
pastel doctor
```

It checks the compiler, the libraries for desktop apps and HTTPS, and which
platforms this computer can build for. Every ✗ comes with the command that
fixes it.

## 3. Install the VS Code extension

In VS Code: *Extensions* (Ctrl+Shift+X) → `…` menu → **Install from VSIX…** →
`vscode/pastel-vscode-<version>.vsix`.

For debugging (F5), VS Code also needs Microsoft's **C/C++** extension; Pastel
offers to install it the first time you press F5.

## 4. Your first program

```sh
pastel new console hello
code hello
```

(or in VS Code: **Pastel: New Project** from the command palette, Ctrl+Shift+P.)

The project looks like this; every Pastel project has the same layout:

```
hello/
├── pastel.toml              name, version, settings (docs/project.md)
├── src/main.pas             the program starts here
├── src/services/greeting.pas  your own units: any folder under src/ is found
└── tests/greeting_test.pas  tests
```

Press **F9** (or click **▶ Pastel Run** in the status bar). The program is
compiled and runs in the terminal panel:

```
Hello, world! This is hello, built with Pastel.
```

It already understands arguments: `pastel run -- --help`, `pastel run -- Ali`,
`pastel run -- --shout Ayşe`.

## 5. Change it, and see it at once

Run **Pastel: Run and Watch** (or `pastel run --watch` in a terminal). Now
every time you save, the program is compiled and started again. Change the
greeting in `src/services/greeting.pas`, press Ctrl+S, and look at the
terminal.

Mistakes show up in the **Problems** panel with the line; click to jump
there.

When you save a `.pas` file it is also formatted (indentation, spaces). If
you prefer to do that yourself, remove `"editor.formatOnSave"` from
`.vscode/settings.json`; `pastel fmt` formats everything at once.

## 6. Test

Open the **Testing** view (the flask icon on the left). It lists the tests
in `tests/`. Click ▶ to run them; a failing test is marked at the line of the
assert that failed. In a terminal: `pastel test`.

A test is a published method of a `TTestSuite` class:

```pascal
procedure TGreetingTests.GreetsByName;
begin
  AssertStartsWith('Hello, Ali!', MakeGreeting('Ali'));
end;
```

More in [testing.md](testing.md).

## 7. Debug

Click left of a line number in `src/main.pas` to set a breakpoint, then press
**F5**. Pastel builds the program and starts it in the debugger; it stops at
the breakpoint. Hover over a variable to see its value (strings are shown as
text, `'Ayşe'`), and use the buttons at the top to step through the code.

No `launch.json` is needed. To give your program arguments while
debugging, add `"args": ["Ali"]` to the configuration in
`.vscode/launch.json`.

## 8. Release

```sh
pastel package
```

makes `dist/hello-0.1.0-linux.tar.gz`: an optimized build with your README,
ready to hand out (and a `.sha256` file to check the download). Change
`version` in `pastel.toml` for the next release; `hello --version` follows.

For Windows and the Raspberry Pi:

```sh
pastel package --target windows      # dist/hello-0.1.0-windows.zip
pastel package --target rpi          # for Raspberry Pi OS (64-bit)
```

Building for another platform needs the Free Pascal cross-compiler for it.
`pastel doctor` shows which ones are ready; today
[fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe) is the
easiest way to add them.

## 9. A desktop app

```sh
pastel new app notes
cd notes
pastel run
```

A window opens. Open `src/forms/Home.pform` in VS Code: the form designer
appears beside the editor. Change a text, drag a button: the running window
follows at once. The code for the buttons is in `src/forms/Home.pas`; F12
switches between form and code. See [forms.md](forms.md).

## Where next

| | |
|---|---|
| [guide-cli.md](guide-cli.md) | Writing a command-line tool, step by step |
| [console.md](console.md) | Arguments, colors, tables, questions |
| [data.md](data.md) | JSON, settings, logging |
| [system.md](system.md) | Files, other programs, HTTP |
| [workflow.md](workflow.md) | Watch, format, libraries, dependencies |
| [project.md](project.md) | Everything in `pastel.toml`; packages |
| [services.md](services.md) | Programs that keep running: jobs, systemd |
| [web.md](web.md) | Web APIs and sites |
| [testing.md](testing.md) | Tests |
| [forms.md](forms.md) | Desktop apps: forms and controls |
| `examples/` | Complete programs: `dupfinder` (files), `weather` (calls a web API), `notes-api` (is a web API) |
