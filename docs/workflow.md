# Everyday work: watch, format, libraries

| | |
|---|---|
| `pastel run --watch` | Build and run again every time you save |
| `pastel test --watch` | Run the tests again every time you save |
| `pastel fmt` | Format the code in one standard style |
| `pastel new lib` | A library: units that other projects use |
| `[dependencies]` | Use another Pastel project or a package from this one ([packages.md](packages.md)) |

## Watch: `pastel run --watch`

```
$ pastel run --watch
   Compiling hello v0.1.0 (linux, debug)
    Finished debug in 0.14s
     Running build/linux/debug/hello  (saving a file builds and runs it again; Ctrl+C stops)

Hello, world!

      Exited with code 0; waiting for changes (Ctrl+C to stop)

-------- 14:03:12 src/services/greeting.pas changed --------
   Compiling hello v0.1.0 (linux, debug)
...
```

- Every Pascal file of the project is watched, and the units of its dependencies, and `pastel.toml`.
- A program that is still running when you save is asked to stop (SIGTERM, so it can clean up; after 3 seconds it is stopped) and started again with the new code. That makes it handy for servers too.
- After a compile error Pastel waits: fix the code, save, and it continues.
- Arguments for your program go after `--`: `pastel run --watch -- --port 9000`.
- In a desktop app, `.pform` changes appear in the running window by themselves (hot reload); only code changes restart the app.

`pastel test --watch` does the same for the tests, also when a test file changes. With a filter it runs only some of them: `pastel test --watch greeting`.

In VS Code: **Pastel: Run and Watch** and **Pastel: Test and Watch** in the command palette, or the `pastel: watch` task in new projects.

## Format: `pastel fmt`

```sh
pastel fmt                 # every .pas file in src/ and tests/
pastel fmt src/main.pas    # some files or folders
pastel fmt --check         # only list the files that are not formatted (exit code 1): for CI
```

What it does:

- indentation from the structure of the code: two spaces per level; `begin` lines up with its `if`, `for` or `while`; `else` with its `if`; `except` and `finally` with their `try`; members of a class one level in, `private`/`public` at the level of the class; case labels one level in, their statements one more
- reserved words in lower case: `BEGIN` → `begin`, `String` → `string`
- a space around `:=` and after `,`; none before `,` and `;`
- trailing spaces, more than one empty line in a row, tabs at the start of a line

What it leaves alone:

- line breaks: it never joins or splits lines
- comments and strings; `asm` blocks
- the shape of a statement that continues on the next line (it moves as a whole)
- extra spaces used to line things up: `X    := 1;`
- anything between `// fmt: off` and `// fmt: on`

It is careful: a file whose `begin`/`end` do not match is reported and not changed (`src/x.pas: line 40: "begin" from line 12 has no matching "end"`), and after formatting the code is read back and compared with the original; if anything but spacing would change, nothing is written.

Settings, in `pastel.toml`:

```toml
[format]
indent = 2           # spaces per level
keywords = "lower"   # or "keep" to leave Begin/END as written
```

In VS Code, **Format Document** (`Shift+Alt+F`) uses `pastel fmt`, and new projects format on save (`"editor.formatOnSave"` in `.vscode/settings.json`). Code that cannot be formatted while you type is left as it is, with a note in the status bar.

## Libraries: `pastel new lib`

```sh
pastel new lib text-tools
```

creates

```
text-tools/
├── pastel.toml          type = "lib"
├── src/texttools.pas    unit TextTools
└── tests/texttools_test.pas
```

A library has no program of its own:

- `pastel build` compiles every unit in `src/` (to find mistakes)
- `pastel test` runs its tests
- `pastel run` explains that there is nothing to run

## Dependencies

To use the library from another project, add it to that project's `pastel.toml`:

```toml
[dependencies]
text-tools = { path = "../text-tools" }
```

and use its units as usual:

```pascal
uses TextTools;
```

- The path is relative to the project (an absolute path works too).
- The dependency's `src/` folders (and its `[build] unit_paths`) are added to the search path. Its tests are not.
- A dependency's own dependencies are added too; each project once, even if several need it.
- Changes in a dependency are compiled with your project, and `--watch` sees them.
- Any Pastel project can be a dependency, not only libraries; usually it is a library.

Packages from the internet — from the registry or a git repository, with versions and `pastel.lock` — are explained in [packages.md](packages.md).
