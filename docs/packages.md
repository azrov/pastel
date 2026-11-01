# Packages

A **package** is a Pastel library that someone published: serial ports, charts, a barcode reader. You add it with one command, and Pastel fetches it, keeps its exact version in `pastel.lock` and compiles it with your project. It works like Composer for PHP or npm for JavaScript.

```sh
pastel search serial         # what is there
pastel add serial            # fetch it, add it to pastel.toml and pastel.lock
pastel build                 # its units can now be used: uses Serial;
```

| Composer (PHP) | Pastel |
|---|---|
| `composer.json` → `require` | `pastel.toml` → `[dependencies]` |
| `composer.lock` | `pastel.lock` |
| `composer require x` | `pastel add x` |
| `composer update` | `pastel update` |
| `composer install` | nothing to do: `pastel build` fetches what is missing |
| `composer remove x` | `pastel remove x` |
| Packagist | the registry: [github.com/azrov/pastel-packages](https://github.com/azrov/pastel-packages) |
| `vendor/` | one cache for all projects: `~/.cache/pastel` |

## Free Pascal's own packages

Free Pascal comes with about 140 packages, and a Pastel project can use all of them without adding anything: write the unit in `uses` and build. Pastel itself is built on several (`fpjson`, `fphttpclient`, `sqldb`, `process`).

```pascal
uses
  zipper, RegExpr, md5, base64, DOM, XMLRead, fpimage, fpreadpng, Generics.Collections, IniFiles;

var
  R: TRegExpr;
begin
  R := TRegExpr.Create('\d+');
  if R.Exec('order 123') then
    ShowMessage(R.Match[0]);      // 123
  R.Free;
end;
```

Some useful ones:

| Package | Units | For |
|---|---|---|
| `paszlib` | `zipper`, `zstream` | Zip files, compressed streams |
| `regexpr` | `RegExpr` | Regular expressions |
| `hash` | `md5`, `sha1`, `crc` | Checksums |
| `fcl-base` | `base64`, `IniFiles`, `CustApp`, `uriparser` | Everyday helpers |
| `fcl-xml` | `DOM`, `XMLRead`, `XMLWrite`, `XPath` | XML |
| `fcl-image` | `fpimage`, `fpreadpng`, `fpwritejpeg`... | Reading and writing pictures |
| `rtl-generics`, `fcl-stl` | `Generics.Collections`, `gmap`, `ghashmap` | Lists and dictionaries of any type |
| `fcl-db` | `sqldb`, `sqlite3conn`, `pqconnection`, `mysql80conn` | Databases directly (Pastel.Db is easier) |
| `fcl-net`, `fcl-web` | `ssockets`, `fphttpclient`, `fphttpserver` | Network (Pastel.Http and Pastel.Web are easier) |
| `numlib`, `symbolic` | `typ`, `inv`, `symbolic` | Mathematics |

Packages that wrap a C library (`libcurl`, `openssl`, `sdl`, `cairo`, `gtk2`, `libvlc`...) also need that library on the computer the program runs on.

Building for another system (`pastel build --target win64`) needs Free Pascal's packages for that system too; `pastel doctor --install win64` sets them up.

## Adding a package

```sh
pastel add serial               # the newest version: serial = "^1.2.0"
pastel add serial@^1.0          # a range of versions
pastel add serial@1.2.3         # exactly this one
```

`pastel.toml` gets a line:

```toml
[dependencies]
serial = "^1.2.0"
```

and the code uses its units like your own:

```pascal
uses
  Serial;
```

A library's controls and components appear in the designer's toolbox, like the project's own ([components.md](components.md)).

### From a git repository

A package that is not in the registry (your company's own, or one being written) comes straight from its repository:

```sh
pastel add chart --git https://github.com/someone/pastel-chart
pastel add gpio --git https://github.com/azrov/pastel-extras --path gpio --branch main
```

```toml
[dependencies]
chart = { git = "https://github.com/someone/pastel-chart", version = "^0.3" }
gpio = { git = "https://github.com/azrov/pastel-extras", path = "gpio", branch = "main" }
tools = { git = "git@github.com:my-company/tools.git", rev = "a1b2c3d" }
```

| | |
|---|---|
| `git` | The repository: `https://...`, `git@...` (with your SSH key: private repositories work), or a folder |
| `path` | The folder of the package in the repository, when it holds several |
| `version` | A range of its tags (below) |
| `branch` | The newest commit of a branch instead of a version; `pastel update` moves to the newest again |
| `rev` | One commit |

### From a folder on this computer

```sh
pastel add salon-core --path ../salon-core
```

```toml
[dependencies]
salon-core = { path = "../salon-core" }
```

Nothing is fetched or locked: the folder is used as it is, and changes in it are compiled right away ([workflow.md](workflow.md#dependencies)).

## Versions

A package's versions are the tags of its repository: `v1.2.3` (or `1.2.3`). In `pastel.toml` you write which versions are fine — usually with `^`, which allows everything that should not break your code:

| Written | Allows | |
|---|---|---|
| `"^1.2.0"` | `>= 1.2.0`, `< 2.0.0` | the default of `pastel add` |
| `"^0.3.1"` | `>= 0.3.1`, `< 0.4.0` | before 1.0, the second number counts |
| `"~1.2.3"` | `>= 1.2.3`, `< 1.3.0` | only fixes |
| `"1.2.3"` | exactly 1.2.3 | |
| `"1.2"` | any 1.2.x | |
| `">=1.0, <1.5"` | a range | |
| `"*"` | any version | |

Pre-releases (`1.0.0-rc.1`) are only used when the range names one: `"^1.0.0-rc.1"`.

## pastel.lock

`pastel add` and `pastel update` write `pastel.lock` next to `pastel.toml`: the exact version and commit of every package, also of the packages your packages use.

```toml
[package.serial]
version = "1.2.3"
git = "https://github.com/azrov/pastel-extras"
path = "serial"
commit = "4f2a9c1e..."
```

**Put it in git.** Every computer — yours, a colleague's, the CI — then builds with exactly the same code, until someone runs `pastel update`. `pastel build` never changes a locked version; it only adds what is new in `pastel.toml`.

```sh
pastel update               # every package: the newest version pastel.toml allows
pastel update serial        # only this one
pastel deps                 # what is used, and why
```

```
$ pastel deps
greet 0.3.0  https://github.com/azrov/pastel-extras (greet)
  serial 0.2.0  https://github.com/azrov/pastel-extras (serial)
```

When two libraries need versions of a package that cannot both be met (one `^1.0`, the other `^2.0`), Pastel says so and changes nothing; update one of them.

## Where packages are kept

Each repository is fetched once and each version is unpacked once, into a cache for all projects:

| | |
|---|---|
| Linux | `~/.cache/pastel` (or `$XDG_CACHE_HOME/pastel`) |
| Windows | `%LOCALAPPDATA%\pastel\cache` |
| Anywhere | `PASTEL_CACHE=/some/folder` |

With `pastel.lock` and the cache, building needs no network. Deleting the cache is safe: what is needed is fetched again. Packages are fetched with **git**, which must be installed.

## Publishing a package

A package is a Pastel library (`pastel new lib`) in a git repository:

```sh
pastel new lib serial
cd serial
# write src/serial.pas, tests/serial_test.pas, README.md
git init && git add -A && git commit -m "First version"
git tag v0.1.0
git remote add origin https://github.com/you/pastel-serial
git push -u origin main --tags
```

Anyone can use it now with `--git`. To make `pastel add serial` find it, add it to the registry with a pull request to [pastel-packages](https://github.com/azrov/pastel-packages), one entry in `packages.toml`:

```toml
[serial]
git = "https://github.com/you/pastel-serial"
description = "Serial ports: COM on Windows, /dev/ttyUSB0 on Linux"
```

`path = "serial"` when the package is a folder of a bigger repository (like [pastel-extras](https://github.com/azrov/pastel-extras)).

Good packages:

- have a `README.md` with an example, and tests (`pastel test`);
- get a new tag for every release: `v1.2.4` for a fix, `v1.3.0` for something new, `v2.0.0` when code that uses it must change;
- name their units after the package (`Serial`, `SerialPorts`), so they do not meet units of other packages;
- list their own packages in their `pastel.toml` like any project.

### Another registry

A company can keep its own list: `PASTEL_REGISTRY` is a git repository (or a folder) with a `packages.toml`.

```sh
export PASTEL_REGISTRY=https://git.my-company.com/pastel-packages
```
