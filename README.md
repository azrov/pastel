# Pastel

**A modern cross-platform app framework and toolchain for Object Pascal.**

Write your app once in Object Pascal and run it on the desktop, on servers and on Raspberry Pi — and, next, on Android phones. Pastel is built on top of the [Free Pascal](https://www.freepascal.org/) compiler and brings a modern developer experience: a simple command-line tool, clear project conventions, forms with hot reload, and a UI drawn by Pastel itself so it looks the same everywhere.

> **Status: 1.0 release candidate.** Working today: the `pastel` command-line tool and libraries for console programs on Linux, Windows and Raspberry Pi (arguments, files, HTTP, JSON, settings, logging, tests, packaging), Linux services and REST APIs (web server, JWT and API keys, SQLite/PostgreSQL/MySQL with migrations, background workers, `.deb` and Docker packages), and code intelligence in VS Code (completion, hover, parameter hints, references, rename, compiler errors while typing) and desktop apps on Linux and Windows (forms from `.pform` files designed in VS Code, about 30 controls including grids and trees, your own controls in the designer, data binding, menus and shortcuts, dialogs, several windows, translations, themes, high-DPI, hot reload, scripted UI tests; Windows installer, AppImage and `.deb` packages). Ideas, feedback and contributions are very welcome.

## Why Pastel?

Object Pascal is a fast, readable, compiled language with a loyal community. But today you have two choices:

- **Delphi** is powerful and modern, but commercial.
- **Lazarus** is free and open source, but its IDE and workflow feel dated, and mobile support is limited.

Pastel aims to be the missing piece: free, open source, modern, and easy to set up.

## License

[MIT](LICENSE)
