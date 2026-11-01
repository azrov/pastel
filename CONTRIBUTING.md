# Contributing to Pastel

Thank you for helping! Pastel is a Delphi-like way to build console programs, services and desktop apps in Object Pascal, with VS Code and Free Pascal. Bug reports, ideas, documentation fixes and code are all welcome.

## Asking and reporting

- **A bug:** open an issue with the *Bug* form. The output of `pastel version` and `pastel doctor`, and the smallest project that shows the problem, help most.
- **An idea:** open an issue with the *Idea* form and describe what you want to build, not only the feature. [ROADMAP.md](ROADMAP.md) shows what is planned.
- **A security problem:** do not open an issue; see [SECURITY.md](SECURITY.md).

## Getting the code running

You need Free Pascal 3.2.2 (`sudo apt install fpc fpc-source`), Node.js 20 for the VS Code extension, and for the desktop tests SDL2 and FreeType (`sudo apt install libsdl2-2.0-0 libfreetype6`).

```sh
./build.sh                       # bin/pastel
(cd vscode && npm ci && npm run compile)
(cd tools/site && npm ci)        # the documentation website and its link check
sh build.sh test                 # everything: unit, framework, example and end-to-end tests
```

The database tests also run against PostgreSQL and MySQL/MariaDB when `PASTEL_TEST_POSTGRES_URL` and `PASTEL_TEST_MYSQL_URL` are set (see `.github/workflows/ci.yml`). The VS Code extension has its own tests: `npm test` and `npm run test:integration -- <a new app project>` in `vscode/`.

## How the repository is organized

| Folder | What is in it |
|---|---|
| `cli/` | The `pastel` tool: commands, builder, code generation for forms, packaging |
| `framework/src/` | The units programs use (`Pastel.*`); `framework/tests/` tests them |
| `vscode/` | The VS Code extension: designer, Pascal code intelligence, tasks |
| `examples/` | Complete programs; each has tests and is built in CI |
| `docs/` | The guides and the API reference (`docs/api` is generated) |
| `tests/` | Unit tests of the tool, `run.sh` (end-to-end), `perf.sh` (performance) |
| `tools/` | The documentation website and the release scripts |

## Making a change

1. **Discuss bigger changes first** in an issue, so no work is lost.
2. **Write a test** for what you fix or add: a framework test (`framework/tests/tests/`), an end-to-end check (`tests/run.sh`) or a UI script (see [docs/forms.md](docs/forms.md#testing-a-form-without-a-window)).
3. **Keep the style:** `bin/pastel fmt cli framework tests examples` formats the Pascal code; the tests check it.
4. **Document it, with an example, in the same change.** Pastel's docs are meant to answer every "how do I...?" with something to copy:
   - a comment above every public declaration (it becomes the API reference: `npm run apidoc` in `vscode/`);
   - a new control or component: a section `### TName` in [docs/controls.md](docs/controls.md) with a `.pform` and a code example;
   - a new command or option: [docs/commands.md](docs/commands.md);
   - a new feature: a section in the topic's page ([docs/README.md](docs/README.md) lists them), and in the guide when it changes how a program is built;
   - a new example program: a `README.md` and a line in [docs/README.md](docs/README.md#examples);
   - a line in [CHANGELOG.md](CHANGELOG.md).

   `tests/docs-coverage.sh` fails when a control, a command or an example has no documentation, and the website build fails on broken links.
5. **Keep compatibility:** from 1.0 on, nothing in `docs/api/stable.txt` may be removed or changed in 1.x; add new things instead. See [docs/compatibility.md](docs/compatibility.md).
6. Run `sh build.sh test` and open a pull request.

## Writing style

Pastel's documentation, messages and comments use plain, short English that non-native speakers read easily: active sentences, common words, an example before an explanation. Error messages say what went wrong and what to do (`hint: ...`).

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).

## Releasing

For maintainers. A release is made from a tag; the workflows do the rest.

1. Set the version: `PastelVersion` in `cli/src/pastel.project.pas`, `version` in `vscode/package.json`, and a section `## <version>` at the top of [CHANGELOG.md](CHANGELOG.md) (and of `vscode/CHANGELOG.md`).
2. `sh build.sh test` and `sh tests/perf.sh` pass; `npm run apidoc -- --freeze` in `vscode/` only if the stable API is meant to change (never within 1.x).
3. `git tag v1.2.3 && git push --tags`. The *Release* workflow builds Linux (x64, ARM64) and Windows downloads, the `.vsix` and `install.sh` and publishes them with the notes from the changelog (tags with a `-`, like `v1.2.3-rc.1`, become pre-releases). For final versions, *Publish the VS Code extension* uploads it to the Marketplace and Open VSX.
4. The *Website* workflow publishes the documentation from `main`.

Once, for a new repository: enable GitHub Pages (source: GitHub Actions), and add the secrets `VSCE_PAT` (a token of the `pastel` publisher on the Visual Studio Marketplace) and `OVSX_PAT` (a token from open-vsx.org).
