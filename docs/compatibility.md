# Compatibility: what stays the same

Pastel is heading for 1.0. From 1.0 on, a project that builds with Pastel 1.0 builds with every 1.x version. Before 1.0, changes are still possible, but they are made on purpose, listed in the changelog, and `pastel upgrade` carries projects along where it can.

## What is covered

| | Stays compatible | Checked by |
|---|---|---|
| **Framework API** | Every public declaration in [docs/api/stable.txt](api/stable.txt): units, types, routines, methods, properties, constants. New things may be added; nothing listed is removed or changed. | `tests/run.sh` fails when a line of `stable.txt` is gone |
| **`pastel.toml`** | The keys in [project.md](project.md). Unknown keys are reported, never silently ignored. | The project file tests |
| **`.pform` files** | The syntax in [forms.md](forms.md#the-pform-format) and the published properties of the controls (they are part of the API above). | The `.pform` reader tests |
| **`pastel` commands** | Commands and options in `pastel help`; exit codes: 0 success, 1 failure, 2 wrong usage. `--json` output only gets new fields. | The end-to-end tests |
| **`assets/`** | `icon.png`, `font.ttf`, `font-bold.ttf`, `theme.toml`, `lang/*.json` | The end-to-end tests |

## What is not covered

- Declarations whose comment starts with **Internal** and the units marked *Internal unit* (`Pastel.Forms`, `Pastel.PForm`, `Pastel.NativeDialogs`, and the platform units `Pastel.SDL2`, `Pastel.FreeType`, `Pastel.Startup`, `Pastel.ErrorExit`). They exist for Pastel itself and the code it generates. They are left out of the API reference.
- The code Pastel generates (`build/.../gen/`).
- How things look: the default colors, sizes and fonts of the controls may improve. Set the look you depend on in `assets/theme.toml`.
- Messages of the `pastel` tool meant for people (not `--json`).

## For Pastel's developers

```sh
cd vscode
npm run apidoc                 # docs/api/*.md and api.txt from framework/src
npm run apidoc -- --freeze     # docs/api/stable.txt := what is public now
```

Run `--freeze` only when a change to the stable API is meant (before 1.0, or for a new major version). Mark helpers that must be public for technical reasons with an `{ Internal: ... }` comment.

A project records the Pastel version it is made for in `pastel.toml` (`pastel = "0.7"`); see [Upgrading a project](project.md#upgrading-a-project).
