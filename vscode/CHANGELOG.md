# Changelog

## 0.9.0

- The designer and its toolbox know the controls of your project (`src/controls/`, made with
  `pastel new control`): they come first in the toolbox, with their properties in the panel;
  saving a control updates the toolbox and the picture
- New controls in the toolbox and properties: `TGrid`, `TListView`, `TTreeView` (with `TGridColumn`
  children), `TDataBinding`

## 0.8.0

- Form designer: undo and redo (Ctrl+Z, Ctrl+Y), copy, cut, paste and duplicate controls
  (Ctrl+C/X/V/D; pasted controls get free names), rename a control with F2 or in the
  properties panel, and the form's `.pas` code is renamed with it
- Preview at phone, tablet and desktop sizes, and in the dark theme
- **Pastel: New Form…** (also in the Pastel panel): a dialog form with OK and Cancel, added to `main.pas`
- The toolbox and properties know the new controls: check boxes, switches, radio buttons, combo boxes,
  list boxes, memos, images, tabs, scroll boxes, progress bars, sliders, spinners, menus, actions, timers

## 0.7.0

- Pascal code intelligence from the project, the Pastel framework and the Free Pascal sources:
  completion after a dot (`NameEdit.` → `Text`, `SetFocus`, also through properties, function
  results, `[index]` and string helpers), names in scope, units in `uses`
- Hover with the declaration and its documentation comment; parameter hints while typing a call, with overloads
- Go to definition (also into the framework and Free Pascal), find all references, rename across the project
- Compiler errors underlined while typing: the unsaved text is compiled in the background
  (setting `pastel.compileWhileTyping`)
- Quick fixes: add the missing unit to `uses`; create the bodies of methods without one
  (*Pastel: Complete Class*, Ctrl+Shift+C like Delphi)

## 0.6.0

- Web APIs: **▶ Send** above every route (`Web.Get('/path', @Handler)`) sends a request to the running
  server and shows the answer; path parameters, a JSON body and the API key from `config.toml` are filled in
- Pastel panel: routes, jobs (`Every`, `DailyAt`) and database migrations of service and API projects;
  Run Migrations, Migration Status, New Migration…
- New Project offers "api": a web API with a database
- Setting `pastel.serverUrl` for Send Request

## 0.3.1

- "Pastel: Run Tests" command, task and button in the Pastel panel (runs `pastel test`)

## 0.3.0

- Pastel panel in the activity bar: Run/Build actions, forms (click to design), source files, project settings;
  "New Project" button when the folder has no project
- "Open Form Designer" in the right-click menus of the Explorer, the editor and editor tabs,
  and as a button on a form's .pas file
- Delphi keys in Pastel projects: F9 run, Ctrl+F9 build, F12 form/code, Ctrl+Shift+Up/Down declaration/body
  (setting: pastel.delphiShortcuts)
- Pascal: syntax colors, outline, symbol search in the project and the Pastel framework (Ctrl+T),
  go to definition, Ctrl+click on a unit in "uses" opens it

## 0.2.0

- Form designer: select controls, edit properties in a panel, drag to move, add from the toolbox, delete
- Selection follows the editor cursor, and the editor follows the designer
- Event buttons in the designer open a handler's code or create it
- Quick fixes create handlers with the right parameters (e.g. OnCloseQuery)
- "New Project" asks in a dialog whether to open the project, so the question is not missed

## 0.1.0

First version:

- Run, Build, Build Release, Build for Platform, Clean and Check Setup commands
- "Pastel Run" button in the status bar and in the editor title
- Build errors (from Pascal code and .pform files) in the Problems panel, with links to the line
- .pform files: syntax colors, completion of controls, properties and values, hover help,
  checks while typing, outline, Ctrl+click on an event handler to open its code
- Quick fix to add a missing event handler to the form's .pas file
- Live form preview beside the editor (updates as you type)
- New Project wizard
