# Pastel.Forms

Building forms from .pform data.

  The code Pastel generates for each .pform file registers the form's source
  here. When a form is created, its controls are built from that source and
  properties and events are set through RTTI, like Delphi does with .dfm.
  Internal unit: used by Pastel itself and by the code it generates; it
  may change between versions.

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

### CaptureState

```pascal
function CaptureState(Form: TForm): TStringList
```

What the user changed in the controls (typed text, checked boxes, chosen
items, the page of tabs), by control name; hot reload puts it back.

### RestoreState

```pascal
procedure RestoreState(Form: TForm; State: TStringList)
```

### BuildForm

```pascal
procedure BuildForm(Form: TForm; Root: TPFormNode)
```

Creates the controls described by Root on Form, then binds fields.
Raises EPFormError on problems (unknown type, property or event).

