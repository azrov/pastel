# Pastel.Forms

Building forms from .pform data.

  The code Pastel generates for each .pform file registers the form's source
  here. When a form is created, its controls are built from that source and
  properties and events are set through RTTI, like Delphi does with .dfm.

`uses Pastel.Forms;` · source: [framework/src/pastel.forms.pas](../../framework/src/pastel.forms.pas)

## Types

### TFormSource

```pascal
type TFormSource = class
```

## Routines

### RegisterFormSource

```pascal
procedure RegisterFormSource(const AFormClassName: string; const ASource: string; const AFilePath: string)
```

Called by generated code.

### FindFormSource

```pascal
function FindFormSource(Form: TForm): TFormSource
```

The registered source for a form, searching its class hierarchy.

### BuildForm

```pascal
procedure BuildForm(Form: TForm; Root: TPFormNode)
```

Creates the controls described by Root on Form, then binds fields.
Raises EPFormError on problems (unknown type, property or event).

## Constants and variables

| | |
|---|---|
| `var StrictEvents: Boolean` | False: event handlers that do not exist are skipped instead of being an error. Used by tools that load a form without its code (preview, check). |
