# Pastel for Visual Studio Code

Build cross-platform apps in Object Pascal with Pastel. This extension connects VS Code to the `pastel` command-line tool.

## Requirements

- The `pastel` program on your `PATH` (or set `pastel.path`). Check your setup with **Pastel: Check Setup**.
- [Free Pascal](https://www.freepascal.org/) 3.2 or newer.
- Recommended: the **Pascal** extension (`alefragnani.pascal`) for colors in `.pas` files, and **C/C++** (`ms-vscode.cpptools`) for debugging with F5.

## Features

**Run and build.** Press the **Pastel Run** button in the status bar, or use the commands *Pastel: Run*, *Build*, *Build Release*, *Build for Platform…* and *Clean*. `Ctrl+Shift+B` builds. Errors from your Pascal code and from `.pform` files appear in the Problems panel; click one to jump to the line.

**Live form preview.** Open a `.pform` file and press the preview button in the editor title. The form is drawn beside the editor and updates as you type, before you even save.

**Writing forms.** In `.pform` files you get:

- completion for control types (`object SaveButton: T…`), properties, and their values (`Align = Center`, `Style = Secondary`, event handler names from the form's `.pas` file)
- hover help for properties and controls
- mistakes underlined while you type, like an unknown property or a missing event handler
- a quick fix that adds a missing event handler to the form's code, ready to fill in
- `Ctrl+click` on an event handler (`OnClick = SaveClick`) to open its code
- the outline of the form in the Outline view, and snippets: `button`, `edit`, `label`, `row`, `column`, `card`

**New projects.** *Pastel: New Project…* creates an app or console project and opens it. New projects come with VS Code settings, so `Ctrl+Shift+B` builds and `F5` starts debugging.

## Settings

| Setting | Default | |
|---|---|---|
| `pastel.path` | `pastel` | Path to the `pastel` program |
| `pastel.checkWhileTyping` | `true` | Check `.pform` files while you type |
