# The project file: `pastel.toml`

Every Pastel project has a `pastel.toml` in its main folder. `pastel` finds it from any sub-folder, so commands work anywhere in the project.

```toml
[project]
name = "inventory"          # letters, digits, - and _; also the program's file name
version = "1.2.0"           # AppVersion in the program, part of package names
type = "console"            # console, app (desktop window), lib (units for other projects)

[build]
main = "src/main.pas"       # the program (not used by lib projects)
mode = "objfpc"             # objfpc or delphi
defines = ["USE_CACHE"]     # {$IFDEF USE_CACHE} in every build
unit_paths = ["../shared"]  # more folders with units (src/ and its sub-folders are always searched)

[profile.debug]             # only debug builds (pastel build, pastel run)
defines = ["VERBOSE_SQL"]

[profile.release]           # only release builds (--release, pastel package)
defines = ["SHIPPED"]
options = ["-O3"]           # extra Free Pascal options, for special cases

[profile.test]              # pastel test (which also gets the debug settings)
defines = ["FAKE_CLOCK"]

[targets]
platforms = ["linux", "windows", "rpi"]   # pastel build --all, pastel package --all

[dependencies]
text-tools = { path = "../text-tools" }   # another Pastel project, see workflow.md

[package]
include = ["config.example.toml", "assets"]   # put into every package
[package.windows]
include = ["libs/windows/*.dll"]              # only into the Windows package

[format]
indent = 2                  # pastel fmt: spaces per level
keywords = "lower"          # or "keep"
```

Only `[project] name` is required. Mistakes are reported with the line: `pastel.toml: line 7: invalid value "yes" (strings need quotes)`.

## Defines everywhere

Every build also has:

| Define | When |
|---|---|
| `PASTEL` | always |
| `PASTEL_DEBUG` | debug and test builds |
| `PASTEL_RELEASE` | release builds |
| `PASTEL_TEST` | `pastel test` |

and the unit `AppInfo` with `AppName`, `AppVersion`, `AppProfile` (`debug`, `release` or `test`) and `AppTarget`.

## Debug and release builds

| | Debug (default) | Release (`--release`) |
|---|---|---|
| Speed | not optimized | optimized (`-O2`) |
| Checks | range, overflow and I/O checks, assertions | off |
| Debug information | DWARF 3, readable in gdb | none, smaller program |
| `.pform` files | read at run time (hot reload) | built into the program |
| Windows apps | with a console window | without |
| Output | `build/<platform>/debug/` | `build/<platform>/release/` |

## Packages: `pastel package`

```sh
pastel package                    # dist/inventory-1.2.0-linux.tar.gz
pastel package --target windows   # dist/inventory-1.2.0-windows.zip
pastel package --all              # every platform in [targets] platforms
```

A package is a release build in an archive: `.zip` for Windows, `.tar.gz` for the others. It contains one folder, `inventory-1.2.0-linux/`, with

- the program (executable on Linux and macOS),
- `README`, `LICENSE` and `CHANGELOG` files from the project folder,
- what `[package] include` and `[package.<platform>] include` list: files, folders (with their contents) and patterns like `docs/*.md`, relative to the project.

Next to every archive is a `.sha256` file, so receivers can check it: `sha256sum -c inventory-1.2.0-linux.tar.gz.sha256`.

For servers there are also `pastel package deb` (a Debian/Ubuntu package with the systemd unit) and `pastel package docker` (a container image): [deploy.md](deploy.md).

Desktop apps need SDL2 and FreeType on the computer that runs them. On Linux they come with the system (`sudo apt install libsdl2-2.0-0 libfreetype6`); for Windows, put `SDL2.dll` and `freetype.dll` in the project (for example `libs/windows/`) and list them in `[package.windows] include`.
