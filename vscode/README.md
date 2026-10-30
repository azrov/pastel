# Pastel for Visual Studio Code

Build cross-platform apps in Object Pascal with Pastel. This extension connects VS Code to the `pastel` command-line tool.

## Requirements

- The `pastel` program on your `PATH` (or set `pastel.path`). Check your setup with **Pastel: Check Setup**.
- [Free Pascal](https://www.freepascal.org/) 3.2 or newer.
- Recommended: **C/C++** (`ms-vscode.cpptools`) for debugging with F5.

## Features

**Run and build.** Press the **Pastel Run** button in the status bar, or use the commands *Pastel: Run*, *Build*, *Build Release*, *Build for Platform…* and *Clean*. `Ctrl+Shift+B` builds. Errors from your Pascal code and from `.pform` files appear in the Problems panel; click one to jump to the line.

**Form designer.** Open a `.pform` file and press the designer button in the editor title. The form is drawn beside the editor and updates as you type. Click a control to select it and edit its properties; drag controls to move them; drag new ones in from the toolbox; press `Delete` to remove one. Selection follows the cursor in the editor and the other way round, and every change is a normal text edit, so `Ctrl+Z` undoes it.

**Writing forms.** In `.pform` files you get:

- completion for control types (`object SaveButton: T…`), properties, and their values (`Align = Center`, `Style = Secondary`, event handler names from the form's `.pas` file)
- hover help for properties and controls
- mistakes underlined while you type, like an unknown property or a missing event handler
- a quick fix that adds a missing event handler to the form's code, ready to fill in
- `Ctrl+click` on an event handler (`OnClick = SaveClick`) to open its code
- the outline of the form in the Outline view, and snippets: `button`, `edit`, `label`, `row`, `column`, `card`

**New projects.** *Pastel: New Project…* creates an app, console, service, API or library project and opens it. New projects come with VS Code settings, so `Ctrl+Shift+B` builds and `F5` starts debugging.

**Pastel panel.** The palette icon in the activity bar opens the Pastel panel: Run and Build buttons, your forms (click one to open the designer; expand it for its `.pform` and `.pas` files), the other source files and the project settings.

**Web APIs and services.** In service and API projects the Pastel panel lists the routes (click one to open its code), the jobs and the database migrations, with *Run Migrations*, *Migration Status* and *New Migration…*. Above every route in the code is **▶ Send**: it sends a request to the running server (start it with F9), asks for path parameters and a JSON body, adds the API key from `config.toml`, and shows the answer in the *Pastel Requests* output. The same is in the panel (the ▶ next to a route) and as *Pastel: Send Request*.

**Pascal code.** `.pas` files get syntax colors, an outline (classes, methods), symbol search across your project and the Pastel framework (`Ctrl+T`), and go to definition: `Ctrl+click` a class or method name, or a unit in a `uses` clause to open that unit.

**Delphi keys** (in Pastel projects; turn off with `pastel.delphiShortcuts`):

| Key | |
|---|---|
| `F9` | Run |
| `Ctrl+F9` | Build |
| `F12` | Switch between a form (designer or `.pform`) and its code |
| `Ctrl+Shift+Up` / `Down` | Jump between a method's declaration and its body |

These replace VS Code's own F9 (toggle breakpoint) and F12 (go to definition) in Pastel projects. Breakpoints can still be set by clicking left of the line numbers, and `Ctrl+click` still goes to a definition.

## Settings

| Setting | Default | |
|---|---|---|
| `pastel.path` | `pastel` | Path to the `pastel` program |
| `pastel.checkWhileTyping` | `true` | Check `.pform` files while you type |
| `pastel.delphiShortcuts` | `true` | F9, Ctrl+F9, F12 and Ctrl+Shift+Up/Down as in Delphi |
| `pastel.serverUrl` | (empty) | Address for Send Request; empty: `localhost` with `[server] port` from `config.toml` |
