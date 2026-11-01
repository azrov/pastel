# Changelog

## 1.1.0

- The designer is laid out like Delphi's IDE: Structure and the Object Inspector (Properties and Events tabs, search, alphabetical) on the left, the form in a window frame in the middle, the Tool Palette in groups with a search box on the right, non-visual components in a tray under the form
- Free placement (`Layout = Free`): drop controls where they should be, drag to move (also into a panel), eight grips to resize, an 8 pixel grid (`Alt` places freely), `Ctrl+arrows` move by a pixel, `Shift+arrows` resize, align and same-size buttons for several controls; the position and size are shown while dragging
- Flow containers get grips for a fixed width and height too
- `Anchors` as check boxes; colors can also be typed (`#RRGGBB`); a double-click on an event writes its handler
- The form is shown at its real size (*Fit* shrinks a big one)


## 1.0.5

- Designer: properties the `.pform` does not set show their default — `Enabled`, `Visible` and a form's `Resizable` are ticked, `Style` says *(default: Primary)*; choosing the default again removes the line
- Designer: a **Name** row at the top of the properties, like Delphi's Object Inspector (the `.pas` code is renamed too)
- Designer: `BackgroundImage` and `FileName` offer the pictures in `assets/`
- Designer: changes are made one after the other, and a change that would leave the form's `object`/`end` lines unbalanced is refused
- A handler is created once, also after a quick second double-click, and before `initialization` in the unit

## 1.0.4

- Designer: select several controls (`Ctrl+click`) and change their common properties, delete, copy or cut them together
- Designer: put controls into a new row, column or card (⊞), take them out again (*Unwrap*); `Alt+Up`/`Down` moves a control among its neighbours
- Designer: a *Structure* list of every object, also the non-visual ones (timers, actions...)
- Designer: what `pastel check` finds is outlined on the form and listed under it
- Debugging: objects are shown as their real class with their properties; `TStringList`, `TList`, `TFPList` with their items; JSON values as JSON
- F5 in a library's file debugs the program that uses it, like F9

## 1.0.3

- Completion and go to definition know the units of packages (`pastel add`), read from the cache
- Links to the repository on GitHub

## 1.0.2

- The designer offers the icon names in a button's `Icon` field

## 1.0.1

- F9 (Run) in a library's file runs a program that uses it; with several, it asks once and remembers (*Pastel: Choose the Program to Run* asks again); with none, it offers the library's tests
- `.pform` files show a warning on rows whose controls do not fit the form

## 1.0.0

- The toolbox shows the controls of the libraries a project uses, and non-visual components (◇): timers, actions, data bindings and your own; adding one puts it at the top of the form
- Ready for the Marketplace and Open VSX; works with Pastel 1.0 (`pastel = "1.0"` projects)
- The form designer, Pascal code intelligence, tests, routes and tasks as in 0.9, now with a stable `pastel` tool behind them

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
