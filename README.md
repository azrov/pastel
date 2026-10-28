# Pastel

**A modern cross-platform app framework and toolchain for Object Pascal.**

Write your app once in Object Pascal and run it on desktop, mobile, server and Raspberry Pi. Pastel is built on top of the [Free Pascal](https://www.freepascal.org/) compiler and brings a modern developer experience: a simple command-line tool, a VS Code extension, clear project conventions and a GPU-rendered UI that looks the same everywhere.

> ⚠️ **Status: early development.** Pastel is not usable yet. Ideas, feedback and contributions are very welcome.

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

## A first look (planned)

```
pastel new app myapp
cd myapp
pastel run
pastel build android
pastel build rpi
```

A form is described in a readable `.pform` file:

```
object MainForm: TMainForm
  Title = 'Hello'
  object Body: TColumn
    Padding = 16
    Gap = 12
    object NameEdit: TEdit
    end
    object SendButton: TButton
      Text = 'Send'
      OnClick = SendClick
    end
  end
end
```

And the logic stays in plain Object Pascal:

```pascal
procedure TMainForm.SendClick(Sender: TObject);
begin
  ShowMessage('Hello, ' + NameEdit.Text);
end;
```

## Project structure

```
myapp/
├── pastel.toml        project settings
├── src/
│   ├── main.pas       entry point
│   ├── forms/         screens (.pform + .pas)
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
| Component library and shared services | Object Pascal |
| UI core: layout, styling, animation | Object Pascal |
| Rendering ([Skia](https://skia.org/)) and platform layer ([SDL3](https://libsdl.org/)) | Existing C libraries |
| Compiler | [Free Pascal](https://www.freepascal.org/), unmodified |

## Roadmap

1. `pastel` CLI: `new`, `run`, `build` for console apps on Linux and Windows
2. First window: Skia + SDL3 rendering, `.pform` loading and hot reload
3. Core components and flexbox-style layout
4. VS Code extension: language server, build commands, live preview
5. Android support and packaging
6. Raspberry Pi and macOS support
7. Visual drag-and-drop designer

## Contributing

Pastel is in its earliest stage, which is the best time to shape it. Open an issue to share ideas, report problems or discuss the design.

## License

[MIT](LICENSE)
