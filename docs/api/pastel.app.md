# Pastel.App

The application: window, event loop, hot reload.

    Application.Initialize;
    Application.CreateForm(TMainForm, MainForm);
    Application.Run;

  Environment variables useful for development and tests:
    PASTEL_TEST_SCRIPT=file  run a script of UI actions, then quit
    PASTEL_HEADLESS=1        no window: draw into memory only (for tests/CI)

`uses Pastel.App;` · source: [framework/src/pastel.app.pas](../../framework/src/pastel.app.pas)

## Types

### TApplication

```pascal
type TApplication = class
```

| | |
|---|---|
| `procedure ProcessMessages` | One pass of the event loop: events, timers, threads, layout, paint. Long work in an event handler can call it to keep the window alive. |
| `constructor Create` |  |
| `destructor Destroy` |  |
| `procedure Initialize` |  |
| `procedure CreateForm(AFormClass: TFormClass; out AReference)` |  |
| `procedure Run` |  |
| `procedure Terminate` |  |
| `procedure Refresh` | Layout and paint now (used by tests and scripts). |
| `property MainForm: TForm` |  |
| `property Canvas: TCanvas32` |  |
| `property Terminated: Boolean` |  |

## Constants and variables

| | |
|---|---|
| `var Application: TApplication` |  |
